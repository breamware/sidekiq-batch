require 'spec_helper'
require 'sidekiq/batch'
require 'sidekiq/testing'

Sidekiq::Testing.server_middleware do |chain|
  chain.add Sidekiq::Batch::Middleware::ServerMiddleware
end

Sidekiq.redis { |r| r.flushdb }

# Sidekiq.logger.level = :debug


def redis_keys
  Sidekiq.redis { |r| r.keys('BID-*') }
end

def dump_redis_keys
  puts redis_keys.inspect
end
