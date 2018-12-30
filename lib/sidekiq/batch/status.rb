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
        Sidekiq.redis { |r| r.hget("BID-#{bid}", 'pending') }.to_i
      end

      def failures
        Sidekiq.redis { |r| r.scard("BID-#{bid}-failed") }.to_i
      end

      def created_at
        Sidekiq.redis { |r| r.hget("BID-#{bid}", 'created_at') }
      end

      def total
        Sidekiq.redis { |r| r.hget("BID-#{bid}", 'total') }.to_i
      end

      def parent_bid
        Sidekiq.redis { |r| r.hget("BID-#{bid}", "parent_bid") }
      end

      def failure_info
        Sidekiq.redis { |r| r.smembers("BID-#{bid}-failed") } || []
      end

      def complete?
        'true' == Sidekiq.redis { |r| r.hget("BID-#{bid}", 'complete') }
      end

      def child_count
        Sidekiq.redis { |r| r.hget("BID-#{bid}", 'children') }.to_i
      end

      def data
        {
          bid: bid,
          total: total,
          failures: failures,
          pending: pending,
          created_at: created_at,
          complete: complete?,
          failure_info: failure_info,
          parent_bid: parent_bid,
          child_count: child_count
        }
      end
    end
  end
end
