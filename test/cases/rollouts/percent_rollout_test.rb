# frozen_string_literal: true

require "helper"

class PercentRolloutTest < ActiveSupport::TestCase
  def distribution_over_every_bucket
    experiment = SubjectExperiment.new
    rollout = SubjectExperiment.rollout

    (0...100).each_with_object(Hash.new(0)) do |crc, counts|
      Zlib.stub(:crc32, crc) { counts[rollout.variant_for(experiment)] += 1 }
    end
  end

  test "variants are assigned in even distribution when no rules are given" do
    SubjectExperiment.use_rollout(:percent)

    assert_equal({ red: 34, blue: 33, green: 33 }, distribution_over_every_bucket)
  end

  test "variants are assigned in exactly the specified distribution" do
    SubjectExperiment.use_rollout(:percent, rules: { red: 25, blue: 30, green: 45 })

    assert_equal({ red: 25, blue: 30, green: 45 }, distribution_over_every_bucket)
  end

  test "variants are assigned in exactly the specified distribution using an array" do
    SubjectExperiment.use_rollout(:percent, rules: [25, 30, 45])

    assert_equal({ red: 25, blue: 30, green: 45 }, distribution_over_every_bucket)
  end

  test "every variant is reachable when running real contexts" do
    SubjectExperiment.use_rollout(:percent, rules: { red: 25, blue: 30, green: 45 })

    results = 100.times.map { |i| SubjectExperiment.run("context-#{i}") }

    assert_empty results - ["red", "blue", "green"]
    assert_equal ["blue", "green", "red"], results.uniq.sort
  end

  test "validations are run for the percentage sum on hashes" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.use_rollout(:percent, rules: { red: 25, blue: 30 })
    end

    assert_equal "The provided rules total 55%, but should be 100%", error.message
  end

  test "validations are run for the variant names on hashes" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.use_rollout(:percent, rules: { red: 25, blue: 30, purple: 45 })
    end

    assert_equal "The provided rules don't match the variants: purple, green", error.message
  end

  test "the percentage sum is validated when the rollout is declared before the variants" do
    error = assert_raises(ArgumentError) do
      Class.new(ActiveExperiment::Base) do
        def self.name = "RulesBeforeVariantsExperiment"

        use_rollout :percent, rules: { red: 30, blue: 30 }
        variant(:red) { "red" }
        variant(:blue) { "blue" }
      end
    end

    assert_equal "The provided rules total 60%, but should be 100%", error.message
  end

  test "the percentage sum is validated on arrays declared before the variants" do
    error = assert_raises(ArgumentError) do
      Class.new(ActiveExperiment::Base) do
        def self.name = "ArrayRulesBeforeVariantsExperiment"

        use_rollout :percent, rules: [30, 30]
        variant(:red) { "red" }
        variant(:blue) { "blue" }
      end
    end

    assert_equal "The provided rules total 60%, but should be 100%", error.message
  end

  test "the variant names are checked on the first run when the rollout is declared first" do
    # Nothing to compare them against at declaration, so the check waits until
    # a variant is being assigned and there is.
    experiment = Class.new(ActiveExperiment::Base) do
      def self.name = "DeferredNamesExperiment"

      use_rollout :percent, rules: { red: 50, purple: 50 }
      variant(:red) { "red" }
      variant(:blue) { "blue" }
    end

    assert_instance_of ActiveExperiment::Rollouts::PercentRollout, experiment.rollout

    error = assert_raises(ArgumentError) { experiment.run(id: 1) }

    assert_equal "The provided rules don't match the variants: purple, blue", error.message
  end

  test "the deferred check keeps raising rather than only failing once" do
    experiment = Class.new(ActiveExperiment::Base) do
      def self.name = "RepeatedlyDeferredExperiment"

      use_rollout :percent, rules: { red: 50, purple: 50 }
      variant(:red) { "red" }
      variant(:blue) { "blue" }
    end

    3.times { |i| assert_raises(ArgumentError) { experiment.run(id: i) } }
  end

  test "a rollout declared before the variants runs when the rules do match" do
    experiment = Class.new(ActiveExperiment::Base) do
      def self.name = "DeferredValidExperiment"

      use_rollout :percent, rules: { red: 100, blue: 0 }
      variant(:red) { "red" }
      variant(:blue) { "blue" }
    end

    assert_equal "red", experiment.run(id: 1)
  end

  test "validations are run for the percentage sum on arrays" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.use_rollout(:percent, rules: [25, 30])
    end

    assert_equal "The provided rules total 55%, but should be 100%", error.message
  end

  test "validations are run for the length of the rules on arrays" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.use_rollout(:percent, rules: [25, 15, 15, 45])
    end

    assert_equal "The provided rules don't match the number of variants", error.message
  end

  test "describing an even split" do
    SubjectExperiment.use_rollout(:percent)

    described = SubjectExperiment.rollout.describe

    assert_equal :percent, described[:type]
    assert_equal({ red: 100 / 3.0, blue: 100 / 3.0, green: 100 / 3.0 }, described[:distribution])
  end

  test "describing rules given as a hash" do
    SubjectExperiment.use_rollout(:percent, rules: { red: 25, blue: 30, green: 45 })

    assert_equal({ red: 25.0, blue: 30.0, green: 45.0 },
      SubjectExperiment.rollout.describe[:distribution])
  end

  test "describing rules given as an array" do
    SubjectExperiment.use_rollout(:percent, rules: [25, 30, 45])

    # Positional against the variants, which is the whole of what an array
    # means -- so describing it has to put the names back.
    assert_equal({ red: 25.0, blue: 30.0, green: 45.0 },
      SubjectExperiment.rollout.describe[:distribution])
  end

  test "the rules are reported alongside the distribution they normalize to" do
    SubjectExperiment.use_rollout(:percent, rules: [25, 30, 45])

    assert_equal({ rules: [25, 30, 45] }, SubjectExperiment.rollout.describe[:options])
  end

  test "describing a rollout whose variants aren't registered yet" do
    rollout = ActiveExperiment::Rollouts::PercentRollout.new(nil)

    # Nothing to name the shares after, and nothing to compare a split
    # against, so there's no distribution to report.
    assert_empty rollout.describe[:distribution]
  end

  test "providing unknown types of rules isn't allowed" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.use_rollout(:percent, rules: :symbol)
    end

    assert_equal "ArgumentError", error.message
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }
    variant(:green) { "green" }

    def self.use_rollout(...)
      super
    end
  end
end
