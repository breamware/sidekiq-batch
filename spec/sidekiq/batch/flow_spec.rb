require 'spec_helper'

class WorkerA
  include Sidekiq::Worker
  def perform
  end
end

class WorkerB
  include Sidekiq::Worker
  def perform
  end
end

class WorkerC
  include Sidekiq::Worker
  def perform
  end
end

describe 'Batch flow' do
  context 'when handling a batch' do
    let(:batch) { Sidekiq::Batch.new }
    before { batch.on(:complete, SampleCallback, :id => 42) }
    before { batch.description = 'describing the batch' }
    let(:status) { Sidekiq::Batch::Status.new(batch.bid) }
    let(:jids) { batch.jobs do 3.times do TestWorker.perform_async end end }
    let(:queue) { Sidekiq::Queue.new }

    it 'correctly initializes' do
      expect(jids.size).to eq(3)

      expect(batch.bid).not_to be_nil
      expect(batch.description).to eq('describing the batch')

      expect(status.total).to eq(3)
      expect(status.pending).to eq(3)
      expect(status.failures).to eq(0)
      expect(status.complete?).to be false
      expect(status.created_at).not_to be_nil
      expect(status.bid).to eq(batch.bid)
    end

    it 'handles an empty batch' do
      batch = Sidekiq::Batch.new
      jids = batch.jobs do nil end
      expect(jids.size).to eq(0)
    end
  end

  context 'when handling a nested batch' do
    let(:batchA) { Sidekiq::Batch.new }
    let(:batchB) { Sidekiq::Batch.new }
    let(:batchC) { Sidekiq::Batch.new(batchA.bid) }
    let(:batchD) { Sidekiq::Batch.new }
    let(:jids) { [] }
    let(:parent) { batchA.bid }
    let(:children) { [] }

    it 'handles a basic nested batch' do
      batchA.jobs do
        jids << WorkerA.perform_async
        batchB.jobs do
          jids << WorkerB.perform_async
        end
        jids << WorkerA.perform_async
        children << batchB.bid
      end

      batchC.jobs do
        batchD.jobs do
          jids << WorkerC.perform_async
        end
        children << batchD.bid
      end

      expect(jids.size).to eq(4)
      expect(Sidekiq::Batch::Status.new(parent).child_count).to eq(2)
      children.each do |kid|
          status = Sidekiq::Batch::Status.new(kid)
          expect(status.child_count).to eq(0)
          expect(status.pending).to eq(1)
          expect(status.parent_bid).to eq(parent)
      end

    end

  end
end
