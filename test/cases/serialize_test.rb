# frozen_string_literal: true

require "helper"

class SerializeTest < ActiveSupport::TestCase
  test "serializing an experiment" do
    expected = {
      experiment: "serialize_test/subject_experiment",
      run_id: "1fbde0db-2c9f-4ed8-83b7-b30293d644ae",
      run_key: "d76381b585686083ce758b3813d4b056fe5855507fce9c9894e490b053eb90dc",
      variant: :treatment,
      variant_source: nil,
      skipped: false,
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
