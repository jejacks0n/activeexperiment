# frozen_string_literal: true

require "helper"

class GlobalIDTest < ActiveSupport::TestCase
  include LogHelpers

  test "generating the run key with global ids" do
    experiment = SubjectExperiment.new(GlobalIDObject.new)
    run_key = experiment.run_key

    assert_equal "67d9a9096d9506b04623b53015502829f09379a9efe61e295437675a6fcd7282", run_key
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

  test "raising when an identifier fails, since the run key can't be stable" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.new(GlobalIDObject.new(id: 666))
    end

    assert_includes error.message, "Unable to generate a stable run key"
    assert_includes error.message, "RuntimeError: to_global_id"
  end

  test "raising for objects that can't be identified at all" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.new(id: Object.new)
    end

    assert_includes error.message, "Unable to generate a stable run key"
    assert_includes error.message, "unsafe_context_digest"
  end

  test "falling back to inspect when unsafe_context_digest is opted into" do
    SubjectExperiment.unsafe_context_digest = true

    experiment = SubjectExperiment.new(GlobalIDObject.new(id: 666))

    assert_equal 64, experiment.run_key.length
  ensure
    SubjectExperiment.unsafe_context_digest = false
  end

  test "logging global ids when an identifier fails" do
    SubjectExperiment.unsafe_context_digest = true

    capture_logger do |logger|
      SubjectExperiment.run(GlobalIDObject.new(id: 666))

      context = %{with context: #<GlobalIDObject:0xXXXXXX @id=666>}
      assert_equal <<~MESSAGES, logger.messages
        SubjectExperiment[key]  Running global_id_test/subject_experiment (Run ID: 1fbde0db) #{context}
        SubjectExperiment[key]  Completed running control variant (Duration: 0.0ms | Allocations: 0)
      MESSAGES
    end
  ensure
    SubjectExperiment.unsafe_context_digest = false
  end

  test "generating the same run key regardless of context hash ordering" do
    a = SubjectExperiment.new(account: 1, user: GlobalIDObject.new)
    b = SubjectExperiment.new(user: GlobalIDObject.new, account: 1)

    assert_equal a.run_key, b.run_key
  end

  test "generating the same run key for nested hashes written in any order" do
    a = SubjectExperiment.new(outer: { a: 1, b: { c: 2, d: 3 } })
    b = SubjectExperiment.new(outer: { b: { d: 3, c: 2 }, a: 1 })

    assert_equal a.run_key, b.run_key
  end

  test "generating different run keys when array order differs" do
    a = SubjectExperiment.new(ids: [1, 2])
    b = SubjectExperiment.new(ids: [2, 1])

    assert_not_equal a.run_key, b.run_key
  end

  class SubjectExperiment < ActiveExperiment::Base
    control { }

    def log_context?
      true
    end
  end
end
