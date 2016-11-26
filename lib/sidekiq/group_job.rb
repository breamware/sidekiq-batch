require 'securerandom'
require 'sidekiq'

require 'sidekiq/group_job/callback'
require 'sidekiq/group_job/middleware'
require 'sidekiq/group_job/status'
require 'sidekiq/group_job/version'

module Sidekiq
  class GroupJob
    class NoBlockGivenError < StandardError; end

    BID_EXPIRE_TTL = 108_000

    attr_reader :bid, :description, :callback_queue

    def initialize(existing_bid = nil)
      @bid = existing_bid || SecureRandom.urlsafe_base64(10)
      Sidekiq.redis do |r|
        r.multi do
          r.hset("BID-#{bid}", 'created_at', Time.now)
          r.expire("BID-#{bid}", BID_EXPIRE_TTL)
        end
      end
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
          r.hset("BID-#{bid}", "callback_#{event}", callback)
          r.hset("BID-#{bid}", "callback_#{event}_opts", options.to_json)
          r.expire("BID-#{bid}", BID_EXPIRE_TTL)
        end
      end
    end

    def jobs
      raise NoBlockGivenError unless block_given?

      Sidekiq.redis { |r| r.hincrby("BID-#{bid}", 'to_process', 1) }
      Thread.current[:bid] = bid
      yield
      Thread.current[:bid] = nil
      Sidekiq.redis { |r| r.hincrby("BID-#{bid}", 'to_process', -1) }
    end

    private

    def persist_bid_attr(attribute, value)
      Sidekiq.redis do |r|
        r.multi do
          r.hset("BID-#{bid}", attribute, value)
          r.expire("BID-#{bid}", BID_EXPIRE_TTL)
        end
      end
    end

    class << self
      def process_failed_job(bid, jid)
        to_process = Sidekiq.redis do |r|
          r.multi do
            r.sadd("BID-#{bid}-failed", jid)
            r.scard("BID-#{bid}-failed")
            r.hget("BID-#{bid}", 'to_process')
            r.expire("BID-#{bid}-failed", BID_EXPIRE_TTL)
          end
        end
        if to_process[2].to_i == to_process[1].to_i
          Callback.call_if_needed(:complete, bid)
        end
      end

      def process_successful_job(bid)
        out = Sidekiq.redis do |r|
          r.multi do
            r.hincrby("BID-#{bid}", 'to_process', -1)
            r.scard("BID-#{bid}-failed")
            r.hincrby("BID-#{bid}", 'pending', -1)
            r.expire("BID-#{bid}", BID_EXPIRE_TTL)
          end
        end

        puts "processed process_successful_job"
        Callback.call_if_needed(:complete, bid) if out[1].to_i == out[0].to_i
        Callback.call_if_needed(:success, bid) if out[0].to_i.zero?
      end

      def cleanup_redis(bid)
        Sidekiq.redis do |r|
          r.del("BID-#{bid}",
                "BID-#{bid}-failed")
        end
      end

      def increment_job_queue(bid)
        Sidekiq.redis do |r|
          r.multi do
            %w(to_process pending total).each do |c|
              r.hincrby("BID-#{bid}", c, 1)
            end
            r.expire("BID-#{bid}", BID_EXPIRE_TTL)
          end
        end
      end
    end
  end
end
