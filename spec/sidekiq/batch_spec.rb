require 'spec_helper'

describe Sidekiq::Batch do
  it 'has a version number' do
    expect(Sidekiq::Batch::VERSION).not_to be nil
  end

  describe '#initialize' do
    subject { described_class }

    it 'creates bid when called without it' do
      expect(subject.new.bid).not_to be_nil
    end

    it 'reuses bid when called with it' do
      batch = subject.new('dayPO5KxuRXXxw')
      expect(batch.bid).to eq('dayPO5KxuRXXxw')
    end
  end

  describe '#description' do
    let(:description) { 'custom description' }
    before { subject.description = description }

    it 'sets descriptions' do
      expect(subject.description).to eq(description)
    end

    it 'persists description' do
      expect(Sidekiq.redis { |r| r.hget("BID-#{subject.bid}", 'description') })
        .to eq(description)
    end
  end

  describe '#callback_queue' do
    let(:callback_queue) { 'custom_queue' }
    before { subject.callback_queue = callback_queue }

    it 'sets callback_queue' do
      expect(subject.callback_queue).to eq(callback_queue)
    end

    it 'persists callback_queue' do
      expect(Sidekiq
             .redis { |r| r.hget("BID-#{subject.bid}", 'callback_queue') })
        .to eq(callback_queue)
    end
  end

  describe '#jobs' do
    it 'throws error if no block given' do
      expect { subject.jobs }.to raise_error Sidekiq::Batch::NoBlockGivenError
    end

    it 'calls increment_job_queue/process_successful_job to wait for block to finish' do
      batch = Sidekiq::Batch.new
      expect(Sidekiq::Batch).to receive(:increment_job_queue).with(batch.bid)
      expect(Sidekiq::Batch).to receive(:process_successful_job).with(batch.bid)

      batch.jobs {}
    end

    it 'sets Thread.current bid' do
      batch = Sidekiq::Batch.new
      batch.jobs {}
      expect(Thread.current[:bid]).to eq(batch.bid)
    end
  end
end
