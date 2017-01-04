require 'securerandom'
require 'sidekiq'

require 'sidekiq/batch/callback'
require 'sidekiq/batch/middleware'
require 'sidekiq/batch/status'
require 'sidekiq/batch/version'

module Sidekiq
  class Batch
    class NoBlockGivenError < StandardError; end

    BID_EXPIRE_TTL = 108_000

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

    def on(event, callback, options = {})
      return unless %w(success complete).include?(event.to_s)
      Sidekiq.redis do |r|
        r.multi do
          r.hset(@bidkey, "callback_#{event}", callback)
          r.hset(@bidkey, "callback_#{event}_opts", options.to_json)
          r.expire(@bidkey, BID_EXPIRE_TTL)
        end
      end
    end

    def jobs
      raise NoBlockGivenError unless block_given?

      bid_data, Thread.current[:bid_data] = Thread.current[:bid_data], []

      begin
        if !@existing && !@initialized
          parent_bid = Thread.current[:bid].bid if Thread.current[:bid]

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
          parent = Thread.current[:bid]
          Thread.current[:bid] = self
          yield
        ensure
          Thread.current[:bid] = parent
        end

        return [] unless @ready_to_queue.size > 0

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
      puts "RtQ: " + @ready_to_queue.to_s
      puts "JID: " + jid.to_s
      @ready_to_queue << jid
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
            r.sadd("BID-#{bid}-failed", [jid])

            r.hincrby("BID-#{bid}", "pending", 0)
            r.scard("BID-#{bid}-failed")
            r.hincrby("BID-#{bid}", "children", 0)
            r.scard("BID-#{bid}-complete")

            r.expire("BID-#{bid}-failed", BID_EXPIRE_TTL)
          end
        end

        enqueue_callback(:complete, bid) if pending.to_i == failed.to_i && children == complete
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

            r.hdel("BID-#{bid}-failed", jid)
            r.srem("BID-#{bid}-jids", jid)
            r.expire("BID-#{bid}", BID_EXPIRE_TTL)
          end
        end

        puts "processed process_successful_job"

        enqueue_callback(:complete, bid) if pending.to_i == failed.to_i && children == complete
        enqueue_callback(:success, bid) if pending.to_i.zero? && children == success
      end

      def enqueue_callback(event, bid)
        needed, _, callback, opts, queue, parent_bid = Sidekiq.redis do |r|
          r.multi do
            r.hget("BID-#{bid}", event)
            r.hset("BID-#{bid}", event, true)
            r.hget("BID-#{bid}", "callback_#{event}")
            r.hget("BID-#{bid}", "callback_#{event}_opts")
            r.hget("BID-#{bid}", "callback_queue")
            r.hget("BID-#{bid}", "parent_bid")
          end
        end
        return if 'true' == needed
        return unless callback

        begin
          parent_bid = !parent_bid || parent_bid.empty? ? nil : parent_bid    # Basically parent_bid.blank?
          opts    = JSON.parse(opts) if opts
          opts  ||= {}
          queue ||= 'default'
          Sidekiq::Client.push('class' => Sidekiq::Batch::Callback::Worker,
                               'args' => [callback, event, opts, bid, parent_bid],
                               'queue' => queue)
        ensure
          cleanup_redis(bid) if event == :success
        end
      end

      def cleanup_redis(bid)
        Sidekiq.redis do |r|
          r.del("BID-#{bid}",
                "BID-#{bid}-failed")
        end
      end


    end
  end
end
