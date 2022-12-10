# frozen_string_literal: true

require "helper"

class InactiveRolloutTest < ActiveSupport::TestCase
  test "being enabled" do
    experiment = SubjectExperiment.new

    assert_equal false, experiment.rollout.enabled_for(experiment)
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
