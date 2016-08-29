module Sidekiq
  class Batch
    class Status
      attr_reader :bid, :total, :failures, :created_at, :failure_info

      def initialize(bid)
        @bid = bid
      end

      def join
        raise "Not supported"
      end

      def pending
        Sidekiq.redis { |r| r.get("BID-#{bid}-to_process") }.to_i
      end

      def failures
        Sidekiq.redis { |r| r.scard("BID-#{bid}-failed") }.to_i
      end

      def complete?
        'true' == Sidekiq.redis { |r| r.hget("BID-#{bid}", 'complete') }
      end

      def data
        {
          total: total,
          failures: failures,
          pending: pending,
          created_at: created_at,
          complete: complete?,
          failure_info: failure_info
        }
      end
    end
  end
end
