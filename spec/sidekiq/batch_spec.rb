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

    it 'increments to_process (when started)'

    it 'decrements to_process (when finished)'
    # it 'calls process_successful_job to wait for block to finish' do
    #   batch = Sidekiq::Batch.new
    #   expect(Sidekiq::Batch).to receive(:process_successful_job).with(batch.bid)
    #   batch.jobs {}
    # end

    it 'sets Thread.current bid' do
      batch = Sidekiq::Batch.new
      batch.jobs do
        expect(Thread.current[:bid]).to eq(batch.bid)
      end
    end
  end

  describe '#process_failed_job' do
    let(:batch) { Sidekiq::Batch.new }
    let(:bid) { batch.bid }
    before { Sidekiq.redis { |r| r.hset("BID-#{bid}", 'to_process', 1) } }

    context 'complete' do
      let(:failed_jid) { 'xxx' }
      before { batch.on(:complete, Object) }
      before { Sidekiq::Batch.increment_job_queue(bid) }
      before { Sidekiq::Batch.process_failed_job(bid, 'failed-job-id') }

      it 'tries to call complete callback' do
        expect(Sidekiq::Batch::Callback).to receive(:call_if_needed).with(:complete, bid)
        Sidekiq::Batch.process_failed_job(bid, failed_jid)
      end

      it 'add job to failed list' do
        Sidekiq::Batch.process_failed_job(bid, failed_jid)
        failed = Sidekiq.redis { |r| r.smembers("BID-#{bid}-failed") }
        expect(failed).to eq(['xxx', 'failed-job-id'])
      end
    end

    context 'success' do
      before { batch.on(:complete, Object) }
      it 'tries to call complete and success callbacks' do
        expect(Sidekiq::Batch::Callback).to receive(:call_if_needed).with(:complete, bid)
        expect(Sidekiq::Batch::Callback).to receive(:call_if_needed).with(:success, bid)
        Sidekiq::Batch.process_successful_job(bid)
      end
    end
  end

  describe '#process_successful_job' do
    let(:batch) { Sidekiq::Batch.new }
    let(:bid) { batch.bid }
    before { Sidekiq.redis { |r| r.hset("BID-#{bid}", 'to_process', 1) } }

    context 'complete' do
      before { batch.on(:complete, Object) }
      before { Sidekiq::Batch.increment_job_queue(bid) }
      before { Sidekiq::Batch.process_failed_job(bid, 'failed-job-id') }

      it 'tries to call complete callback' do
        expect(Sidekiq::Batch::Callback).to receive(:call_if_needed).with(:complete, bid)
        Sidekiq::Batch.process_successful_job(bid)
      end
    end

    context 'success' do
      before { batch.on(:complete, Object) }
      it 'tries to call complete and success callbacks' do
        expect(Sidekiq::Batch::Callback).to receive(:call_if_needed).with(:complete, bid)
        expect(Sidekiq::Batch::Callback).to receive(:call_if_needed).with(:success, bid)
        Sidekiq::Batch.process_successful_job(bid)
      end

      it 'cleanups redis key' do
        Sidekiq::Batch.process_successful_job(bid)
        expect(Sidekiq.redis { |r| r.get("BID-#{bid}-to_process") }.to_i).to eq(0)
      end
    end
  end

  describe '#increment_job_queue' do
    let(:bid) { 'BID' }
    it 'increments to_process counter' do
      Sidekiq::Batch.increment_job_queue(bid)
      to_process = Sidekiq.redis { |r| r.hget("BID-#{bid}", 'to_process') }
      expect(to_process).to eq('1')
    end

    it 'increments pending'

    it 'increments total'
  end
end
