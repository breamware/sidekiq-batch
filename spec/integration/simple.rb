require 'integration_helper'

# Simple nested batch without callbacks
# Batches:
# - Overall (Worker1)
#  - Worker2

class Worker1
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work1"
    batch = Sidekiq::Batch.new
    batch.jobs do
      Worker2.perform_async
    end
  end
end

class Worker2
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work2"
  end

  def on_complete status, opts
    Sidekiq.logger.info "Worker 2 Complete"
  end
end

class SomeClass
  def on_complete(status, options)
    Sidekiq.logger.info "Overall Complete #{options} #{status.data}"
  end
  def on_success(status, options)
    Sidekiq.logger.info "Overall Success #{options} #{status.data}"
  end
end

batch = Sidekiq::Batch.new
batch.on(:success, SomeClass)
batch.on(:complete, SomeClass)
batch.jobs do
  Worker1.perform_async
end

puts "Overall bid #{batch.bid}"

dump_redis_keys

Sidekiq::Worker.drain_all

describe("sidekiq batch") do
  it "cleans redis keys" do
    expect(redis_keys).to eq([])
  end
end
