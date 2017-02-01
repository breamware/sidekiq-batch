module Sidekiq::Batch::Extension
  module Worker
    def bid
      Thread.current[:bid]
    end

    def batch
      Sidekiq::Batch.new(Thread.current[:bid].bid) if Thread.current[:bid]
    end

    def valid_within_batch?
      batch.valid?
    end
  end
end
