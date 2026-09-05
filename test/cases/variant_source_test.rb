# frozen_string_literal: true

require "helper"

class VariantSourceTest < ActiveSupport::TestCase
  test "not having been run" do
    assert_nil SubjectExperiment.new(id: 1).variant_source
  end

  test "the rollout assigning the variant" do
    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_equal :rollout, experiment.variant_source
  end

  test "a variant set before the run" do
    experiment = SubjectExperiment.new(id: 1).set(variant: :blue)
    experiment.run

    assert_equal :preset, experiment.variant_source
    assert_equal :blue, experiment.variant
  end

  test "a segment rule assigning the variant" do
    experiment = SegmentedExperiment.new(id: 1)
    experiment.run

    assert_equal :segment, experiment.variant_source
    assert_equal :blue, experiment.variant
  end

  test "reading the variant back out of the cache" do
    CachedExperiment.cache_store.clear

    first = CachedExperiment.new(id: 1)
    first.run
    assert_equal :rollout, first.variant_source

    second = CachedExperiment.new(id: 1)
    second.run

    assert_equal :cached, second.variant_source
    assert_equal first.variant, second.variant
  end

  test "a skipped run" do
    experiment = SkippedExperiment.new(id: 1)
    experiment.run

    assert_equal :skipped, experiment.variant_source
    assert_equal :red, experiment.variant
  end

  test "a skipped run with a variant set before it" do
    experiment = SkippedExperiment.new(id: 1).set(variant: :blue)
    experiment.run

    assert_equal :preset, experiment.variant_source
  end

  test "a rollout that doesn't assign anything" do
    experiment = UnassignedExperiment.new(id: 1)
    experiment.run

    assert_equal :default, experiment.variant_source
    assert_equal :red, experiment.variant
  end

  test "the source is serialized alongside the variant" do
    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_equal experiment.variant_source, experiment.serialize[:variant_source]
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }

    use_rollout :percent
    use_default_variant :red
  end

  class SegmentedExperiment < SubjectExperiment
    segment(into: :blue) { true }
  end

  class CachedExperiment < SubjectExperiment
    use_cache_store :memory_store
  end

  class SkippedExperiment < SubjectExperiment
    use_rollout :inactive
  end

  # A rollout that answers with nil, that will cause the default variant to be
  # assigned.
  class UnassignedExperiment < SubjectExperiment
    use_rollout Class.new(ActiveExperiment::Rollouts::BaseRollout) {
      def variant_for(*)
        nil
      end
    }.new(nil)
  end
end
