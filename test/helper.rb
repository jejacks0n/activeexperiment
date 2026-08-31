# frozen_string_literal: true

# require "active_support/testing/strict_warnings"
require "active_support/core_ext/kernel/reporting"
require "minitest/mock"
require "simplecov"
require "simplecov-cobertura"

SimpleCov.start do
  skip "test/"
  skip "lib/active_experiment/version.rb"
  skip "lib/active_experiment/gem_version.rb"

  # Codecov can't parse SimpleCov's own JSON, so emit Cobertura XML alongside
  # the HTML report that's useful locally.
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ])
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
