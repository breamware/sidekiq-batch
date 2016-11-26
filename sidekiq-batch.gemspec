# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sidekiq/group_job/version'

Gem::Specification.new do |spec|
  spec.name = "sidekiq-group_job"
  spec.version = Sidekiq::GroupJob::VERSION
  spec.authors       = ["Marcin Naglik"]
  spec.email         = ["marcin.naglik@gmail.com"]

  spec.summary = "Sidekiq Group Job (Batch) Jobs"
  spec.description   = "Sidekiq Batch Jobs Implementation"
  spec.homepage = "http://github.com/breamware/sidekiq-group_job"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", ">= 3"

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "fakeredis", "~> 0.5.0"
end
