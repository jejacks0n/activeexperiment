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
    #   key: experiment name
    #   fields: key => entry
    #
    # To use this cache in an experiment:
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     variant(:red) { "red" }
    #     variant(:blue) { "blue" }
    #
    #     use_cache_store :redis_hash
    #   end
    #
    # == Connecting
    #
    # Anything passed along with the store name is handed to
    # +ActiveSupport::Cache::RedisCacheStore+, so the connection is configured
    # the same way Rails configures its own Redis cache. Point it at a server
    # with a url:
    #
    #   use_cache_store :redis_hash, url: ENV["EXPERIMENT_REDIS_URL"]
    #
    # Or hand it a connection directly, or a proc that builds one, which defers
    # connecting until the store is first used:
    #
    #   use_cache_store :redis_hash, redis: -> { Redis.new(url: ...) }
    #
    # Connections are pooled by default, and the pool is configured the way it
    # is for any of the Rails cache stores:
    #
    #   use_cache_store :redis_hash, url: ..., pool: { size: 5, timeout: 5 }
    #
    # With nothing passed it connects to redis on localhost, which is only
    # really useful in development. Because assignments have to survive for the
    # life of the experiment, it's worth considering whether they belong on the
    # same server as the rest of the application's caching -- see below.
    #
    # == Entries Never Expire
    #
    # Redis expiry is per key, and this store keeps the entire experiment in
    # one hash, so there's nowhere to have a TTL on an individual assignment.
    # That's deliberate -- an assignment that expires mid experiment wouldn't
    # be stable. Entries live, and should live until the experiment is cleaned
    # up with +MyExperiment.clear_cache+.
    #
    # So +expires_in+ and +race_condition_ttl+ are accepted and ignored, as is
    # +unless_exist+.
    #
    # Make sure that the server itself is configured correctly, because its
    # eviction policy has to leave these entries alone as well. Under an
    # +allkeys-lru+ or +allkeys-random+ +maxmemory-policy+, redis will evict
    # experiment hashes under memory pressure like anything else, and every
    # evicted subject is reassigned from scratch on its next run.
    #
    # Use a +volatile-*+ policy, which only evicts keys that have a TTL set and
    # so can't touch these, or +noeviction+, or give experiments their own
    # redis away from data that's expected to be evicted.
    class RedisHashCacheStore < ActiveSupport::Cache::RedisCacheStore
      def length(hkey = nil)
        if hkey
          failsafe :read_hlen do
            redis.then { |c| c.hlen(hkey) }
          end
        else
          failsafe :read_dbsize do
            redis.then { |c| c.dbsize }
          end
        end
      end

      private
        def hkey(key)
          parts = key.to_s.split(":")
          run_key = parts.pop
          [Array(parts).join(":"), run_key]
        end

        def read_serialized_entry(key, raw: false, **options)
          failsafe :read_entry do
            redis.then { |c| c.hget(*hkey(key)) }
          end
        end

        def write_serialized_entry(key, payload, raw: false, unless_exist: false, expires_in: nil, race_condition_ttl: nil, pipeline: nil, **options)
          # TODO: Support pipeline?
          failsafe :write_entry, returning: false do
            redis.then { |c| c.hset(*hkey(key), payload) }
          end
        end

        def delete_entry(key, **options)
          failsafe :delete_entry, returning: false do
            redis.then { |c| c.hdel(*hkey(key)) }
          end
        end
    end
  end
end
