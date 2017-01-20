module Sidekiq
  class Batch
    module Middleware
      class ClientMiddleware
        def call(_worker, msg, _queue, _redis_pool = nil)
          if (batch = Thread.current[:bid])
            batch.increment_job_queue([ msg['jid'] ]) if (msg[:bid] = batch.bid)
          end
          yield
        end
      end

      class ServerMiddleware
        def call(_worker, msg, _queue)
          if (bid = msg['bid'])
            begin
              Thread.current[:bid] = bid
              yield
              Thread.current[:bid] = nil
              Batch.process_successful_job(bid, msg['jid'])
            rescue
              Batch.process_failed_job(bid, msg['jid'])
              raise
            ensure
              Thread.current[:bid] = nil
            end
          else
            yield
          end
        end
      end

      def self.configure
        Sidekiq.configure_client do |config|
          config.client_middleware do |chain|
            chain.add Sidekiq::Batch::Middleware::ClientMiddleware
          end
        end
        Sidekiq.configure_server do |config|
          config.client_middleware do |chain|
            chain.add Sidekiq::Batch::Middleware::ClientMiddleware
          end
          config.server_middleware do |chain|
            chain.add Sidekiq::Batch::Middleware::ServerMiddleware
          end
        end
        Sidekiq::Worker.send(:define_method, 'bid') do
          Thread.current[:bid]
        end
        Sidekiq::Worker.send(:define_method, 'batch') do
          Sidekiq::Batch.new(Thread.current[:bid].bid) if Thread.current[:bid]
        end
      end
    end
  end
end

Sidekiq::Batch::Middleware.configure
