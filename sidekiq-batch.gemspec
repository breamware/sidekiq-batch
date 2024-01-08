# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sidekiq/batch/version'

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-batch"
  spec.version       = Sidekiq::Batch::VERSION
  spec.authors       = ["Marcin Naglik"]
  spec.email         = ["marcin.naglik@gmail.com"]

  spec.summary       = "Sidekiq Batch Jobs"
  spec.description   = "Sidekiq Batch Jobs Implementation"
  spec.homepage      = "http://github.com/breamware/sidekiq-batch"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", ">= 7", "<8"

  spec.add_development_dependency "bundler", "~> 2.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "fakeredis", "~> 0.8.0"
end
