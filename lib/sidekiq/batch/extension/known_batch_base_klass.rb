module Sidekiq::Batch::Extension
  module KnownBatchBaseKlass
    def enabled?
      @enabled ||= defined?(ENABLED) ? ENABLED : false
    end

    def allowed
      @allowed ||= defined?(ALLOWED) ? ALLOWED : []
    end

    def allowed?(klass)
      return true unless enabled?

      (Object.const_get(klass).ancestors & allowed).any?
    end
  end
end
