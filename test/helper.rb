# frozen_string_literal: true

# require "active_support/testing/strict_warnings"
require "active_support/core_ext/kernel/reporting"
require "minitest/mock"
require "simplecov"
# require "simplecov_json_formatter"

# SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter if ENV["CC_TEST_REPORTER_ID"]
SimpleCov.start do
  add_filter "test/"
  add_filter "lib/active_experiment/version.rb"
  add_filter "lib/active_experiment/gem_version.rb"
end

require "active_experiment"

GlobalID.app = "ae"
ActiveExperiment.logger = Logger.new(nil)
ActiveExperiment::Base.default_rollout = ActiveExperiment::Rollouts::BaseRollout.new(nil)

require "support/log_helpers"
require "support/view_helpers"
require "support/global_id_object"

require "active_support/testing/autorun"
# require_relative "../../tools/test_common"
