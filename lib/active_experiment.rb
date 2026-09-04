# frozen_string_literal: true

# GlobalID's URI parsing calls CGI.unescape without requiring it. Ruby 4.0
# removed the CGI library, leaving cgi/escape as the only place that method
# lives; before 4.0 cgi/escape can't stand on its own, so cgi/util is needed.
if RUBY_VERSION >= "4.0"
  require "cgi/escape"
else
  require "cgi/util"
end
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
  autoload :Recorders
  autoload :Rollouts
  autoload :Capturable

  autoload :TestCase
  autoload :TestHelper

  mattr_accessor :logger, default: ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
end
