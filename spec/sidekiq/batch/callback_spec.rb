require 'spec_helper'

describe Sidekiq::Batch::Callback::Worker do
  describe '#perfom' do
    it 'does not do anything if it cannot find the callback class' do
      subject.perform('SampleCallback', 'complete', {}, 'ABCD')
    end

    it 'does not do anything if event is different from complete or success' do
      class SampleCallback; end
      expect(SampleCallback).not_to receive(:new)
      subject.perform('SampleCallback', 'ups', {}, 'ABCD')
    end

    it 'creates instance when class and event' do
      class SampleCallback; end
      expect(SampleCallback).to receive(:new)
      subject.perform('SampleCallback', 'success', {}, 'ABCD')
    end

    it 'calls on_success if defined' do
      callback_instance = double('SampleCallback')
      class SampleCallback; end
      expect(SampleCallback).to receive(:new).and_return(callback_instance)
      expect(callback_instance).to receive(:on_success)
        .with(instance_of(Sidekiq::Batch::Status), {})
      subject.perform('SampleCallback', 'success', {}, 'ABCD')
    end

    it 'calls on_complete if defined' do
      callback_instance = double('SampleCallback')
      class SampleCallback; end
      expect(SampleCallback).to receive(:new).and_return(callback_instance)
      expect(callback_instance).to receive(:on_complete)
        .with(instance_of(Sidekiq::Batch::Status), {})
      subject.perform('SampleCallback', 'complete', {}, 'ABCD')
    end
  end
end
