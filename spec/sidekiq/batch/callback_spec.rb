require 'spec_helper'

describe Sidekiq::Batch::Callback::Worker do
  describe '#perform' do
    it 'does not do anything if it cannot find the callback class' do
      subject.perform('SampleCallback', 'complete', {}, 'ABCD', 'EFGH')
    end

    it 'does not do anything if event is different from complete or success' do
      expect(SampleCallback).not_to receive(:new)
      subject.perform('SampleCallback', 'ups', {}, 'ABCD', 'EFGH')
    end

    it 'calls on_success if defined' do
      callback_instance = double('SampleCallback', on_success: true)
      expect(SampleCallback).to receive(:new).and_return(callback_instance)
      expect(callback_instance).to receive(:on_success)
        .with(instance_of(Sidekiq::Batch::Status), {})
      subject.perform('SampleCallback', 'success', {}, 'ABCD', 'EFGH')
    end

    it 'calls on_complete if defined' do
      callback_instance = double('SampleCallback')
      expect(SampleCallback).to receive(:new).and_return(callback_instance)
      expect(callback_instance).to receive(:on_complete)
        .with(instance_of(Sidekiq::Batch::Status), {})
      subject.perform('SampleCallback', 'complete', {}, 'ABCD', 'EFGH')
    end

    it 'calls specific callback if defined' do
      callback_instance = double('SampleCallback')
      expect(SampleCallback).to receive(:new).and_return(callback_instance)
      expect(callback_instance).to receive(:sample_method)
        .with(instance_of(Sidekiq::Batch::Status), {})
      subject.perform('SampleCallback#sample_method', 'complete', {}, 'ABCD', 'EFGH')
    end
  end
end
