# frozen_string_literal: true

require "helper"

class PercentRolloutTest < ActiveSupport::TestCase
  test "variants are assigned in mostly even distribution" do
    SubjectExperiment.use_rollout(:percent)

    actual = { "red" => 0, "blue" => 0, "green" => 0 }
    expect = { "red" => 33, "blue" => 34, "green" => 33 }
    100.times { |i| actual[SubjectExperiment.run("44#{i}")] += 1 }

    assert_equal expect, actual
  end

  test "variants are assigned in specified distribution" do
    SubjectExperiment.use_rollout(:percent, rules: { red: 25, blue: 30, green: 45 })

    actual = { "red" => 0, "blue" => 0, "green" => 0 }
    expect = { "red" => 25, "blue" => 30, "green" => 45 }
    100.times { |i| actual[SubjectExperiment.run("93#{i}")] += 1 }

    assert_equal expect, actual
  end

  test "variants are assigned in specified distribution when specified using an array" do
    SubjectExperiment.use_rollout(:percent, rules: [25, 30, 45])

    actual = { "red" => 0, "blue" => 0, "green" => 0 }
    expect = { "red" => 25, "blue" => 30, "green" => 45 }
    100.times { |i| actual[SubjectExperiment.run("93#{i}")] += 1 }

    assert_equal expect, actual
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
