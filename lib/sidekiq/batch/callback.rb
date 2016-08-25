module Sidekiq
  class Batch
    module Callback
      class Worker
        include Sidekiq::Worker

        def perform(clazz, event, opts, bid)
          return unless %w(success complete).include?(event)
          instance = clazz.constantize.send(:new) rescue nil
          return unless instance
          instance.send("on_#{event}", Status.new(bid), opts) rescue nil
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
        end
      end
    end
  end
end
