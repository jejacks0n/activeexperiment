# frozen_string_literal: true

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
    #     t.binary :value, null: false
    #   end
    #
    #   add_index :active_experiment_cache_entries, :key, unique: true
    #
    # == Database Support
    #
    # The value column is binary because that's what entries serialize to -- a
    # payload that leads with a null byte and isn't necessarily valid in the
    # connection's encoding. PostgreSQL rejects that outright in a text or
    # varchar column, and MySQL will too unless the column is binary.
    #
    # A +t.string :value+ column still works on SQLite, which doesn't enforce
    # column types, so tables created before this was documented don't need
    # migrating. Anything else wants +t.binary+.
    #
    # The statements are written with +?+ placeholders and quoted through the
    # connection, so they don't depend on a particular adapter's bind syntax.
    #
    # SQLite and PostgreSQL are both covered by the test suite, the latter
    # against a real server in CI. MySQL should work on the same basis -- it
    # takes the same +x'..'+ binary literal SQLite does -- but nothing verifies
    # that, so treat it as untested.
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

      def length(options = nil)
        options = merged_options(options)
        execute(<<~SQL).first["count"]
          SELECT COUNT(key) AS count FROM #{table_name(options)}
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
          DELETE FROM #{table_name(options)} WHERE key LIKE ?
        SQL
      end

      private
        def read_entry(key, **options)
          result = execute(<<~SQL, key)
            SELECT value FROM #{table_name(options)} WHERE key = ?
          SQL

          deserialize_entry(column_value(result, "value"))
        end

        def write_entry(key, entry, **options)
          return false if options[:unless_exist] && exist?(key, options)

          execute(<<~SQL, key, binary(serialize_entry(entry, **options)))
            INSERT INTO #{table_name(options)} (key, value) VALUES (?, ?)
          SQL

          true
        end

        def delete_entry(key, **options)
          execute(<<~SQL, key)
            DELETE FROM #{table_name(options)} WHERE key = ?
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

        def column_value(result, column)
          row = result&.first
          return if row.nil?

          type = result.column_types[column]
          type ? type.deserialize(row[column]) : row[column]
        end

        def binary(payload)
          ActiveRecord::Type::Binary::Data.new(payload)
        end

        def execute(sql, *binds)
          sql = ActiveRecord::Base.sanitize_sql_array([sql, *binds]) if binds.any?

          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.exec_query(sql, "ActiveExperiment::Cache")
          end
        end
    end
  end
end
