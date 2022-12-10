# frozen_string_literal: true

require "helper"

class InactiveRolloutTest < ActiveSupport::TestCase
  test "being skipped" do
    experiment = SubjectExperiment.new

    assert_equal true, experiment.rollout.skipped_for(experiment)
  end

  test "variant assignment" do
    experiment = SubjectExperiment.new

    assert_nil experiment.rollout.variant_for(experiment)
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }

    use_rollout :inactive
  end
end
