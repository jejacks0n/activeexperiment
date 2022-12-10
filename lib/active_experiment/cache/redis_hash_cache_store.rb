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
