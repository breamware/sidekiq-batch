module Sidekiq
  class Batch
    class Status
      attr_reader :bid

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

      def created_at
        Sidekiq.redis { |r| r.hget("BID-#{bid}", 'created_at') }
      end

      def total
        Sidekiq.redis { |r| r.get("BID-#{bid}-total") }.to_i
      end

      def failure_info
        []
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
