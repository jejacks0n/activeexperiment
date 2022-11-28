# frozen_string_literal: true

require "helper"

class ExecutionTest < ActiveSupport::TestCase
  test "setting options at the class level" do
    result = SubjectExperiment.set(variant: :blue, foo: :bar).run

    assert_equal "blue {:foo=>:bar}", result
  end

  test "setting options on an instance" do
    result = SubjectExperiment.new.set(variant: :blue, foo: :bar).run

    assert_equal "blue {:foo=>:bar}", result
  end

  test "setting options within the run block" do
    result = SubjectExperiment.run do |experiment|
      experiment.set(variant: :blue, foo: :bar)
    end

    assert_equal "blue {:foo=>:bar}", result
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

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue #{options.inspect}" }
    control { "control" }
  end

  class NoControlExperiment < ActiveExperiment::Base
    variant(:treatment) { "treatment" }
  end
end
