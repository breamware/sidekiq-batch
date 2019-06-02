require 'integration_helper'

# Tests deep nesting of batches
# Batches:
# - Overall (Worker 1)
#  - Worker 2
#   - Worker 3
#    - Worker 4

class Worker1
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work1"
    batch = Sidekiq::Batch.new
    batch.on(:success, Worker2)
    batch.jobs do
      Worker2.perform_async
    end
  end
end

class Worker2
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work2"
    batch = Sidekiq::Batch.new
    batch.on(:success, Worker3)
    batch.jobs do
      Worker3.perform_async
    end
  end

  def on_success status, opts
    Sidekiq.logger.info "Worker 2 Success"
  end
end

class Worker3
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work3"
    batch = Sidekiq::Batch.new
    batch.on(:success, Worker4)
    batch.jobs do
      Worker4.perform_async
    end
  end

  def on_success status, opts
    Sidekiq.logger.info "Worker 3 Success"
  end
end

class Worker4
  include Sidekiq::Worker

  def perform
    Sidekiq.logger.info "Work4"
  end

  def on_success status, opts
    Sidekiq.logger.info "Worker 4 Success"
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
batch.on(:success, SomeClass, 'uid' => 3)
batch.on(:complete, SomeClass, 'uid' => 3)
batch.jobs do
  Worker1.perform_async
end

puts "Overall bid #{batch.bid}"

output, keys = process_tests
overall_tests output, keys
