# frozen_string_literal: true

require "active_support/core_ext/class/subclasses"
require "active_support/testing/assertions"

module ActiveExperiment
  # Provides helper methods for testing Active Experiment.
  #
  # TODO: finish documenting.
  module TestHelper
    include ActiveSupport::Testing::Assertions

    def before_setup # :nodoc:
    end

    def after_teardown # :nodoc:
    end
  end
end
