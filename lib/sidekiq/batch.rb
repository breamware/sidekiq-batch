require 'securerandom'
require 'sidekiq'

require 'sidekiq/batch/callback'
require 'sidekiq/batch/middleware'
require 'sidekiq/batch/status'
require 'sidekiq/batch/version'

module Sidekiq
  class Batch
    class NoBlockGivenError < StandardError; end

    attr_reader :bid, :description, :callback_queue

    def initialize(existing_bid = nil)
      @bid = existing_bid || SecureRandom.urlsafe_base64(10)
      Sidekiq.redis { |r| r.hset("BID-#{bid}", 'created_at', Time.now) }
    end

    def description=(description)
      @description = description
      Sidekiq.redis { |r| r.hset("BID-#{bid}", 'description', description) }
    end

    def callback_queue=(callback_queue)
      @callback_queue = callback_queue
      Sidekiq.redis { |r| r.hset("BID-#{bid}", 'callback_queue', callback_queue) }
    end

    def on(event, callback, options = {})
      return unless %w(success complete).include?(event.to_s)
      Sidekiq.redis do |r|
        r.hset("BID-#{bid}", "callback_#{event}", callback)
        r.hset("BID-#{bid}", "callback_#{event}_opts", options.to_json)
      end
    end

    def jobs
      raise NoBlockGivenError unless block_given?

      Sidekiq.redis { |r| r.incr("BID-#{bid}-to_process") }
      Thread.current[:bid] = bid
      yield
      Sidekiq.redis { |r| r.decr("BID-#{bid}-to_process") }
    end

    class << self
      def process_failed_job(bid, jid)
        to_process = Sidekiq.redis do |r|
          r.multi do
            r.sadd("BID-#{bid}-failed", jid)
            r.scard("BID-#{bid}-failed")
            r.get("BID-#{bid}-to_process")
          end
        end
        if to_process[2].to_i == to_process[1].to_i
          Callback.call_if_needed(:complete, bid)
        end
      end

      def process_successful_job(bid)
        out = Sidekiq.redis do |r|
          r.multi do
            r.decr("BID-#{bid}-to_process")
            r.scard("BID-#{bid}-failed")
            r.decr("BID-#{bid}-pending")
          end
        end

        Callback.call_if_needed(:success, bid) if out[0].to_i.zero?
        Callback.call_if_needed(:complete, bid) if out[1].to_i == out[0].to_i

        cleanup_redis(bid)
      end

      def cleanup_redis(bid)
        Sidekiq.redis do |r|
          r.del("BID-#{bid}",
                "BID-#{bid}-to_process",
                "BID-#{bid}-pending",
                "BID-#{bid}-total",
                "BID-#{bid}-failed")
        end
      end

      def increment_job_queue(bid)
        Sidekiq.redis do |r|
          r.multi do
            r.incr("BID-#{bid}-to_process")
            r.incr("BID-#{bid}-pending")
            r.incr("BID-#{bid}-total")
          end
        end
      end
    end
  end
end
