# frozen_string_literal: true

require "active_support/cache"

module ActiveExperiment
  # == Caching
  #
  # Active Experiment can use caching for variant assignments. Caching is a
  # complex topic, and unlike a lot of caching strategies where a key can
  # expire and/or be cleaned up automatically, Active Experiment requires a
  # cache store that will hold a given cache key for the lifetime of the
  # experiment.
  #
  # Since an experiment cache has to live for the lifetime of the experiment,
  # there are some special considerations about the size of the cache and how
  # we might clean it up after an experiment is removed, and also if/when to
  # use caching at all.
  #
  # == When to Use Caching
  #
  # In simple experiments caching may not be required, but as experiments get
  # more complex, caching starts to become a more important aspect to consider.
  # Because of this, caching can be configured on a per experiment basis.
  #
  # When should you consider caching? Exclusions and segmenting rules can often
  # benefit from caching, and so it should be considered whenever adding
  # segment rules to an experiment.
  #
  # For example, here's an experiment that highlights why caching can be an
  # important consideration when adding a segment rule:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #
  #     segment :older_accounts, into: :red
  #
  #     private
  #
  #     def older_accounts
  #       context.created_at < 1.week.ago
  #     end
  #   end
  #
  # If caching isn't used for this experiment, a new account might be assigned
  # the blue variant initially, and within a week the variant would switch to
  # red because they shift into the "older_accounts" segment.
  #
  # In some scenarios it might be desirable to allow contexts to move between
  # the segments, but in most cases it's not.
  #
  # == Cache Considerations
  #
  # The cache store used should be a long lived cache, such as Redis, or even a
  # database. The cache store should also be able to handle the number of keys
  # that will be stored in it.
  #
  # For example, if you have 100 users and 100 posts, and define an experiment
  # that runs on all users viewing all posts, you'll have a cache potential of
  # ~1,000,000 entries for that experiment alone.
  #
  # Here's an example of what that means, and how you can consider the cache
  # size:
  #
  #   User.count # => 100
  #   Post.count # => 100
  #   MyExperiment.run(user: user, post: post) # => cache potential: ~1,000,000
  #
  # Now, will that potential ever be hit? It's hard to say, and the answer is
  # dependent on where the experiment is being run, and other considerations
  # like those.
  #
  # If the same experiment is run only on posts (or users), the cache potential
  # would be limited to 100.
  #
  # == Custom Cache Stores
  #
  # Custom cache stores can be created and registered, as long as they adhere
  # to the standard interface in +ActiveSupport::Cache::Store+ they can be
  # used -- provided it can handle the long lived caching nature required by
  # Active Experiment.
  #
  # == Configuring Caching
  #
  # Caching can be configured globally, and overridden on a per experiment
  # basis. By default the cache store used is the standard +:null_store+ as its
  # defined in +ActiveSupport::Cache::NullStore+. This is a no-op cache store
  # that doesn't actually cache anything but provides a consistent interface.
  #
  # Active Experiment ships with a functional cache store based on using the
  # Redis hash data type (https://redis.io/docs/data-types/hashes/). This cache
  # store expects a redis instance or pool that hasn't been configured to auto
  # expire keys.
  #
  # To configure the cache store globally:
  #
  #   ActiveExperiment::Base.cache_store = :redis_hash
  #
  # To configure the cache store on a per experiment basis:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #
  #     use_cache_store :redis_hash
  #   end
  module Caching
    extend ActiveSupport::Concern

    included do
      class_attribute :cache_store, instance_writer: false, instance_predicate: false

      self.default_cache_store = :null_store
    end

    module ClassMethods
      def inherited(subclass)
        super
        subclass.default_cache_store = @default_cache_store
      end

      def default_cache_store=(name_or_cache_store)
        use_cache_store(name_or_cache_store)
        @default_cache_store = name_or_cache_store
      end

      def clear_cache(cache_key_prefix = nil)
        cache_store.delete_matched(cache_key_prefix || name.underscore)
      end

      private
        def use_cache_store(name_or_cache_store, *args)
          case name_or_cache_store
          when Symbol, String
            self.cache_store = ActiveExperiment::Cache.lookup(name_or_cache_store, *args)
          else
            self.cache_store = name_or_cache_store
          end
        end
    end

    # The cache key prefix.
    #
    # This is used to namespace cache keys, and can be used to find all cache
    # keys for a given experiment.
    def cache_key_prefix
      name
    end

    # The cache key for a given experiment and experiment context.
    #
    # The cache key includes the experiment name and hexdigest generated by the
    # experiment context.
    def cache_key
      [cache_key_prefix, run_key.slice(0, 32)].join("/")
    end

    # Store the variant assignment in the cache.
    #
    # Raises an +ExecutionError+ if no variant has been assigned.
    def cache_variant!
      raise ExecutionError, "No variant assigned" unless variant.present?

      cache_store.write(self, variant)
    end

    private
      def cached_variant(variant, &block)
        cache_store.fetch(self, skip_nil: true) { variant || block&.call }
      end
  end
end
