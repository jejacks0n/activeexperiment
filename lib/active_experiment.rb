# frozen_string_literal: true

require "global_id"
require "active_support"
require "active_support/rails"
require "active_support/tagged_logging"

require "active_experiment/version"

module ActiveExperiment
  Error = Class.new(StandardError)
  ExecutionError = Class.new(Error)

  extend ActiveSupport::Autoload

  autoload :Base
  autoload :Cache
  autoload :ConfiguredExperiment
  autoload :Executed
  autoload :Rollouts

  autoload :TestCase
  autoload :TestHelper

  mattr_accessor :logger, default: ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
end
