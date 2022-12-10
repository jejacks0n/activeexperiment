# frozen_string_literal: true

module ActiveExperiment
  # == Cache Stores
  #
  # TODO: finish documenting.
  module Cache
    extend ActiveSupport::Autoload

    autoload :ActiveRecordCacheStore
    autoload :RedisHashCacheStore

    CACHE_STORE_SUFFIX = "CacheStore"
    private_constant :CACHE_STORE_SUFFIX

    # Allows looking up a cache store by name.
    #
    # Raises an +ArgumentError+ if the cache store isn't found.
    def self.lookup(name, *args)
      const_get("#{name.to_s.camelize}#{CACHE_STORE_SUFFIX}").new(*args)
    rescue NameError
      store = ActiveSupport::Cache.lookup_store(name, *args)
      raise ArgumentError, "No cache store found for #{name.inspect}" unless store

      store
    end
  end
end
