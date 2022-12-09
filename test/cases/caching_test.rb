# frozen_string_literal: true

require "helper"

class CachingTest < ActiveSupport::TestCase
  def setup
    SubjectExperiment.cache_store.clear
  end

  test "the default cache store is the null store" do
    DefaultCacheStoreExperiment = Class.new(ActiveExperiment::Base)

    assert_instance_of ActiveSupport::Cache::NullStore,
      DefaultCacheStoreExperiment.cache_store
  end

  test "using an active support cache store on an experiment" do
    MemoryCacheStoreExperiment = Class.new(SubjectExperiment) do
      use_cache_store :memory_store
    end

    assert_instance_of ActiveSupport::Cache::MemoryStore,
      MemoryCacheStoreExperiment.cache_store
  end

  test "using the redis hash cache store on an experiment" do
    RedisHashCacheStoreExperiment = Class.new(SubjectExperiment) do
      use_cache_store :redis_hash
    end

    assert_instance_of ActiveExperiment::Cache::RedisHashCacheStore,
      RedisHashCacheStoreExperiment.cache_store
  end

  test "using a custom cache store class on an experiment" do
    CustomClassStore = Class.new(ActiveSupport::Cache::Store)
    CustomClassStoreExperiment = Class.new(SubjectExperiment) do
      use_cache_store CustomClassStore.new
    end

    assert_instance_of CustomClassStore,
      CustomClassStoreExperiment.cache_store
  end

  test "caching a variant that's been assigned" do
    experiment = SubjectExperiment.new
    result = experiment.set(variant: :blue).run

    assert_equal "blue", result
    assert_equal :blue, SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  test "caching a variant that's been resolved" do
    experiment = SubjectExperiment.new
    result = experiment.run

    assert_equal "red", result
    assert_equal :red, SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  test "when an experiment is skipped" do
    experiment = SkippedExperiment.new
    result = experiment.run

    assert_equal "red", result
    assert_nil SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  test "when an experiment is skipped and a variant has been assigned" do
    experiment = SkippedExperiment.new
    result = experiment.set(variant: :blue).run

    assert_equal "blue", result
    # TODO: Should this be cached?
    assert_nil SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  test "using the cache to lookup a variant" do
    experiment = SubjectExperiment.new
    SubjectExperiment.cache_store.write(experiment.cache_key, :blue)

    assert_equal "blue", experiment.run
  end

  test "caching a variant for a collection of contexts" do
    SubjectExperiment.set(variant: :blue).cache_each([1, 2, 3])

    [
      "caching_test/subject_experiment/ddcfc1505fdcb8b5c4022c4b6d4bb5da",
      "caching_test/subject_experiment/e862b4fc3c3287350118eaa1a4c561af",
      "caching_test/subject_experiment/e2eda826db2757a9110ebfc89ea15920"
    ].each do |key|
      assert_equal :blue, SubjectExperiment.cache_store.read(key)
    end
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }

    use_cache_store :memory_store
    use_default_variant :red
  end

  class SkippedExperiment < SubjectExperiment
    def skipped?
      true
    end
  end
end
