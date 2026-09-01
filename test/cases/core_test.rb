# frozen_string_literal: true

require "helper"

class CoreTest < ActiveSupport::TestCase
  include LogHelpers

  test "a run that never needs a run key doesn't build one" do
    capture_logger(logger: false, with_subscriber: nil) do
      experiment = SkippedExperiment.new(id: 1)
      experiment.run

      assert_nil experiment.instance_variable_get(:@run_key)
      assert_nil experiment.instance_variable_get(:@run_id)
    end
  end

  test "the run key is built once and kept" do
    experiment = SubjectExperiment.new(id: 1)

    assert_equal experiment.run_key, experiment.run_key
    assert_equal 64, experiment.run_key.length
  end

  test "an unstable context is still rejected when the experiment is built" do
    # Not deferred along with the digest: a skipped experiment never asks for a
    # run key, so deferring would leave a bad context raising only once the
    # experiment was ramped up.
    assert_raises(ArgumentError) { SubjectExperiment.new(id: Object.new) }
  end

  test "setting multiple options" do
    expect = { foo: :bar, bar: :qux, baz: :foo }
    result = SubjectExperiment.set(variant: :hash, foo: :bar, bar: :baz).run do |experiment|
      experiment.set(bar: :qux, baz: :foo)
    end

    assert_equal expect, result
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:hash) { @options }
    variant(:json) { @options.to_json }
  end

  class SkippedExperiment < ActiveExperiment::Base
    variant(:red) { "red" }

    use_rollout :inactive
  end
end
