require 'sidekiq/batch'

class TestWorker
  include Sidekiq::Worker

  def perform
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

batch = Sidekiq::Batch.new
batch.description = 'Test batch'
batch.callback_queue = :default
batch.on(:success, MyCallback, to: 'success@gmail.com')
batch.on(:complete, MyCallback, to: 'complete@gmail.com')

batch.jobs do
  10.times do
    TestWorker.perform_async
  end
end
puts Sidekiq::Batch::Status.new(batch.bid).data
