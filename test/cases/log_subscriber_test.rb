# frozen_string_literal: true

require "helper"

class LogSubscriberTest < ActiveSupport::TestCase
  include LogHelpers

  test "logging with a debug level" do
    capture_logger(level: Logger::DEBUG) do |logger|
      SubjectExperiment.run(id: 1)

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Completed segment callbacks (0.0ms)
        SubjectExperiment[key]  Completed variant callbacks (0.0ms)
        SubjectExperiment[key]  Completed run callbacks (0.0ms)
        SubjectExperiment[key]  Completed running red variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "logging with a debug level and no callbacks" do
    capture_logger(level: Logger::DEBUG) do |logger|
      NoCallbackExperiment.run(id: 1)

      assert_equal <<~MESSAGES, logger.messages
        NoCallbackExperiment[key]  Running log_subscriber_test/no_callback_experiment (Run ID: 1fbde0db)
        NoCallbackExperiment[key]  Completed running red variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "logging context" do
    LogContextExperiment = Class.new(NoCallbackExperiment) do
      def log_context?
        true
      end
    end

    capture_logger do |logger|
      LogContextExperiment.run(foo: "Foo", bar: [1, 2, 3], baz: { a: 1, b: 2, c: 3 })

      context = %{with context: {:foo=>"Foo", :bar=>[1, 2, 3], :baz=>{:a=>1, :b=>2, :c=>3}}}
      assert_equal <<~MESSAGES, logger.messages
        LogContextExperiment[key]  Running log_subscriber_test/log_context_experiment (Run ID: 1fbde0db) #{context}
        LogContextExperiment[key]  Completed running red variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "logging when a variant is assigned" do
    capture_logger do |logger|
      SubjectExperiment.set(variant: :blue).run(id: 1)

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db, Variant: blue)
        SubjectExperiment[key]  Completed running blue variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "logging when segmented" do
    capture_logger do |logger|
      SubjectExperiment.run(segment: true)

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Segmented into the `blue` variant (0.0ms)
        SubjectExperiment[key]  Completed running blue variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "raising an exception in a before run callback" do
    capture_logger do |logger|
      assert_raises(RuntimeError) do
        SubjectExperiment.run(raise_in_before_run: true)
      end

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Run failed: RuntimeError (before_run)
      MESSAGES
    end
  end

  test "raising an exception in an after run callback" do
    capture_logger do |logger|
      assert_raises(RuntimeError) do
        SubjectExperiment.run(raise_in_after_run: true)
      end

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Run failed: RuntimeError (after_run)
      MESSAGES
    end
  end

  test "raising an exception in segment callbacks" do
    capture_logger do |logger|
      assert_raises(RuntimeError) do
        SubjectExperiment.run(raise_in_segment: true)
      end

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Run failed: RuntimeError (segment block)
      MESSAGES
    end
  end

  test "raising an exception in a variant callback" do
    capture_logger do |logger|
      assert_raises(RuntimeError) do
        SubjectExperiment.run(raise_in_before_variant: true)
      end

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Run failed: RuntimeError (before_variant)
      MESSAGES
    end
  end

  test "raising an exception in a variant override" do
    capture_logger do |logger|
      assert_raises(RuntimeError) do
        SubjectExperiment.run(id: 1) do |experiment|
          experiment.on(:red) { raise "variant override" }
        end
      end

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Run failed: RuntimeError (variant override)
      MESSAGES
    end
  end

  test "raising an exception in the log subscriber" do
    capture_logger do |logger|
      NoCallbackExperiment.run(raise_in_start_run: true)

      # rubocop:disable Layout/TrailingWhitespace
      assert_equal <<~MESSAGES, logger.messages
        Could not log \"start_experiment.active_experiment\" event. RuntimeError: start_experiment 
        NoCallbackExperiment[key]  Completed running red variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
      # rubocop:enable Layout/TrailingWhitespace
    end
  end

  test "aborting in a run callback" do
    capture_logger do |logger|
      SubjectExperiment.run(abort_in_before_run: true)

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Run aborted in run callbacks (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "aborting in a variant callback" do
    capture_logger do |logger|
      result = SubjectExperiment.run(abort_in_before_variant: true)

      assert_nil result
      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Run aborted in red_variant callbacks (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "aborting in a variant step" do
    capture_logger do |logger|
      result = SubjectExperiment.set(variant: :green).run(abort_in_variant_step: true)

      assert_nil result
      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db, Variant: green)
        SubjectExperiment[key]  Run aborted in green_variant_steps callbacks (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "setting the variant in segment rule" do
    capture_logger do |logger|
      SubjectExperiment.run(set_variant_in_segment: true)

      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Resolved `red` variant in segment callbacks (0.0ms)
        SubjectExperiment[key]  Completed running red variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "trying to set the variant in a variant callback" do
    # Alright, so, probably don't do this, but here's a test.
    #
    # It starts by segmenting in to the blue variant, but then the variant is
    # changed to red in the before_variant callback for the blue variant. This
    # should result in the red variant being run, but could be confusing for
    # any reporting layers.
    capture_logger do |logger|
      result = SubjectExperiment.run(segment: true, set_variant_in_before_variant: true)

      assert_equal "red", result
      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running log_subscriber_test/subject_experiment (Run ID: 1fbde0db)
        SubjectExperiment[key]  Segmented into the `blue` variant (0.0ms)
        SubjectExperiment[key]  Resolved `red` variant in variant callbacks (0.0ms)
        SubjectExperiment[key]  Completed running red variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "when an unknown variant is resolved" do
    UnknownVariantExperiment = Class.new(SubjectExperiment) do
      def resolve_variant(*)
        :missing
      end
    end

    capture_logger do |logger|
      UnknownVariantExperiment.run

      assert_equal <<~MESSAGES, logger.messages
        UnknownVariantExperiment[key]  Running log_subscriber_test/unknown_variant_experiment (Run ID: 1fbde0db)
        UnknownVariantExperiment[key]  Run errored: unknown `missing` variant resolved (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "when no variant is resolved" do
    NoVariantExperiment = Class.new(SubjectExperiment) do
      def resolve_variant(*)
        nil
      end
    end

    capture_logger do |logger|
      NoVariantExperiment.run

      assert_equal <<~MESSAGES, logger.messages
        NoVariantExperiment[key]  Running log_subscriber_test/no_variant_experiment (Run ID: 1fbde0db)
        NoVariantExperiment[key]  Run errored: no variant resolved (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "nesting an experiment within another experiment" do
    NestedExperiment = Class.new(ActiveExperiment::Base) do
      control { "nested_control" }
    end

    capture_logger do |logger|
      NoCallbackExperiment.run { NestedExperiment.run }

      assert_equal <<~MESSAGES, logger.messages
        NoCallbackExperiment[key]  Running log_subscriber_test/no_callback_experiment (Run ID: 1fbde0db)
        NestedExperiment[key]  Nesting experiment in LogSubscriberTest::NoCallbackExperiment[fe41da0e]
        NestedExperiment[key]  Running log_subscriber_test/nested_experiment (Run ID: 1fbde0db)
        NestedExperiment[key]  Completed running control variant (Duration: 0.0ms | Allocations: 0)
        NoCallbackExperiment[key]  Completed running red variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "when the logger is nil" do
    capture_logger(logger: false) do
      NoCallbackExperiment.run
    end
  end

  test "when the experiment is slow (color)" do
    capture_logger(with_subscriber: TestColorizedLogSubscriber) do |logger|
      NoCallbackExperiment.run(duration: 500.1)

      details = "(Duration: \e[1m\e[33m500.1ms\e[0m | Allocations: 0)"
      assert_equal <<~MESSAGES, logger.messages
        \e[32mNoCallbackExperiment[key]  \e[0mRunning log_subscriber_test/no_callback_experiment (Run ID: 1fbde0db)
        \e[32mNoCallbackExperiment[key]  \e[0mCompleted running red variant #{details}
      MESSAGES
    end
  end

  test "when the experiment is REALLY slow (color)" do
    capture_logger(with_subscriber: TestColorizedLogSubscriber) do |logger|
      NoCallbackExperiment.run(duration: 1000.1)

      details = "(Duration: \e[1m\e[31m1000.1ms\e[0m | Allocations: 0)"
      assert_equal <<~MESSAGES, logger.messages
        \e[32mNoCallbackExperiment[key]  \e[0mRunning log_subscriber_test/no_callback_experiment (Run ID: 1fbde0db)
        \e[32mNoCallbackExperiment[key]  \e[0mCompleted running red variant #{details}
      MESSAGES
    end
  end

  def capture_logger(with_subscriber: nil, level: 1, **kws, &block)
    super(with_subscriber: with_subscriber || LogSubscriberTest::TestLogSubscriber, level: level, **kws, &block)
  end

  class NoCallbackExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }
    variant(:green) do
      throw(:abort) if context[:abort_in_variant_step]
      "green"
    end

    self.default_variant = :green
  end

  class SubjectExperiment < NoCallbackExperiment
    before_run do
      raise "before_run" if context[:raise_in_before_run]
      throw(:abort) if context[:abort_in_before_run]
    end

    after_run do
      raise "after_run" if context[:raise_in_after_run]
      throw(:abort) if context[:abort_in_after_run]
    end

    segment(into: :blue) do
      raise "segment block" if context[:raise_in_segment]
      set(variant: :red) if context[:set_variant_in_segment]
      context[:segment]
    end

    before_variant(:red) do
      raise "before_variant" if context[:raise_in_before_variant]
      set(variant: :blue) if context[:set_variant_in_before_variant]
      throw(:abort) if context[:abort_in_before_variant]
    end

    before_variant(:blue) do
      raise "before_variant" if context[:raise_in_before_variant]
      @variant = :red if context[:set_variant_in_before_variant]
      throw(:abort) if context[:abort_in_before_variant]
    end

    before_variant(:green) do
      raise "before_variant" if context[:raise_in_before_variant]
      @variant = :red if context[:set_variant_in_before_variant]
      throw(:abort) if context[:abort_in_before_variant]
    end
  end

  class TestLogSubscriber < LogHelpers::TestLogSubscriber
    def start_experiment(event)
      raise "start_experiment" if event.payload[:experiment].context[:raise_in_start_run]
      super
    end
  end

  class TestColorizedLogSubscriber < LogHelpers::TestLogSubscriber
    private
      def colorize_logging
        true
      end
  end
end
