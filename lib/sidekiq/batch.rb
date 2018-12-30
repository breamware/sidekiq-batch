require 'securerandom'
require 'sidekiq'

require 'sidekiq/batch/callback'
require 'sidekiq/batch/middleware'
require 'sidekiq/batch/status'
require 'sidekiq/batch/version'

module Sidekiq
  class Batch
    class NoBlockGivenError < StandardError; end

    BID_EXPIRE_TTL = 2_592_000

    attr_reader :bid, :description, :callback_queue, :created_at

    def initialize(existing_bid = nil)
      @bid = existing_bid || SecureRandom.urlsafe_base64(10)
      @existing = !(!existing_bid || existing_bid.empty?)  # Basically existing_bid.present?
      @initialized = false
      @created_at = Time.now.utc.to_f
      @bidkey = "BID-" + @bid.to_s
      @ready_to_queue = []
    end

    def description=(description)
      @description = description
      persist_bid_attr('description', description)
    end

    def callback_queue=(callback_queue)
      @callback_queue = callback_queue
      persist_bid_attr('callback_queue', callback_queue)
    end

    def callback_batch=(callback_batch)
      @callback_batch = callback_batch
      persist_bid_attr('callback_batch', callback_batch)
    end

    def on(event, callback, options = {})
      return unless %w(success complete).include?(event.to_s)
      callback_key = "#{@bidkey}-callbacks-#{event}"
      Sidekiq.redis do |r|
        r.multi do
          r.sadd(callback_key, JSON.unparse({
            callback: callback,
            opts: options
          }))
          r.expire(callback_key, BID_EXPIRE_TTL)
        end
      end
    end

    def jobs
      raise NoBlockGivenError unless block_given?

      bid_data, Thread.current[:bid_data] = Thread.current[:bid_data], []

      begin
        if !@existing && !@initialized
          parent_bid = Thread.current[:batch].bid if Thread.current[:batch]

          Sidekiq.redis do |r|
            r.multi do
              r.hset(@bidkey, "created_at", @created_at)
              r.hset(@bidkey, "parent_bid", parent_bid.to_s) if parent_bid
              r.expire(@bidkey, BID_EXPIRE_TTL)
            end
          end

          @initialized = true
        end

        @ready_to_queue = []

        begin
          parent = Thread.current[:batch]
          Thread.current[:batch] = self
          yield
        ensure
          Thread.current[:batch] = parent
        end

        return [] if @ready_to_queue.size == 0

        Sidekiq.redis do |r|
          r.multi do
            if parent_bid
              r.hincrby("BID-#{parent_bid}", "children", 1)
              r.expire("BID-#{parent_bid}", BID_EXPIRE_TTL)
            end

            r.hincrby(@bidkey, "pending", @ready_to_queue.size)
            r.hincrby(@bidkey, "total", @ready_to_queue.size)
            r.expire(@bidkey, BID_EXPIRE_TTL)

            r.sadd(@bidkey + "-jids", @ready_to_queue)
            r.expire(@bidkey + "-jids", BID_EXPIRE_TTL)
          end
        end

        @ready_to_queue
      ensure
        Thread.current[:bid_data] = bid_data
      end
    end

    def increment_job_queue(jid)
      @ready_to_queue << jid
    end

    def invalidate_all
      Sidekiq.redis do |r|
        r.setex("invalidated-bid-#{bid}", BID_EXPIRE_TTL, 1)
      end
    end

    def parent_bid
      Sidekiq.redis do |r|
        r.hget(@bidkey, "parent_bid")
      end
    end

    def parent
      if parent_bid
        Sidekiq::Batch.new(parent_bid)
      end
    end

    def valid?(batch = self)
      valid = !Sidekiq.redis { |r| r.exists("invalidated-bid-#{batch.bid}") }
      batch.parent ? valid && valid?(batch.parent) : valid
    end

    private

    def persist_bid_attr(attribute, value)
      Sidekiq.redis do |r|
        r.multi do
          r.hset(@bidkey, attribute, value)
          r.expire(@bidkey, BID_EXPIRE_TTL)
        end
      end
    end

    class << self
      def process_failed_job(bid, jid)
        _, pending, failed, children, complete = Sidekiq.redis do |r|
          r.multi do
            r.sadd("BID-#{bid}-failed", jid)

            r.hincrby("BID-#{bid}", "pending", 0)
            r.scard("BID-#{bid}-failed")
            r.hincrby("BID-#{bid}", "children", 0)
            r.scard("BID-#{bid}-complete")

            r.expire("BID-#{bid}-failed", BID_EXPIRE_TTL)
          end
        end

        enqueue_callbacks(:complete, bid) if pending.to_i == failed.to_i && children == complete
      end

      def process_successful_job(bid, jid)
        failed, pending, children, complete, success, total, parent_bid = Sidekiq.redis do |r|
          r.multi do
            r.scard("BID-#{bid}-failed")
            r.hincrby("BID-#{bid}", "pending", -1)
            r.hincrby("BID-#{bid}", "children", 0)
            r.scard("BID-#{bid}-complete")
            r.scard("BID-#{bid}-success")
            r.hget("BID-#{bid}", "total")
            r.hget("BID-#{bid}", "parent_bid")

            r.srem("BID-#{bid}-failed", jid)
            r.srem("BID-#{bid}-jids", jid)
            r.expire("BID-#{bid}", BID_EXPIRE_TTL)
          end
        end

        Sidekiq.logger.debug {"Job success: #{jid} in batch #{bid} children: #{children} complete #{complete} success #{success} pending #{pending} failed #{failed}"}

        enqueue_callbacks(:complete, bid) if pending.to_i == failed.to_i && children == complete
        enqueue_callbacks(:success, bid) if pending.to_i.zero? && children == success
      end

      def enqueue_callbacks(event, bid)
        batch_key = "BID-#{bid}"
        callback_key = "#{batch_key}-callbacks-#{event}"
        needed, _, callbacks, queue, parent_bid, callback_batch = Sidekiq.redis do |r|
          r.multi do
            r.hget(batch_key, event)
            r.hset(batch_key, event, true)
            r.smembers(callback_key)
            r.hget(batch_key, "callback_queue")
            r.hget(batch_key, "parent_bid")
            r.hget(batch_key, "callback_batch")
          end
        end
        Sidekiq.logger.debug {"Enqueue callback info: bid: #{bid} event: #{event} needed: #{needed}"} if needed == 'true'

        return if needed == 'true'

        queue ||= "default"
        parent_bid = !parent_bid || parent_bid.empty? ? nil : parent_bid    # Basically parent_bid.blank?
        callback_args = callbacks.reduce([]) do |memo, jcb|
          cb = Sidekiq.load_json(jcb)
          memo << [cb['callback'], event, cb['opts'], bid, parent_bid]
        end

        Sidekiq.logger.debug {"Enqueue callback bid: #{bid} event: #{event} args: #{callback_args.inspect}"}

        if callback_batch
          push_callbacks callback_args, queue unless callback_args.empty?
          return
        end

        opts = {"bid" => bid, "event" => event}

        if callback_args.empty?
          # Finalize now
          finalizer = Sidekiq::Batch::Callback::Finalize.new
          status = Status.new bid
          finalizer.dispatch(status, opts)
        else
          # Otherwise finalize in sub batch success callback
          cb_batch = self.new
          cb_batch.callback_batch = true
          Sidekiq.logger.debug {"Adding callback batch: #{cb_batch.bid} for batch: #{bid}"}
          cb_batch.on(:success, "Sidekiq::Batch::Callback::Finalize#dispatch", opts)
          cb_batch.jobs do
            push_callbacks callback_args, queue
          end
        end
      end

      def cleanup_redis(bid)
        Sidekiq.logger.debug {"Cleaning redis of batch #{bid}"}
        Sidekiq.redis do |r|
          r.del(
            "BID-#{bid}",
            "BID-#{bid}-callbacks-complete",
            "BID-#{bid}-callbacks-success",
            "BID-#{bid}-failed",

            "BID-#{bid}-success",
            "BID-#{bid}-complete",
            "BID-#{bid}-jids",
          )
        end
      end

    private

      def push_callbacks args, queue
        Sidekiq::Client.push_bulk(
          'class' => Sidekiq::Batch::Callback::Worker,
          'args' => args,
          'queue' => queue
        ) unless args.empty?
      end
    end
  end
end
