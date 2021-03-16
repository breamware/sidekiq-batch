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

    # it 'decrements to_process (when finished)'
    # it 'calls process_successful_job to wait for block to finish' do
    #   batch = Sidekiq::Batch.new
    #   expect(Sidekiq::Batch).to receive(:process_successful_job).with(batch.bid)
    #   batch.jobs {}
    # end

    it 'sets Thread.current bid' do
      batch = Sidekiq::Batch.new
      batch.jobs do
        expect(Thread.current[:batch]).to eq(batch)
      end
    end
  end

  describe '#invalidate_all' do
    class InvalidatableJob
      include Sidekiq::Worker

      def perform
        return unless valid_within_batch?
        was_performed
      end

      def was_performed; end
    end

    it 'marks batch in redis as invalidated' do
      batch = Sidekiq::Batch.new
      job = InvalidatableJob.new
      allow(job).to receive(:was_performed)

      batch.invalidate_all
      batch.jobs { job.perform }

      expect(job).not_to have_received(:was_performed)
    end

    context 'nested batches' do
      let(:batch_parent) { Sidekiq::Batch.new }
      let(:batch_child_1) { Sidekiq::Batch.new }
      let(:batch_child_2) { Sidekiq::Batch.new }
      let(:job_of_parent) { InvalidatableJob.new }
      let(:job_of_child_1) { InvalidatableJob.new }
      let(:job_of_child_2) { InvalidatableJob.new }

      before do
        allow(job_of_parent).to receive(:was_performed)
        allow(job_of_child_1).to receive(:was_performed)
        allow(job_of_child_2).to receive(:was_performed)
      end

      it 'invalidates all job if parent batch is marked as invalidated' do
        batch_parent.invalidate_all
        batch_parent.jobs do
          [
            job_of_parent.perform,
            batch_child_1.jobs do
              [
                job_of_child_1.perform,
                batch_child_2.jobs { job_of_child_2.perform }
              ]
            end
          ]
        end

        expect(job_of_parent).not_to have_received(:was_performed)
        expect(job_of_child_1).not_to have_received(:was_performed)
        expect(job_of_child_2).not_to have_received(:was_performed)
      end

      it 'invalidates only requested batch' do
        batch_child_2.invalidate_all
        batch_parent.jobs do
          [
            job_of_parent.perform,
            batch_child_1.jobs do
              [
                job_of_child_1.perform,
                batch_child_2.jobs { job_of_child_2.perform }
              ]
            end
          ]
        end

        expect(job_of_parent).to have_received(:was_performed)
        expect(job_of_child_1).to have_received(:was_performed)
        expect(job_of_child_2).not_to have_received(:was_performed)
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
        expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:complete, bid)
        Sidekiq::Batch.process_failed_job(bid, failed_jid)
      end

      it 'add job to failed list' do
        Sidekiq::Batch.process_failed_job(bid, 'failed-job-id')
        Sidekiq::Batch.process_failed_job(bid, failed_jid)
        failed = Sidekiq.redis { |r| r.smembers("BID-#{bid}-failed") }
        expect(failed).to eq(['xxx', 'failed-job-id'])
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
        expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:complete, bid)
        Sidekiq::Batch.process_successful_job(bid, 'failed-job-id')
      end
    end

    context 'success' do
      before { batch.on(:complete, Object) }
      it 'tries to call complete callback' do
        expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:complete, bid).ordered
        expect(Sidekiq::Batch).to receive(:enqueue_callbacks).with(:success, bid).ordered
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

  describe '#enqueue_callbacks' do
    let(:callback) { double('callback') }
    let(:event) { :complete }

    context 'on :success' do
      let(:event) { :success }
      context 'when no callbacks are defined' do
        it 'clears redis keys' do
          batch = Sidekiq::Batch.new
          expect(Sidekiq::Batch).to receive(:cleanup_redis).with(batch.bid)
          Sidekiq::Batch.enqueue_callbacks(event, batch.bid)
        end
      end
    end

    context 'when already called' do
      it 'returns and does not enqueue callbacks' do
        batch = Sidekiq::Batch.new
        batch.on(event, SampleCallback)
        Sidekiq.redis { |r| r.hset("BID-#{batch.bid}", event, true) }

        expect(Sidekiq::Client).not_to receive(:push)
        Sidekiq::Batch.enqueue_callbacks(event, batch.bid)
      end
    end

    context 'when not yet called' do
      context 'when there is no callback' do
        it 'it returns' do
          batch = Sidekiq::Batch.new

          expect(Sidekiq::Client).not_to receive(:push)
          Sidekiq::Batch.enqueue_callbacks(event, batch.bid)
        end
      end

      context 'when callback defined' do
        let(:opts) { { 'a' => 'b' } }

        it 'calls it passing options' do
          batch = Sidekiq::Batch.new
          batch.on(event, SampleCallback, opts)

          expect(Sidekiq::Client).to receive(:push_bulk).with(
            'class' => Sidekiq::Batch::Callback::Worker,
            'args' => [['SampleCallback', event, opts, batch.bid, nil]],
            'queue' => 'default'
          )
          Sidekiq::Batch.enqueue_callbacks(event, batch.bid)
        end
      end

      context 'when multiple callbacks are defined' do
        let(:opts) { { 'a' => 'b' } }
        let(:opts2) { { 'b' => 'a' } }

        it 'enqueues each callback passing their options' do
          batch = Sidekiq::Batch.new
          batch.on(event, SampleCallback, opts)
          batch.on(event, SampleCallback2, opts2)

          expect(Sidekiq::Client).to receive(:push_bulk).with(
            'class' => Sidekiq::Batch::Callback::Worker,
            'args' => [
              ['SampleCallback2', event, opts2, batch.bid, nil],
              ['SampleCallback', event, opts, batch.bid, nil]
            ],
            'queue' => 'default'
          )

          Sidekiq::Batch.enqueue_callbacks(event, batch.bid)
        end
      end
    end
  end
end
