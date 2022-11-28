# frozen_string_literal: true

require "active_support/test_case"

module ActiveExperiment
  class TestCase < ActiveSupport::TestCase
    include ActiveExperiment::TestHelper

    ActiveSupport.run_load_hooks(:active_experiment_test_case, self)
  end
end
