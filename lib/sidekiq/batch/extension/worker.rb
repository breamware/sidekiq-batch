module Sidekiq::Batch::Extension
  module Worker
    def bid
      Thread.current[:batch].bid
    end

    def batch
      Thread.current[:batch]
    end

    def valid_within_batch?
      batch.valid?
    end
  end
end
