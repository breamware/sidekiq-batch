require 'sidekiq/group_job'

Sidekiq.redis { |r| r.flushdb }

class AnotherWorker
  include Sidekiq::Worker

  def perform
    sleep 10
  end
end

class TestWorker
  include Sidekiq::Worker

  def perform
    sleep 1
    if bid
      batch.jobs do
        AnotherWorker.perform_async
      end
    end
  end
end

class MyCallback
  def on_success(status, options)
    puts "Success #{options} #{status.data}"
  end

  def on_complete(status, options)
    puts "Complete #{options} #{status.data}"
  end
end

batch = Sidekiq::GroupJob.new
batch.description = 'Test group_job'
batch.callback_queue = :default
batch.on(:success, MyCallback, to: 'success@gmail.com')
batch.on(:complete, MyCallback, to: 'complete@gmail.com')

batch.jobs do
  10.times do
    TestWorker.perform_async
  end
end
puts Sidekiq::GroupJob::Status.new(batch.bid).data

Thread.new do
  loop do
    sleep 1
    keys = Sidekiq.redis { |r| r.keys('BID-*') }
    puts keys.inspect
  end
end
