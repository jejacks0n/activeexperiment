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
      use_cache_store :memory_store, namespace: "_exp_"
    end

    assert_instance_of ActiveSupport::Cache::MemoryStore,
      MemoryCacheStoreExperiment.cache_store
  end

  test "using the redis hash cache store on an experiment" do
    RedisHashCacheStoreExperiment = Class.new(SubjectExperiment) do
      use_cache_store :redis_hash, namespace: "_exp_"
    end

    assert_instance_of ActiveExperiment::Cache::RedisHashCacheStore,
      RedisHashCacheStoreExperiment.cache_store
  end

  test "using a custom cache store class on an experiment" do
    CustomClassStore = Class.new(ActiveSupport::Cache::Store)
    CustomClassStoreExperiment = Class.new(SubjectExperiment) do
      use_cache_store CustomClassStore.new(namespace: "_exp_")
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

  test "clearing an experiments cache" do
    experiment = SubjectExperiment.new
    experiment.run

    assert_not_nil SubjectExperiment.cache_store.read(experiment.cache_key)

    SubjectExperiment.clear_cache

    assert_nil SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  test "caching a variant for a collection of contexts" do
    SubjectExperiment.set(variant: :blue).cache_each([1, 2, 3])

    [
      "caching_test/subject_experiment:ea1f2eae48ec6532f68566524f8555ba",
      "caching_test/subject_experiment:a1288c4dbda59f4a75681512d0060ec9",
      "caching_test/subject_experiment:baca0c7761def3cf0e76969bfd1fe769"
    ].each do |key|
      assert_equal :blue, SubjectExperiment.cache_store.read(key)
    end
  end

  test "assigning the name of a cache store to the attribute that holds one" do
    # What `config.active_experiment.cache_store = :redis_hash` reaches. It
    # used to store the symbol and fail later, on the first cache access.
    error = assert_raises(ArgumentError) do
      SubjectExperiment.cache_store = :redis_hash
    end

    assert_match(/default_cache_store = :redis_hash/, error.message)
    assert_match(/use_cache_store :redis_hash/, error.message)
  end

  test "assigning a store to the attribute is still allowed" do
    original = SubjectExperiment.cache_store
    store = ActiveSupport::Cache::MemoryStore.new
    SubjectExperiment.cache_store = store

    assert_same store, SubjectExperiment.cache_store
  ensure
    SubjectExperiment.cache_store = original
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
