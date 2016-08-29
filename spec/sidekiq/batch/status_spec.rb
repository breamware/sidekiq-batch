require 'spec_helper'

describe Sidekiq::Batch::Status do
  let(:bid) { 'BID' }
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
      before { Sidekiq::Batch.increment_job_queue(bid) }

      it 'returns pending jobs' do
        expect(subject.pending).to eq(1)
      end
    end
  end

  describe '#data' do
    it 'returns batch description' do
      expect(subject.data).to eq(total: nil, failures: nil, pending: 0, created_at: nil, complete: false, failure_info: nil)
    end
  end
end
