module Sidekiq
  class Batch
    module Callback
      class Worker
        include Sidekiq::Worker

        def perform(clazz, event, opts, bid)
          return unless %w(success complete).include?(event)
          clazz, method = clazz.split('#') if (clazz.class == "string" && clazz.include?("#"))
          method = "on_#{event}" if method.nil?
          instance = clazz.constantize rescue nil
          instance.new.send(method, Sidekiq::Batch::Status.new(bid), opts) rescue nil
        end
      end

      class << self
        def call_if_needed(event, bid)
          needed = Sidekiq.redis do |r|
            r.multi do
              r.hget("BID-#{bid}", event)
              r.hset("BID-#{bid}", event, true)
            end
          end
          return if 'true' == needed[0]
          callback, opts, queue = Sidekiq.redis do |r|
            r.hmget("BID-#{bid}",
                    "callback_#{event}", "callback_#{event}_opts",
                    'callback_queue')
          end
          return unless callback
          opts    = JSON.parse(opts) if opts
          opts  ||= {}
          queue ||= 'default'
          Sidekiq::Client.push('class' => Sidekiq::Batch::Callback::Worker,
                               'args' => [callback, event, opts, bid],
                               'queue' => queue)
        ensure
          Sidekiq::Batch.cleanup_redis(bid) if event == :success
        end
      end
    end
  end
end
