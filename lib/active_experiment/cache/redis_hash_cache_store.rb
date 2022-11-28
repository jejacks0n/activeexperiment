# frozen_string_literal: true

require "active_support/cache/redis_cache_store"

module ActiveExperiment
  module Cache
    # == Active Experiment Redis Hash Cache Store
    #
    # This cache store is an implementation on top of the redis hash data type
    # (https://redis.io/docs/data-types/hashes/) and expects that the cache
    # will live until the experiment is cleaned up and removed.
    #
    # This is a good cache store to use with Active Experiment because of the
    # optimized way that redis stores hashes.
    #
    # The data structure:
    #   key: experiment.name
    #   fields: run key => variant name
    #
    # To use this cache in an experiment:
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     variant(:red) { "red" }
    #     variant(:blue) { "blue" }
    #
    #     use_cache_store :redis_hash
    #   end
    class RedisHashCacheStore < ActiveSupport::Cache::RedisCacheStore
    end
  end
end
