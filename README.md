[gem]: https://rubygems.org/gems/sidekiq-batch
[travis]: https://travis-ci.org/breamware/sidekiq-batch
[codeclimate]: https://codeclimate.com/github/breamware/sidekiq-batch

# Sidekiq::Batch

[![Join the chat at https://gitter.im/breamware/sidekiq-batch](https://badges.gitter.im/breamware/sidekiq-batch.svg)](https://gitter.im/breamware/sidekiq-batch?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

[![Gem Version](https://badge.fury.io/rb/sidekiq-batch.svg)][gem]
[![Build Status](https://travis-ci.org/breamware/sidekiq-batch.svg?branch=master)][travis]
[![Code Climate](https://codeclimate.com/github/breamware/sidekiq-batch/badges/gpa.svg)][codeclimate]
[![Code Climate](https://codeclimate.com/github/breamware/sidekiq-batch/badges/coverage.svg)][codeclimate]
[![Code Climate](https://codeclimate.com/github/breamware/sidekiq-batch/badges/issue_count.svg)][codeclimate]

Simple Sidekiq Batch Job implementation.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-batch'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-batch

## Usage

Sidekiq Batch is drop-in replacement for the API from Sidekiq PRO. See https://github.com/mperham/sidekiq/wiki/Batches for usage.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/breamware/sidekiq-batch.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## Changes in this fork

There are multiple bugs reported on how the complete/success callback is called on batches.
This version fixes (tries to fix) 2 bugs (unwanted behaviours): 
1. The complete callback is called sometimes to early, before batch completion 
2. The total number of pending jobs from the batch sometimes differ from the initial jobs enqueued initially 

Both issues are caused (in my case) when the jobs from the batch are enqueuing jobs that are not related to the batch. 
Also this is reproducible only when concurrency is > 1

#### How the fix works:  
We consider that only the "Allowed" classes can be added to the batch queue.
To enable this behaviour, the following constants should be set in an initializer:
```
Sidekiq::Batch::Extension::KnownBatchBaseKlass::ENABLED = true
Sidekiq::Batch::Extension::KnownBatchBaseKlass::ALLOWED = [MyBaseBatchWorker].freeze
```
By enabling this behaviour, jobs that are enqueued by jobs from our batch, are not added to the batch also. Only the ones that have as an ancestor a base class defined by us. 