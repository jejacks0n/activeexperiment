# frozen_string_literal: true

require "helper"

class ExecutionTest < ActiveSupport::TestCase
  def teardown
    # The run puts back whatever was there before it, so this is only here to
    # keep one leaking test from making the next one look fine.
    ActiveSupport::ExecutionContext.clear
    super
  end

  test "setting options at the class level" do
    result = SubjectExperiment.set(variant: :blue, foo: :bar).run

    assert_equal "blue #{{ foo: :bar }.inspect}", result
  end

  test "setting options on an instance" do
    result = SubjectExperiment.new.set(variant: :blue, foo: :bar).run

    assert_equal "blue #{{ foo: :bar }.inspect}", result
  end

  test "setting options within the run block" do
    result = SubjectExperiment.run do |experiment|
      experiment.set(variant: :blue, foo: :bar)
    end

    assert_equal "blue #{{ foo: :bar }.inspect}", result
  end

  test "overriding multiple variants" do
    result = SubjectExperiment.run do |experiment|
      experiment.on(:red, :blue) { "purple" }
    end

    assert_equal "purple", result
  end

  test "trying to override a variant without a block" do
    SubjectExperiment.run do |experiment|
      error = assert_raises(ArgumentError) do
        experiment.on(:red)
      end

      assert_equal "Missing block", error.message
    end
  end

  test "trying to override a variant that doesn't exist" do
    SubjectExperiment.run do |experiment|
      error = assert_raises(ArgumentError) do
        experiment.on(:foo) { }
      end

      assert_equal "Unknown :foo variant", error.message
    end
  end

  test "trying to run with no variants defined" do
    NoVariantExperiment = Class.new(ActiveExperiment::Base)

    error = assert_raises(ActiveExperiment::ExecutionError) do
      NoVariantExperiment.run
    end

    assert_equal "No variants registered", error.message
  end

  test "when the experiment is skipped" do
    result = SubjectExperiment.run do |experiment|
      experiment.skip
      assert_equal true, experiment.skipped?
    end

    assert_equal "control", result
  end

  test "fallback when an experiment without a control is skipped" do
    result = NoControlExperiment.run do |experiment|
      experiment.skip
    end

    assert_nil result
  end

  test "running an experiment twice" do
    experiment = SubjectExperiment.new
    result1 = experiment.run
    result2 = experiment.run { raise "Should not be called" }

    assert_equal result1, result2
    assert_equal "red", result1
    assert_equal "red", result2
  end

  test "the experiment is in the execution context while it runs" do
    seen = nil
    SubjectExperiment.run do |experiment|
      experiment.on(:red) { seen = ActiveSupport::ExecutionContext.to_h[:experiment] }
    end

    assert_instance_of SubjectExperiment, seen
  end

  test "the execution context is put back after the run" do
    SubjectExperiment.run

    assert_nil ActiveSupport::ExecutionContext.to_h[:experiment]
  end

  test "the execution context is put back after a run that raises" do
    assert_raises(RuntimeError) do
      SubjectExperiment.run { |experiment| experiment.on(:red) { raise "from the variant" } }
    end

    assert_nil ActiveSupport::ExecutionContext.to_h[:experiment]
  end

  test "a nested experiment hands the outer one back" do
    inner = after_inner = nil
    SubjectExperiment.run do |experiment|
      experiment.on(:red) do
        NoControlExperiment.run do |nested|
          nested.on(:treatment) { inner = ActiveSupport::ExecutionContext.to_h[:experiment] }
        end

        after_inner = ActiveSupport::ExecutionContext.to_h[:experiment]
      end
    end

    assert_instance_of NoControlExperiment, inner
    assert_instance_of SubjectExperiment, after_inner
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue #{options.inspect}" }
    control { "control" }
  end

  class NoControlExperiment < ActiveExperiment::Base
    variant(:treatment) { "treatment" }
  end
end
