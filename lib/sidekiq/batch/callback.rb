module Sidekiq
  class Batch
    module Callback
      class Worker
        include Sidekiq::Worker

        def perform(clazz, event, opts, bid, parent_bid)
          return unless %w(success complete).include?(event)
          clazz, method = clazz.split("#") if (clazz && clazz.class == String && clazz.include?("#"))
          method = "on_#{event}" if method.nil?
          status = Sidekiq::Batch::Status.new(bid)

          if clazz && object = Object.const_get(clazz)
            instance = object.new
            instance.send(method, status, opts) if instance.respond_to?(method)
          end
        end
      end

      class Finalize
        def dispatch status, opts
          bid = opts["bid"]
          callback_bid = status.bid
          event = opts["event"].to_sym
          callback_batch = bid != callback_bid

          Sidekiq.logger.debug {"Finalize #{event} batch id: #{opts["bid"]}, callback batch id: #{callback_bid} callback_batch #{callback_batch}"}

          batch_status = Status.new bid
          send(event, bid, batch_status, batch_status.parent_bid)


          # Different events are run in different callback batches
          Sidekiq::Batch.cleanup_redis callback_bid if callback_batch
          Sidekiq::Batch.cleanup_redis bid if event == :success
        end

        def success(bid, status, parent_bid)
          return unless parent_bid

          _, _, success, _, complete, pending, children, failure = Sidekiq.redis do |r|
            r.multi do |pipeline|
              pipeline.sadd("BID-#{parent_bid}-success", bid)
              pipeline.expire("BID-#{parent_bid}-success", Sidekiq::Batch::BID_EXPIRE_TTL)
              pipeline.scard("BID-#{parent_bid}-success")
              pipeline.sadd("BID-#{parent_bid}-complete", bid)
              pipeline.scard("BID-#{parent_bid}-complete")
              pipeline.hincrby("BID-#{parent_bid}", "pending", 0)
              pipeline.hincrby("BID-#{parent_bid}", "children", 0)
              pipeline.scard("BID-#{parent_bid}-failed")
            end
          end
          # if job finished successfully and parent batch completed call parent complete callback
          # Success callback is called after complete callback
          if complete == children && pending == failure
            Sidekiq.logger.debug {"Finalize parent complete bid: #{parent_bid}"}
            Batch.enqueue_callbacks(:complete, parent_bid)
          end

        end

        def complete(bid, status, parent_bid)
          pending, children, success = Sidekiq.redis do |r|
            r.multi do |pipeline|
              pipeline.hincrby("BID-#{bid}", "pending", 0)
              pipeline.hincrby("BID-#{bid}", "children", 0)
              pipeline.scard("BID-#{bid}-success")
            end
          end

          # if we batch was successful run success callback
          if pending.to_i.zero? && children == success
            Batch.enqueue_callbacks(:success, bid)

          elsif parent_bid
            # if batch was not successfull check and see if its parent is complete
            # if the parent is complete we trigger the complete callback
            # We don't want to run this if the batch was successfull because the success
            # callback may add more jobs to the parent batch

            Sidekiq.logger.debug {"Finalize parent complete bid: #{parent_bid}"}
            _, complete, pending, children, failure = Sidekiq.redis do |r|
              r.multi do |pipeline|
                pipeline.sadd("BID-#{parent_bid}-complete", bid)
                pipeline.scard("BID-#{parent_bid}-complete")
                pipeline.hincrby("BID-#{parent_bid}", "pending", 0)
                pipeline.hincrby("BID-#{parent_bid}", "children", 0)
                pipeline.scard("BID-#{parent_bid}-failed")
              end
            end
            if complete == children && pending == failure
              Batch.enqueue_callbacks(:complete, parent_bid)
            end
          end
        end

        def cleanup_redis bid, callback_bid=nil
          Sidekiq::Batch.cleanup_redis bid
          Sidekiq::Batch.cleanup_redis callback_bid if callback_bid
        end
      end
    end
  end
end
