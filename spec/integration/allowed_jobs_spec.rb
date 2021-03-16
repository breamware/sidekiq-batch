require_relative '../integration_helper.rb'

class TestWorker
  include Sidekiq::Worker
  def perform
  end
end

class BaseKnownWorker
  include Sidekiq::Worker
  def perform
  end
end

class KnownBatchWorker < BaseKnownWorker
  def perform
    TestWorker.perform_async
    TestWorker.perform_one
  end
end

describe 'allowed jobs' do
  context 'when KnownBatchBaseKlass is enabled' do
    let(:batch) { Sidekiq::Batch.new }
    let(:bid) { batch.bid }

    before(:each) do
      Sidekiq::Worker.drain_all
      Sidekiq::Batch::Extension::KnownBatchBaseKlass::ENABLED = true
      Sidekiq::Batch::Extension::KnownBatchBaseKlass::ALLOWED = [BaseKnownWorker]
      batch.on(:complete, KnownBatchWorker)
      batch.on(:success, KnownBatchWorker)

      batch.jobs do
        KnownBatchWorker.perform_async
      end
    end

    after(:each) do
      Sidekiq::Batch::Extension::KnownBatchBaseKlass::ENABLED = false
      Sidekiq::Batch::Extension::KnownBatchBaseKlass::ALLOWED = []
    end

    it 'should not add other redis jobs into the batch queue' do
      total = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'total') }
      expect(total).to eq('1')

      pending = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'pending') }
      expect(pending).to eq('1')
    end

    it 'should call complete and success callbacks' do
      expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:complete, anything)
      expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:success, anything)

      Sidekiq::Worker.drain_all
    end

    it 'should have correct status' do
      expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:complete, anything)
      expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:success, anything)

      Sidekiq::Worker.drain_all

      total = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'total') }
      expect(total).to eq('1')

      pending = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'pending') }
      expect(pending).to eq('0')
    end
  end

  context 'when KnownBatchBaseKlass is disabled' do
    let(:batch) { Sidekiq::Batch.new }
    let(:bid) { batch.bid }

    before(:each) do
      Sidekiq::Worker.drain_all

      Sidekiq::Batch::Extension::KnownBatchBaseKlass::ENABLED = false
      Sidekiq::Batch::Extension::KnownBatchBaseKlass::ALLOWED = []
      batch.on(:complete, KnownBatchWorker)

      batch.jobs do
        KnownBatchWorker.perform_async
      end
    end

    it 'should have the pending status -1 because of the extra job executed by our batch job' do
      expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:complete, anything)
      expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:success, anything)

      total = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'total') }
      expect(total).to eq('1')
      pending = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'pending') }
      expect(pending).to eq('1')

      Sidekiq::Worker.drain_all

      total = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'total') }
      expect(total).to eq('1')
      pending = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'pending') }
      expect(pending).to eq('-1')
    end
  end
end
