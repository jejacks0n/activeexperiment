# frozen_string_literal: true

require "helper"

class LoggingTest < ActiveSupport::TestCase
  include LogHelpers

  test "logging within run and variant blocks" do
    capture_logger(with_subscriber: false) do |logger|
      experiment = SubjectExperiment.new
      experiment.logger.info "experiment info"
      experiment.run do |ex|
        ex.logger.info "inside run block"
      end

      assert_equal <<~MESSAGES, logger.messages
        [ActiveExperiment] experiment info
        [ActiveExperiment] [run] before run
        [ActiveExperiment] [run] inside run block
        [ActiveExperiment] [run] control block executed
      MESSAGES
    end
  end

  test "logging when the logger isn't taggable" do
    capture_logger(with_subscriber: false, logger: TestLogger.new(nil)) do |logger|
      experiment = SubjectExperiment.new
      experiment.logger.info "experiment info"
      experiment.run do |ex|
        ex.logger.info "inside run block"
      end

      assert_equal <<~MESSAGES, logger.messages
        experiment info
        before run
        inside run block
        control block executed
      MESSAGES
    end
  end

  class SubjectExperiment < ActiveExperiment::Base
    control
    variant(:treatment) { "treatment" }

    around_run(prepend: true) do |_, block|
      tag_logger("run", &block)
    end

    before_run do
      logger.info "before run"
    end

    private
      def control_variant
        logger.debug "control block executed"
        "control"
      end
  end
end
