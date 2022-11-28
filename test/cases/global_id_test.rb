# frozen_string_literal: true

require "helper"

class GlobalIDTest < ActiveSupport::TestCase
  include LogHelpers

  test "generating the run key with global ids" do
    experiment = SubjectExperiment.new(GlobalIDObject.new)
    run_key = experiment.run_key

    assert_equal "f249850d807b46e3d430ea2c78904bab9b84078eb1f30eccddb95e3489a4df8f", run_key
  end

  test "logging global ids" do
    capture_logger do |logger|
      SubjectExperiment.run(GlobalIDObject.new)

      context = %{with context: "gid://ae/GlobalIDObject/42"}
      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running global_id_test/subject_experiment (Run ID: 1fbde0db) #{context}
        SubjectExperiment[key]  Completed running control variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  test "logging global ids when an identifier fails" do
    # TODO: should this raise since we can't generate a consistent run key?
    capture_logger do |logger|
      SubjectExperiment.run(GlobalIDObject.new(id: 666))

      context = %{with context: #<GlobalIDObject:0xXXXXXX @id=666>}
      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running global_id_test/subject_experiment (Run ID: 1fbde0db) #{context}
        SubjectExperiment[key]  Completed running control variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  end

  class SubjectExperiment < ActiveExperiment::Base
    control { }

    def log_context?
      true
    end
  end
end
