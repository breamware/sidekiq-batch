module Sidekiq
  class Batch
    module Callback
      class Worker
        include Sidekiq::Worker

        def perform(clazz, event, opts, bid, parent_bid)
          return unless %w(success complete).include?(event)
          clazz, method = clazz.split("#") if (clazz.class == String && clazz.include?("#"))
          method = "on_#{event}" if method.nil?
          status = Sidekiq::Batch::Status.new(bid)
          clazz.constantize.new.send(method, status, opts) rescue nil

          send(event.to_sym, bid, status, parent_bid)
        end


        def success(bid, status, parent_bid)
          if (parent_bid)
            _, _, success, pending, kids = Sidekiq.redis do |r|
              r.multi do
                r.sadd("BID-#{parent_bid}-success", bid)
                r.expire("BID-#{parent_bid}-success", Sidekiq::Batch::BID_EXPIRE_TTL)
                r.scard("BID-#{parent_bid}-success")
                r.hincrby("BID-#{parent_bid}", "pending", 0)
                r.hincrby("BID-#{parent_bid}", "kids", 0)
              end
            end

            Batch.enqueue_callback(:success, parent_bid) if pending.to_i.zero? && kids == success
          end

          Sidekiq.redis do |r|
            r.multi do
              r.del "BID-#{bid}-success", "BID-#{bid}-complete", "BID-#{bid}-jids", "BID-#{bid}-failed"
            end
          end
        end

        def complete(bid, status, parent_bid)
          if (parent_bid)
            _, complete, pending, kids, failure = Sidekiq.redis do |r|
              r.multi do
                r.sadd("BID-#{parent_bid}-complete", bid)
                r.scard("BID-#{parent_bid}-complete")
                r.hincrby("BID-#{parent_bid}", "pending", 0)
                r.hincrby("BID-#{parent_bid}", "kids", 0)
                r.hlen("BID-#{parent_bid}-failed")
              end
            end

            Batch.enqueue_callback(:complete, parent_bid) if complete == kids && pending == failure
          end
        end

      end
    end
  end
end
