# frozen_string_literal: true

require "helper"

class SerializeTest < ActiveSupport::TestCase
  test "serializing an experiment" do
    expected = {
      "experiment" => "serialize_test/subject_experiment",
      "run_id" => "1fbde0db-2c9f-4ed8-83b7-b30293d644ae",
      "run_key" => "6b32f3d80362e4ef28224e8173c0649e43649ed365036deaec91ed1ba9f7d478",
      "variant" => "treatment"
    }

    SecureRandom.stub(:uuid, "1fbde0db-2c9f-4ed8-83b7-b30293d644ae") do
      assert_equal expected, SubjectExperiment.new(id: 1).set(variant: :treatment).serialize
    end
  end

  class SubjectExperiment < ActiveExperiment::Base
    control { "control" }
    variant(:treatment) { "treatment" }
  end
end
