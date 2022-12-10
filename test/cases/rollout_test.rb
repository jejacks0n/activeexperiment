# frozen_string_literal: true

require "helper"

class RolloutTest < ActiveSupport::TestCase
  test "using a custom rollout in an experiment" do
    assert_equal "treatment", SubjectExperiment.run
  end

  test "trying to set an invalid default rollout" do
    error = assert_raises(ArgumentError) do
      ActiveExperiment::Base.default_rollout = {}
    end

    assert_equal "Invalid rollout. "\
      "Rollouts must respond to enabled_for, variant_for.",
      error.message
  end

  test "an experiment that uses itself as a rollout" do
    CustomRolloutModule = Module.new do
      def enabled_for(*)
        true
      end

      def variant_for(*)
        :blue
      end
    end

    SelfRolloutExperiment = Class.new(ActiveExperiment::Base) do
      extend CustomRolloutModule

      variant(:red) { "red" }
      variant(:blue) { "blue" }

      use_rollout self
    end

    assert_equal "blue", SelfRolloutExperiment.run
  end

  class CustomRollout < ActiveExperiment::Rollouts::BaseRollout
    def variant_for(*)
      :treatment
    end
  end

  ActiveExperiment::Rollouts.register(:custom, CustomRollout)

  class SubjectExperiment < ActiveExperiment::Base
    control { "control" }
    variant(:treatment) { "treatment" }

    use_rollout :custom
  end
end
