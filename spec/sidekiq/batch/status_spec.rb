require 'spec_helper'

describe Sidekiq::Batch::Status do
  let(:bid) { 'BID' }
  let(:batch) { Sidekiq::Batch.new(bid) }
  subject { described_class.new(bid) }

  describe '#join' do
    it 'raises info' do
      expect { subject.join }.to raise_error('Not supported')
    end
  end

  describe '#pending' do
    context 'when not initalized' do
      it 'returns 0 pending jobs' do
        expect(subject.pending).to eq(0)
      end
    end

    context 'when more than 0' do
      before { batch.jobs do TestWorker.perform_async end }
      it 'returns pending jobs' do
        expect(subject.pending).to eq(1)
      end
    end
  end

  describe '#failures' do
    context 'when not initalized' do
      it 'returns 0 failed jobs' do
        expect(subject.failures).to eq(0)
      end
    end

    context 'when more than 0' do
      before { batch.increment_job_queue(bid) }
      before { Sidekiq::Batch.process_failed_job(bid, 'FAILEDID') }

      it 'returns failed jobs' do
        expect(subject.failures).to eq(1)
      end
    end
  end

  describe '#failure_info' do
    context 'when not initalized' do
      it 'returns empty array' do
        expect(subject.failure_info).to eq([])
      end
    end

    context 'when with error' do
      before { Sidekiq::Batch.process_failed_job(bid, 'jid123') }

      it 'returns array with failed jids' do
        expect(subject.failure_info).to eq(['jid123'])
      end
    end
  end

  describe '#total' do
    context 'when not initalized' do
      it 'returns 0 failed jobs' do
        expect(subject.total).to eq(0)
      end
    end

    context 'when more than 0' do
      before { batch.jobs do TestWorker.perform_async end }

      it 'returns failed jobs' do
        expect(subject.total).to eq(1)
      end
    end
  end

  describe '#data' do
    it 'returns batch description' do
      expect(subject.data).to include(total: 0, failures: 0, pending: 0, created_at: nil, complete: false, failure_info: [], parent_bid: nil)
    end
  end

  describe '#created_at' do
    it 'returns time' do
      batch = Sidekiq::Batch.new
      batch.jobs do TestWorker.perform_async end
      status = described_class.new(batch.bid)
      expect(status.created_at).not_to be_nil
    end
  end
end
