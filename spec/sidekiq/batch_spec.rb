require 'spec_helper'


class TestWorker
  include Sidekiq::Worker
  def perform
  end
end

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
        expect(Thread.current[:bid]).to eq(batch)
      end
    end
  end

  describe '#process_failed_job' do
    let(:batch) { Sidekiq::Batch.new }
    let(:bid) { batch.bid }
    let(:jid) { 'ABCD' }
    before { Sidekiq.redis { |r| r.hset("BID-#{bid}", 'pending', 1) } }

    context 'complete' do
      let(:failed_jid) { 'xxx' }

      it 'tries to call complete callback' do
        expect(Sidekiq::Batch).to receive(:enqueue_callback).with(:complete, bid)
        Sidekiq::Batch.process_failed_job(bid, failed_jid)
      end

      it 'add job to failed list' do
        Sidekiq::Batch.process_failed_job(bid, 'failed-job-id')
        Sidekiq::Batch.process_failed_job(bid, failed_jid)
        failed = Sidekiq.redis { |r| r.smembers("BID-#{bid}-failed") }
        expect(failed).to eq(['xxx', 'failed-job-id'])
      end
    end

    context 'success' do
      before { batch.on(:complete, Object) }

      it 'tries to call complete and success callbacks' do
        expect(Sidekiq::Batch).to receive(:enqueue_callback).with(:complete, bid)
        expect(Sidekiq::Batch).to receive(:enqueue_callback).with(:success, bid)
        Sidekiq::Batch.process_successful_job(bid, jid)
      end
    end
  end

  describe '#process_successful_job' do
    let(:batch) { Sidekiq::Batch.new }
    let(:bid) { batch.bid }
    let(:jid) { 'ABCD' }
    before { Sidekiq.redis { |r| r.hset("BID-#{bid}", 'pending', 1) } }

    context 'complete' do
      before { batch.on(:complete, Object) }
      # before { batch.increment_job_queue(bid) }
      before { batch.jobs do TestWorker.perform_async end }
      before { Sidekiq::Batch.process_failed_job(bid, 'failed-job-id') }

      it 'tries to call complete callback' do
        expect(Sidekiq::Batch).to receive(:enqueue_callback).with(:complete, bid)
        Sidekiq::Batch.process_successful_job(bid, 'failed-job-id')
      end
    end

    context 'success' do
      before { batch.on(:complete, Object) }
      it 'tries to call complete and success callbacks' do
        expect(Sidekiq::Batch).to receive(:enqueue_callback).with(:complete, bid)
        expect(Sidekiq::Batch).to receive(:enqueue_callback).with(:success, bid)
        Sidekiq::Batch.process_successful_job(bid, jid)
      end

      it 'cleanups redis key' do
        Sidekiq::Batch.process_successful_job(bid, jid)
        expect(Sidekiq.redis { |r| r.get("BID-#{bid}-pending") }.to_i).to eq(0)
      end
    end
  end

  describe '#increment_job_queue' do
    let(:bid) { 'BID' }
    let(:batch) { Sidekiq::Batch.new }

    it 'increments pending' do
      batch.jobs do TestWorker.perform_async end
      pending = Sidekiq.redis { |r| r.hget("BID-#{batch.bid}", 'pending') }
      expect(pending).to eq('1')
    end

    it 'increments total' do
      batch.jobs do TestWorker.perform_async end
      total = Sidekiq.redis { |r| r.hget("BID-#{batch.bid}", 'total') }
      expect(total).to eq('1')
    end
  end

  describe '#enqueue_callback' do
    let(:callback) { double('callback') }
    let(:event) { 'complete' }

    it 'clears redis keys on success'

    context 'when already called' do
      it 'returns and do not call callback' do
        batch = Sidekiq::Batch.new
        batch.on(:complete, SampleCallback)
        Sidekiq.redis { |r| r.hset("BID-#{batch.bid}", event, true) }

        expect(Sidekiq::Client).not_to receive(:push)
        Sidekiq::Batch.enqueue_callback(event, batch.bid)
      end
    end

    context 'when not yet called' do
      context 'when there is no callback' do
        it 'it returns' do
          batch = Sidekiq::Batch.new

          expect(Sidekiq::Client).not_to receive(:push)
          Sidekiq::Batch.enqueue_callback(event, batch.bid)
        end
      end

      context 'when callback defined' do
        let(:opts) { { 'a' => 'b' } }

        it 'calls it passing options' do
          batch = Sidekiq::Batch.new
          batch.on(:complete, SampleCallback, opts)

          expect(Sidekiq::Client).to receive(:push).with(
            'class' => Sidekiq::Batch::Callback::Worker,
            'args' => ['SampleCallback', 'complete', opts, batch.bid, nil],
            'queue' => 'default'
          )
          Sidekiq::Batch.enqueue_callback(event, batch.bid)
        end
      end
    end
  end
end
