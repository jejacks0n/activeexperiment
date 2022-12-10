# frozen_string_literal: true

require "helper"
require "redis"

REDIS = Redis.new(
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
) rescue nil

class RedisHashCacheStoreTest < ActiveSupport::TestCase
  def setup
    REDIS.flushall
  rescue Redis::CannotConnectError
    skip("Skipping because redis is not available")
  end

  test "clearing the entire cache for all experiments" do
    experiment = SubjectExperiment.new
    experiment.run

    assert_equal 1, experiment.cache_store.length

    experiment.cache_store.clear

    assert_equal 0, experiment.cache_store.length
  end

  test "clearing the cache for a specific experiment" do
    experiment = SubjectExperiment.new
    experiment.run

    assert_equal 1, experiment.cache_store.length

    experiment.cache_store.delete_matched(experiment.name)

    assert_equal 0, experiment.cache_store.length
  end

  test "clearing the cache for a specific experiment that has a namespace" do
    NamespacedCacheStoreExperiment = Class.new(SubjectExperiment) do
      use_cache_store :redis_hash, namespace: "_exp_"
    end

    experiment = NamespacedCacheStoreExperiment.new
    experiment.run

    assert_equal 1, experiment.cache_store.length

    experiment.cache_store.delete_matched(experiment.name)

    assert_equal 0, experiment.cache_store.length
  end

  test "caching resolved variants" do
    experiment = SubjectExperiment.new(id: 1)

    assert_equal "red", experiment.run
    assert_equal :red, experiment.cache_store.read(experiment.cache_key)
    assert_equal 1, experiment.cache_store.length

    SubjectExperiment.run(id: 2)
    SubjectExperiment.run(id: 3)

    assert_equal 1, experiment.cache_store.length
    assert_equal 3, experiment.cache_store.length(experiment.cache_key_prefix)
  end

  test "caching assigned variants" do
    experiment = SubjectExperiment.new
    experiment.set(variant: :blue)

    assert_equal "blue", experiment.run
    assert_equal :blue, experiment.cache_store.read(experiment.cache_key)
  end

  test "caching variants when segmented" do
    experiment = SubjectExperiment.new(segment_into_green: true)

    assert_equal "green", experiment.run
    assert_equal :green, experiment.cache_store.read(experiment.cache_key)
  end

  test "skipped experiments" do
    experiment = SubjectExperiment.new
    experiment.skip

    assert_nil experiment.run
    assert_nil experiment.cache_store.read(experiment.cache_key)
    assert_equal 0, experiment.cache_store.length
  end

  test "skipped experiments (through inactive rollout)" do
    InactiveExperiment = Class.new(SubjectExperiment) do
      use_rollout :inactive
      use_cache_store :redis_hash
    end

    experiment = InactiveExperiment.new
    experiment.set(variant: :blue)

    assert_equal "blue", experiment.run
    assert_nil experiment.cache_store.read(experiment.cache_key)
    assert_equal 0, experiment.cache_store.length
  end

  test "skipped experiments with an assigned variant" do
    experiment = SubjectExperiment.new
    experiment.set(variant: :blue)
    experiment.skip

    assert_equal "blue", experiment.run
    assert_nil experiment.cache_store.read(experiment.cache_key)
    assert_equal 0, experiment.cache_store.length
  end

  test "deleting a single entry" do
    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_equal 1, experiment.cache_store.length

    experiment.cache_store.delete(experiment.cache_key)

    assert_equal 0, experiment.cache_store.length
  end

  test "when a cache key already exists" do
    SubjectExperiment.set(variant: :green).run(id: 1)

    assert_equal 1, SubjectExperiment.cache_store.length

    experiment = SubjectExperiment.new(id: 1)

    assert_equal "green", experiment.run
    assert_equal 1, experiment.cache_store.length
    assert_equal 1, experiment.cache_store.length(experiment.cache_key_prefix)
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }
    variant(:green) { "green" }

    segment(into: :green) { context[:segment_into_green] }

    use_cache_store :redis_hash
  end
end
