require "simplecov"
SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'fakeredis/rspec'
require 'sidekiq/batch'

redis_opts = { url: "redis://127.0.0.1:6379/1" }
redis_opts[:driver] = Redis::Connection::Memory if defined?(Redis::Connection::Memory)

Sidekiq.configure_client do |config|
  config.redis = redis_opts
end

Sidekiq.configure_server do |config|
  config.redis = redis_opts
end

RSpec.configure do |config|
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
end

Dir[File.dirname(__FILE__) + "/support/**/*.rb"].each {|f| require f }
