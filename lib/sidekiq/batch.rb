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
      Sidekiq.redis { |r| r.set("#{bid}-to_process", 0) }
    end

    def description=(description)
      @description = description
      Sidekiq.redis { |r| r.hset(bid, 'description', description) }
    end

    def callback_queue=(callback_queue)
      @callback_queue = callback_queue
      Sidekiq.redis { |r| r.hset(bid, 'callback_queue', callback_queue) }
    end

    def on(event, callback, options = {})
      return unless %w(success complete).include?(event.to_s)
      Sidekiq.redis do |r|
        r.hset(bid, "callback_#{event}", callback)
        r.hset(bid, "callback_#{event}_opts", options.to_json)
      end
    end

    def jobs
      raise NoBlockGivenError unless block_given?

      Batch.increment_job_queue(bid)
      Thread.current[:bid] = bid
      yield
      Batch.process_successful_job(bid)
    end

    class << self
      def process_failed_job(bid, jid)
        to_process = Sidekiq.redis do |r|
          r.multi do
            r.sadd("#{bid}-failed", jid)
            r.scard("#{bid}-failed")
            r.get("#{bid}-to_process")
          end
        end
        if to_process[2].to_i == to_process[1].to_i
          Callback.call_if_needed(:complete, bid)
        end
      end

      def process_successful_job(bid)
        to_process = Sidekiq.redis do |r|
          r.multi do
            r.decr("#{bid}-to_process")
            r.get("#{bid}-to_process")
          end
        end
        if to_process[1].to_i == 0
          Callback.call_if_needed(:success, bid)
          Callback.call_if_needed(:complete, bid)
        end
      end

      def increment_job_queue(bid)
        Sidekiq.redis { |r| r.incr("#{bid}-to_process") }
      end
    end
  end
end
