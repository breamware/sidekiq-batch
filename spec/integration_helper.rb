require 'spec_helper'
require 'sidekiq/batch'
require 'sidekiq/testing'

Sidekiq::Testing.server_middleware do |chain|
  chain.add Sidekiq::Batch::Middleware::ServerMiddleware
end

Sidekiq.redis { |r| r.flushdb }

def redis_keys
  Sidekiq.redis { |r| r.keys('BID-*') }
end

def dump_redis_keys
  puts redis_keys.inspect
end

def process_tests
  out_buf = StringIO.new
  Sidekiq.logger = Logger.new out_buf

  # Sidekiq.logger.level = :info

  Sidekiq::Worker.drain_all

  output = out_buf.string
  keys = redis_keys
  puts out_buf.string

  [output, keys]
end

def overall_tests output, keys
  describe "sidekiq batch" do
    it "runs overall complete callback" do
      expect(output).to include "Overall Complete"
    end

    it "runs overall success callback" do
      expect(output).to include "Overall Success"
    end

    it "cleans redis keys" do
      expect(keys).to eq([])
    end
  end
end
