module Sidekiq
  class Batch
    module Middleware
      def self.extended(base)
        base.class_eval do
          register_middleware
        end
      end

      def register_middleware
        Sidekiq.configure_server do |config|
          config.client_middleware do |chain|
            chain.add ClientMiddleware
          end
          config.server_middleware do |chain|
            chain.add ClientMiddleware
            chain.add ServerMiddleware
          end
        end
      end

      class ClientMiddleware
        def call(_worker, msg, _queue, _redis_pool = nil)
          if (bid = Thread.current[:bid])
            Batch.increment_job_queue(bid) if (msg[:bid] = bid)
          end
          yield
        end
      end

      class ServerMiddleware
        def call(_worker, msg, _queue)
          if (bid = msg['bid'])
            begin
              yield
              Batch.process_successful_job(bid)
            rescue
              Batch.process_failed_job(bid, msg['jid'])
              raise
            end
          else
            yield
          end
        end
      end
    end
  end
end

Sidekiq::Batch::Middleware.send(:extend, Sidekiq::Batch::Middleware)
