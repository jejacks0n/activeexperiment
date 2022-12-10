# frozen_string_literal: true

require "monitor"
require "active_record"

module ActiveExperiment
  module Cache
    # == Active Experiment Active Record Cache Store
    #
    # This cache store is an implementation on top of ActiveRecord and expects
    # that the cache will live until the experiment is cleaned up and removed.
    #
    # This is a useful but not particularly performant cache store. It's useful
    # because a lot of Rails projects already have a usable ActiveRecord
    # connection, and because it's likely to be a long lived datastore.
    #
    # This cache store doesn't use a model class directly, and instead executes
    # raw sql to minimize memory usage and allocations.
    #
    # The data structure:
    #   key: experiment name : run key
    #   value: cache entry
    #
    # To use this cache in an experiment the table needs to be created. All
    # experiments will use the same table by default for their cache store, and
    # can be distinguishable by the experiment name that's part of the cache
    # key.
    #
    #   create_table :active_experiment_cache_entries, id: false do |t|
    #     t.string :key, null: false
    #     t.string :value, null: false
    #   end
    #
    #   add_index :active_experiment_cache_entries, :key, unique: true
    #
    # Once a table is created, the cache store can be used in an experiment:
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     variant(:red) { "red" }
    #     variant(:blue) { "blue" }
    #
    #     use_cache_store :active_record
    #   end
    class ActiveRecordCacheStore < ActiveSupport::Cache::Store
      DEFAULT_TABLE_NAME = "active_experiment_cache_entries"

      def initialize(options = nil)
        super
        @connection = ActiveRecord::Base.connection
      end

      def length(options = nil)
        options = merged_options(options)
        execute(<<~SQL).first["COUNT(key)"]
          SELECT COUNT(key) FROM #{table_name(options)}
        SQL
      end

      def clear(options = nil)
        options = merged_options(options)
        execute(<<~SQL)
          DELETE FROM #{table_name(options)}
        SQL
      end

      def delete_matched(matcher, options = nil)
        options = merged_options(options)
        execute(<<~SQL, key_matcher(matcher, options))
          DELETE FROM #{table_name(options)} WHERE key LIKE $1
        SQL
      end

      private
        def read_entry(key, **options)
          results = execute(<<~SQL, key)&.first.try(:[], "value")
            SELECT value FROM #{table_name(options)} WHERE key = $1
          SQL

          deserialize_entry(results)
        end

        def write_entry(key, entry, **options)
          return false if options[:unless_exist] && exist?(key, options)

          execute(<<~SQL, key, serialize_entry(entry, **options))
            INSERT INTO #{table_name(options)} (key, value) VALUES ($1, $2)
          SQL

          true
        end

        def delete_entry(key, **options)
          execute(<<~SQL, key)
            DELETE FROM #{table_name(options)} WHERE key = $1
          SQL

          true
        end

        def table_name(options)
          options[:table_name] || DEFAULT_TABLE_NAME
        end

        def key_matcher(source, options)
          source = "#{source}%"

          return source unless options[:namespace]
          namespace_key(source, options)
        end

        def execute(sql, *args, prepare: true, **kws, &block)
          @connection.exec_query(sql, "SQL", args, prepare: prepare, **kws, &block)
        end
    end
  end
end
