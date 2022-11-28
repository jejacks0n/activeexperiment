# frozen_string_literal: true

require "helper"

class CallbacksTest < ActiveSupport::TestCase
  test "run callback order" do
    SubjectExperiment.run(collector = [])

    assert_equal [
      "subject_experiment:before_run",
      "subject_experiment:around_run[control]",
      "subject_experiment:after_run"
    ], collector
  end

  test "run and variant callback order" do
    SubjectExperiment.set(variant: :treatment).run(collector = [])

    assert_equal [
      "subject_experiment:before_run",
      "subject_experiment:before_variant(treatment)",
      "subject_experiment:around_variant(treatment)[treatment]",
      "subject_experiment:after_variant(treatment)",
      "subject_experiment:around_run[treatment]",
      "subject_experiment:after_run"
    ], collector
  end

  test "variants with multiple steps call order" do
    SubjectExperiment.set(variant: :multi_step).run(collector = [])

    assert_equal [
      "subject_experiment:before_run",
      "subject_experiment:multi_step_method",
      "subject_experiment:multi_step_block",
      "subject_experiment:around_run[multi_step_block]",
      "subject_experiment:after_run",
    ], collector
  end

  test "variant callback order with variant override" do
    result = SubjectExperiment.set(variant: :treatment).run(collector = []) do |experiment|
      experiment.on(:treatment) do
        collector << "#{experiment.name}:override_block"
        "override_block"
      end
    end

    assert_equal "override_block", result
    assert_equal [
      "subject_experiment:before_run",
      "subject_experiment:before_variant(treatment)",
      "subject_experiment:override_block",
      "subject_experiment:around_variant(treatment)[override_block]",
      "subject_experiment:after_variant(treatment)",
      "subject_experiment:around_run[override_block]",
      "subject_experiment:after_run"
    ], collector
  end

  test "when aborted in a before run" do
    result = SubjectExperiment.set(variant: :treatment).run(collector = ["abort_in_before_run"])

    assert_nil result
    assert_equal [
      "abort_in_before_run",
      "subject_experiment:before_run"
    ], collector
  end

  test "when aborted in a before variant" do
    result = SubjectExperiment.set(variant: :treatment).run(collector = ["abort_in_before_variant"])

    assert_nil result
    assert_equal [
      "abort_in_before_variant",
      "subject_experiment:before_run",
      "subject_experiment:before_variant(treatment)",
      "subject_experiment:after_variant(treatment)",
      "subject_experiment:around_run[]",
      "subject_experiment:after_run",
    ], collector
  end

  test "when aborted in the first variant step" do
    result = SubjectExperiment.set(variant: :multi_step).run(collector = ["abort_in_multi_step_method"])

    assert_nil result
    assert_equal [
      "abort_in_multi_step_method",
      "subject_experiment:before_run",
      "subject_experiment:multi_step_method",
      "subject_experiment:around_run[]",
      "subject_experiment:after_run"
    ], collector
  end

  test "when aborted in the last variant step" do
    result = SubjectExperiment.set(variant: :multi_step).run(collector = ["abort_in_multi_step_block"])

    assert_equal "multi_step_method", result
    assert_equal [
      "abort_in_multi_step_block",
      "subject_experiment:before_run",
      "subject_experiment:multi_step_method",
      "subject_experiment:multi_step_block",
      "subject_experiment:around_run[multi_step_method]",
      "subject_experiment:after_run"
    ], collector
  end

  test "defining variants with callback options" do
    WeirdExperiment = Class.new(ActiveExperiment::Base) do
      variant(:foo, unless: -> { context[:foo2] }) do
        raise "Should not be called" if context[:foo2]
        "foo1"
      end
      variant(:foo, add: true, if: -> { context[:foo2] }) { "foo2" }
    end

    assert_equal "foo1", WeirdExperiment.run
    assert_equal "foo2", WeirdExperiment.run(foo2: true)
  end

  class SubjectExperiment < ActiveExperiment::Base
    control { "control" }
    variant(:treatment) { "treatment" }
    variant(:multi_step, :multi_step_method) do |experiment|
      context << "#{experiment.name}:multi_step_block"
      throw(:abort) if context[0] == "abort_in_multi_step_block"
      "multi_step_block"
    end

    after_run do
      context << "#{name}:after_run"
    end

    before_run do
      context << "#{name}:before_run"
      throw(:abort) if context[0] == "abort_in_before_run"
    end

    around_run do |experiment, block|
      experiment.context << "#{name}:around_run[#{block.call}]"
    end

    after_variant :treatment do
      context << "#{name}:after_variant(treatment)"
    end

    before_variant :treatment do |experiment|
      context << "#{experiment.name}:before_variant(treatment)"
      throw(:abort) if context[0] == "abort_in_before_variant"
    end

    around_variant :treatment do |_, block|
      context << "#{name}:around_variant(treatment)[#{block.call}]"
    end

    def name
      "subject_experiment"
    end

    private
      def multi_step_method
        context << "#{name}:multi_step_method"
        throw(:abort) if context[0] == "abort_in_multi_step_method"
        "multi_step_method"
      end
  end
end
