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
    # The unique index is required, not just recommended. Writes upsert on it to
    # stay safe when the same context is resolved by two requests at once, and
    # without it PostgreSQL and SQLite reject the statement outright while MySQL
    # quietly accumulates duplicate rows.
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
    # Table and column names go through the connection's quoting too, since
    # +key+ is a reserved word in MySQL and the quoting character isn't the
    # same everywhere.
    #
    # SQLite, PostgreSQL and MySQL are all covered by the test suite, the latter
    # two against real servers in CI.
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

      STATEMENT_NAME = "ActiveExperiment::Cache"
      private_constant :STATEMENT_NAME

      WRITE_STATEMENT = "INSERT INTO %<table>s (%<key>s, %<value>s) VALUES (?, ?) %<conflict>s"
      private_constant :WRITE_STATEMENT

      def length(options = nil)
        options = merged_options(options)

        query(options, "SELECT COUNT(%<key>s) AS count FROM %<table>s").first["count"]
      end

      def clear(options = nil)
        options = merged_options(options)

        update(options, "DELETE FROM %<table>s")
      end

      def delete_matched(matcher, options = nil)
        options = merged_options(options)

        update(options, "DELETE FROM %<table>s WHERE %<key>s LIKE ?", key_matcher(matcher, options))
      end

      private
        def read_entry(key, **options)
          result = query(options, "SELECT %<value>s FROM %<table>s WHERE %<key>s = ?", key)

          deserialize_entry(column_value(result, "value"))
        end

        def write_entry(key, entry, **options)
          payload = binary(serialize_entry(entry, **options))
          skip = !!options[:unless_exist]

          with_connection do |connection|
            verify_unique_index!(connection, options)

            begin
              affected = update(options, WRITE_STATEMENT, key, payload)

              skip ? affected > 0 : true
            rescue ActiveRecord::RecordNotUnique
              raise unless skip

              false
            rescue ActiveRecord::StatementInvalid
              check_unique_index!(connection, options)
              raise
            end
          end
        end

        def delete_entry(key, **options)
          update(options, "DELETE FROM %<table>s WHERE %<key>s = ?", key)

          true
        end

        # Writing a key that's already been written has to be allowed. Two
        # requests can resolve the same context at the same time, both miss the
        # read, and both write -- and pre-caching a collection more than once
        # (a rerun of a backfill task, say) does the same thing serially.
        #
        # The unique index on +key+ turns that second write into a conflict
        # rather than a duplicate row, and this clause turns the conflict into
        # an overwrite instead of a +RecordNotUnique+. Both writers resolved the
        # same variant for the same run key, so last write wins is a no-op.
        def conflict_clause(connection, names, skip)
          key, value = names.values_at(:key, :value)

          if connection.supports_insert_conflict_target?
            return "ON CONFLICT (#{key}) DO NOTHING" if skip

            "ON CONFLICT (#{key}) DO UPDATE SET #{value} = excluded.#{value}"
          elsif skip
            # No clause at all on MySQL. It has no DO NOTHING.
            ""
          elsif connection.try(:supports_insert_raw_alias_syntax?)
            "AS new ON DUPLICATE KEY UPDATE #{value} = new.#{value}"
          else
            "ON DUPLICATE KEY UPDATE #{value} = VALUES(#{value})"
          end
        end

        # PostgreSQL and SQLite reject the upsert outright when the unique index
        # is missing, so the rescue in +write_entry+ catches it there. MySQL
        # doesn't: ON DUPLICATE KEY UPDATE has nothing to conflict on and simply
        # inserts, so writes quietly pile up duplicate rows instead of failing.
        def verify_unique_index!(connection, options)
          return if connection.supports_insert_conflict_target?

          # Keyed by table alone: every statement goes through the one
          # ActiveRecord::Base pool, so there's only ever the one database.
          verified_indexes.compute_if_absent(table_name(options)) do
            check_unique_index!(connection, options)
            true
          end
        end

        def verified_indexes
          @verified_indexes ||= Concurrent::Map.new
        end

        # The conflict clause needs the unique index to resolve against, and the
        # adapters report that as a generic statement error. Checked only after
        # a write has already failed, so the extra lookup is off the hot path.
        def check_unique_index!(connection, options)
          table = table_name(options)
          return if connection.indexes(table).any? { |index| index.unique && index.columns == ["key"] }

          raise ExecutionError, <<~MESSAGE.squish
            The #{table} table needs a unique index on `key`. Writes upsert on
            it so that two requests resolving the same context at once don't
            collide. Add it with:
            `add_index :#{table}, :key, unique: true`
          MESSAGE
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

        def query(options, template, *binds)
          statement(options, template, *binds) do |connection, sql|
            connection.exec_query(sql, STATEMENT_NAME)
          end
        end

        def update(options, template, *binds)
          statement(options, template, *binds) do |connection, sql|
            connection.exec_update(sql, STATEMENT_NAME)
          end
        end

        # Identifiers are interpolated through the connection rather than
        # written into the statements directly: `key` is a reserved word in
        # MySQL and has to be quoted, the quoting character isn't the same
        # across adapters, and the table name is configurable.
        def statement(options, template, *binds, &block)
          with_connection do |connection|
            names = {
              table: connection.quote_table_name(table_name(options)),
              key: connection.quote_column_name("key"),
              value: connection.quote_column_name("value")
            }
            names[:conflict] = conflict_clause(connection, names, options[:unless_exist]) if template.include?("%<conflict>s")

            block.call(connection, sanitize(format(template, names), *binds))
          end
        end

        def sanitize(sql, *binds)
          return sql if binds.empty?

          ActiveRecord::Base.sanitize_sql_array([sql, *binds])
        end

        def with_connection(&block)
          ActiveRecord::Base.connection_pool.with_connection(&block)
        end
    end
  end
end
