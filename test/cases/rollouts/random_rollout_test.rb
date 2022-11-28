# frozen_string_literal: true

require "helper"

class RandomRolloutTest < ActiveSupport::TestCase
  test "variants are assigned in mostly even distribution" do
    seeded_random do
      SubjectExperiment.use_rollout(:random)

      actual = { "red" => 0, "blue" => 0, "green" => 0 }
      expect = { "red" => 33, "blue" => 34, "green" => 33 }
      100.times { |i| actual[SubjectExperiment.run("#{i}")] += 1 }

      assert_equal expect, actual
    end
  end

  test "when caching is being used" do
    seeded_random do
      SubjectExperiment.use_rollout(:random, cache: true)
      experiment = SubjectExperiment.new

      assert_equal :red, SubjectExperiment.rollout.variant_for(experiment)
    end
  end

  test "when caching isn't being used" do
    seeded_random do
      SubjectExperiment.use_rollout(:random, cache: false)
      experiment = SubjectExperiment.new

      # To avoid caching nil is returned and the variant is assigned using #set.
      assert_nil SubjectExperiment.rollout.variant_for(experiment)
      assert_equal :red, experiment.variant
    end
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }
    variant(:green) { "green" }

    def self.use_rollout(...)
      super
    end
  end

  def seeded_random(seed = 105)
    srand(seed)
    yield
  ensure
    srand
  end
end
