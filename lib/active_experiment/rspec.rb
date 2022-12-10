# frozen_string_literal: true

RSpec.configure do |config|
  config.include ActiveExperiment::TestHelper, type: :experiment

  config.before(:each, type: :experiment) { clear_executed_experiments }
  config.after(:each, type: :experiment) { clear_executed_experiments }

  config.define_derived_metadata(file_path: Regexp.new("spec/experiments/")) do |metadata|
    metadata[:type] ||= :experiment
  end
end
