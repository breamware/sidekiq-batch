require 'spec_helper'

describe Sidekiq::GroupJob::Callback::Worker do
  class SampleCallback; end

  describe '#perfom' do
    it 'does not do anything if it cannot find the callback class' do
      subject.perform('SampleCallback', 'complete', {}, 'ABCD')
    end

    it 'does not do anything if event is different from complete or success' do
      expect(SampleCallback).not_to receive(:new)
      subject.perform('SampleCallback', 'ups', {}, 'ABCD')
    end

    it 'creates instance when class and event' do
      expect(SampleCallback).to receive(:new)
      subject.perform('SampleCallback', 'success', {}, 'ABCD')
    end

    it 'calls on_success if defined' do
      callback_instance = double('SampleCallback')
      expect(SampleCallback).to receive(:new).and_return(callback_instance)
      expect(callback_instance).to receive(:on_success)
                                       .with(instance_of(Sidekiq::GroupJob::Status), {})
      subject.perform('SampleCallback', 'success', {}, 'ABCD')
    end

    it 'calls on_complete if defined' do
      callback_instance = double('SampleCallback')
      expect(SampleCallback).to receive(:new).and_return(callback_instance)
      expect(callback_instance).to receive(:on_complete)
                                       .with(instance_of(Sidekiq::GroupJob::Status), {})
      subject.perform('SampleCallback', 'complete', {}, 'ABCD')
    end
  end
end

describe Sidekiq::GroupJob::Callback do
  subject { described_class }

  describe '#call_if_needed' do
    let(:callback) { double('callback') }
    let(:event) { 'complete' }

    it 'clears redis keys on success'

    context 'when already called' do
      it 'returns and do not call callback' do
        batch = Sidekiq::GroupJob.new
        batch.on(:complete, SampleCallback)
        Sidekiq.redis { |r| r.hset("BID-#{batch.bid}", event, true) }

        expect(Sidekiq::Client).not_to receive(:push)
        subject.call_if_needed(event, batch.bid)
      end
    end

    context 'when not yet called' do
      context 'when there is no callback' do
        it 'it returns' do
          batch = Sidekiq::GroupJob.new

          expect(Sidekiq::Client).not_to receive(:push)
          subject.call_if_needed(event, batch.bid)
        end
      end

      context 'when callback defined' do
        let(:opts) { { 'a' => 'b' } }

        it 'calls it passing options' do
          batch = Sidekiq::GroupJob.new
          batch.on(:complete, SampleCallback, opts)

          expect(Sidekiq::Client).to receive(:push).with(
                                         'class' => Sidekiq::GroupJob::Callback::Worker,
            'args' => ['SampleCallback', 'complete', opts, batch.bid],
            'queue' => 'default'
          )
          subject.call_if_needed(event, batch.bid)
        end
      end
    end
  end
end
