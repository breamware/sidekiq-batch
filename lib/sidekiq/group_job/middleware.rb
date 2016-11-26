module Sidekiq
  class GroupJob
    module Middleware
      class ClientMiddleware
        def call(_worker, msg, _queue, _redis_pool = nil)
          if (bid = Thread.current[:bid])
            GroupJob.increment_job_queue(bid) if (msg[:bid] = bid)
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
              GroupJob.process_successful_job(bid)
            rescue
              GroupJob.process_failed_job(bid, msg['jid'])
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
            chain.add Sidekiq::GroupJob::Middleware::ClientMiddleware
          end
        end
        Sidekiq.configure_server do |config|
          config.client_middleware do |chain|
            chain.add Sidekiq::GroupJob::Middleware::ClientMiddleware
          end
          config.server_middleware do |chain|
            chain.add Sidekiq::GroupJob::Middleware::ServerMiddleware
          end
        end
        Sidekiq::Worker.send(:define_method, 'bid') do
          Thread.current[:bid]
        end
        Sidekiq::Worker.send(:define_method, 'group_job') do
          Sidekiq::GroupJob.new(Thread.current[:bid]) if Thread.current[:bid]
        end
      end
    end
  end
end

Sidekiq::GroupJob::Middleware.configure
