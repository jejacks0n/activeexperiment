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
