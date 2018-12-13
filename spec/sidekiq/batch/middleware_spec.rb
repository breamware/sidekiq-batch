require 'spec_helper'

describe Sidekiq::Batch::Middleware do
  describe Sidekiq::Batch::Middleware::ServerMiddleware do
    context 'when without batch' do
      it 'just yields' do
        yielded = false
        expect(Sidekiq::Batch).not_to receive(:process_successful_job)
        expect(Sidekiq::Batch).not_to receive(:process_failed_job)
        subject.call(nil, {}, nil) { yielded = true }
        expect(yielded).to be_truthy
      end
    end

    context 'when in batch' do
      let(:bid) { 'SAMPLEBID' }
      let(:jid) { 'SAMPLEJID' }
      context 'when successful' do
        it 'yields' do
          yielded = false
          subject.call(nil, { 'bid' => bid, 'jid' => jid }, nil) { yielded = true }
          expect(yielded).to be_truthy
        end

        it 'calls process_successful_job' do
          expect(Sidekiq::Batch).to receive(:process_successful_job).with(bid, nil)
          subject.call(nil, { 'bid' => bid }, nil) {}
        end
      end

      context 'when failed' do
        it 'calls process_failed_job and reraises exception' do
          reraised = false
          expect(Sidekiq::Batch).to receive(:process_failed_job)
          begin
            subject.call(nil, { 'bid' => bid }, nil) { raise 'ERR' }
          rescue
            reraised = true
          end
          expect(reraised).to be_truthy
        end
      end
    end
  end

  describe Sidekiq::Batch::Middleware::ClientMiddleware do
    context 'when without batch' do
      it 'just yields' do
        yielded = false
        expect(Sidekiq::Batch).not_to receive(:increment_job_queue)
        subject.call(nil, {}, nil) { yielded = true }
        expect(yielded).to be_truthy
      end
    end

    context 'when in batch' do
      let(:bid) { 'SAMPLEBID' }
      let(:jid) { 'SAMPLEJID' }
      before { Thread.current[:batch] = Sidekiq::Batch.new(bid) }

      it 'yields' do
        yielded = false
        subject.call(nil, { 'jid' => jid }, nil) { yielded = true }
        expect(yielded).to be_truthy
      end

      it 'increments job queue' do
        # expect(Sidekiq::Batch).to receive(:increment_job_queue).with(bid)
        # subject.call(nil, { 'jid' => jid }, nil) {}
      end

      it 'assigns bid to msg' do
        msg = { 'jid' => jid }
        subject.call(nil, msg, nil) {}
        expect(msg[:bid]).to eq(bid)
      end
    end
  end
end

describe Sidekiq::Batch::Middleware do
  let(:config) { class_double(Sidekiq) }
  let(:client_middleware) { double(Sidekiq::Middleware::Chain) }

  context 'client' do
    it 'adds client middleware' do
      expect(Sidekiq).to receive(:configure_client).and_yield(config)
      expect(config).to receive(:client_middleware).and_yield(client_middleware)
      expect(client_middleware).to receive(:add).with(Sidekiq::Batch::Middleware::ClientMiddleware)
      Sidekiq::Batch::Middleware.configure
    end
  end

  context 'server' do
    let(:server_middleware) { double(Sidekiq::Middleware::Chain) }

    it 'adds client and server middleware' do
      expect(Sidekiq).to receive(:configure_server).and_yield(config)
      expect(config).to receive(:client_middleware).and_yield(client_middleware)
      expect(config).to receive(:server_middleware).and_yield(server_middleware)
      expect(client_middleware).to receive(:add).with(Sidekiq::Batch::Middleware::ClientMiddleware)
      expect(server_middleware).to receive(:add).with(Sidekiq::Batch::Middleware::ServerMiddleware)
      Sidekiq::Batch::Middleware.configure
    end
  end

  context 'worker' do
    it 'defines method bid' do
      expect(Sidekiq::Worker.instance_methods).to include(:bid)
    end

    it 'defines method batch' do
      expect(Sidekiq::Worker.instance_methods).to include(:batch)
    end

    it 'defines method valid_within_batch?' do
      expect(Sidekiq::Worker.instance_methods).to include(:valid_within_batch?)
    end
  end
end
