module Sidekiq
  class Batch
    module Middleware
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

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Batch::Middleware::ClientMiddleware
  end
  config.server_middleware do |chain|
    chain.add Sidekiq::Batch::Middleware::ClientMiddleware
    chain.add Sidekiq::Batch::Middleware::ServerMiddleware
  end
end
