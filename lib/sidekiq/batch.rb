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
        r.multi do |pipeline|
          pipeline.sadd(callback_key, JSON.unparse({
            callback: callback,
            opts: options
          }))
          pipeline.expire(callback_key, BID_EXPIRE_TTL)
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
            r.multi do |pipeline|
              pipeline.hset(@bidkey, "created_at", @created_at)
              pipeline.hset(@bidkey, "parent_bid", parent_bid.to_s) if parent_bid
              pipeline.expire(@bidkey, BID_EXPIRE_TTL)
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
          r.multi do |pipeline|
            if parent_bid
              pipeline.hincrby("BID-#{parent_bid}", "children", 1)
              pipeline.hincrby("BID-#{parent_bid}", "total", @ready_to_queue.size)
              pipeline.expire("BID-#{parent_bid}", BID_EXPIRE_TTL)
            end

            pipeline.hincrby(@bidkey, "pending", @ready_to_queue.size)
            pipeline.hincrby(@bidkey, "total", @ready_to_queue.size)
            pipeline.expire(@bidkey, BID_EXPIRE_TTL)

            pipeline.sadd(@bidkey + "-jids", @ready_to_queue)
            pipeline.expire(@bidkey + "-jids", BID_EXPIRE_TTL)
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
        r.multi do |pipeline|
          pipeline.hset(@bidkey, attribute, value)
          pipeline.expire(@bidkey, BID_EXPIRE_TTL)
        end
      end
    end

    class << self
      def process_failed_job(bid, jid)
        _, pending, failed, children, complete, parent_bid = Sidekiq.redis do |r|
          r.multi do |pipeline|
            pipeline.sadd("BID-#{bid}-failed", jid)

            pipeline.hincrby("BID-#{bid}", "pending", 0)
            pipeline.scard("BID-#{bid}-failed")
            pipeline.hincrby("BID-#{bid}", "children", 0)
            pipeline.scard("BID-#{bid}-complete")
            pipeline.hget("BID-#{bid}", "parent_bid")

            pipeline.expire("BID-#{bid}-failed", BID_EXPIRE_TTL)
          end
        end

        # if the batch failed, and has a parent, update the parent to show one pending and failed job
        if parent_bid
          Sidekiq.redis do |r|
            r.multi do |pipeline|
              pipeline.hincrby("BID-#{parent_bid}", "pending", 1)
              pipeline.sadd("BID-#{parent_bid}-failed", jid)
              pipeline.expire("BID-#{parent_bid}-failed", BID_EXPIRE_TTL)
            end
          end
        end

        if pending.to_i == failed.to_i && children == complete
          enqueue_callbacks(:complete, bid)
        end
      end

      def process_successful_job(bid, jid)
        failed, pending, children, complete, success, total, parent_bid = Sidekiq.redis do |r|
          r.multi do |pipeline|
            pipeline.scard("BID-#{bid}-failed")
            pipeline.hincrby("BID-#{bid}", "pending", -1)
            pipeline.hincrby("BID-#{bid}", "children", 0)
            pipeline.scard("BID-#{bid}-complete")
            pipeline.scard("BID-#{bid}-success")
            pipeline.hget("BID-#{bid}", "total")
            pipeline.hget("BID-#{bid}", "parent_bid")

            pipeline.srem("BID-#{bid}-failed", jid)
            pipeline.srem("BID-#{bid}-jids", jid)
            pipeline.expire("BID-#{bid}", BID_EXPIRE_TTL)
          end
        end

        all_success = pending.to_i.zero? && children == success
        # if complete or successfull call complete callback (the complete callback may then call successful)
        if (pending.to_i == failed.to_i && children == complete) || all_success
          enqueue_callbacks(:complete, bid)
          enqueue_callbacks(:success, bid) if all_success
        end
      end

      def enqueue_callbacks(event, bid)
        batch_key = "BID-#{bid}"
        callback_key = "#{batch_key}-callbacks-#{event}"
        already_processed, _, callbacks, queue, parent_bid, callback_batch = Sidekiq.redis do |r|
          r.multi do |pipeline|
            pipeline.hget(batch_key, event)
            pipeline.hset(batch_key, event, true)
            pipeline.smembers(callback_key)
            pipeline.hget(batch_key, "callback_queue")
            pipeline.hget(batch_key, "parent_bid")
            pipeline.hget(batch_key, "callback_batch")
          end
        end

        return if already_processed == 'true'

        queue ||= "default"
        parent_bid = !parent_bid || parent_bid.empty? ? nil : parent_bid    # Basically parent_bid.blank?
        callback_args = callbacks.reduce([]) do |memo, jcb|
          cb = Sidekiq.load_json(jcb)
          memo << [cb['callback'], event, cb['opts'], bid, parent_bid]
        end

        opts = {"bid" => bid, "event" => event}

        # Run callback batch finalize synchronously
        if callback_batch
          # Extract opts from cb_args or use current
          # Pass in stored event as callback finalize is processed on complete event
          cb_opts = callback_args.first&.at(2) || opts

          Sidekiq.logger.debug {"Run callback batch bid: #{bid} event: #{event} args: #{callback_args.inspect}"}
          # Finalize now
          finalizer = Sidekiq::Batch::Callback::Finalize.new
          status = Status.new bid
          finalizer.dispatch(status, cb_opts)

          return
        end

        Sidekiq.logger.debug {"Enqueue callback bid: #{bid} event: #{event} args: #{callback_args.inspect}"}

        if callback_args.empty?
          # Finalize now
          finalizer = Sidekiq::Batch::Callback::Finalize.new
          status = Status.new bid
          finalizer.dispatch(status, opts)
        else
          # Otherwise finalize in sub batch complete callback
          cb_batch = self.new
          cb_batch.callback_batch = true
          Sidekiq.logger.debug {"Adding callback batch: #{cb_batch.bid} for batch: #{bid}"}
          cb_batch.on(:complete, "Sidekiq::Batch::Callback::Finalize#dispatch", opts)
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
