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
    # == Clearing an Experiment
    #
    # +MyExperiment.clear_cache+ deletes by prefix, which is a +LIKE+ against
    # the key. On PostgreSQL a btree index over a column with a non C collation
    # can't serve a prefix match, so that's a sequential scan over every entry
    # for every experiment. Confirmed with +EXPLAIN+ under +en_US.UTF-8+. For a
    # cache large enough to care, add an index with the pattern operator class
    # alongside the unique one:
    #
    #   add_index :active_experiment_cache_entries, :key,
    #     opclass: :varchar_pattern_ops,
    #     name: "index_active_experiment_cache_entries_on_key_pattern"
    #
    # SQLite scans as well, because +LIKE+ is case insensitive there unless
    # +case_sensitive_like+ is turned on, which rules out its own index
    # optimization. That one isn't worth working around.
    #
    # == Choosing a Database
    #
    # Statements run against +ActiveRecord::Base+ unless the store is given a
    # class to use instead. Since entries are numerous and live for as long as
    # the experiment does, a busy application may not want them in the same
    # database everything else is in:
    #
    #   class CacheRecord < ActiveRecord::Base
    #     self.abstract_class = true
    #
    #     connects_to database: { writing: :experiments }
    #   end
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     use_cache_store :active_record, connection_class: CacheRecord
    #   end
    #
    # Reads go through the same class as writes. Pointing them at a replica
    # isn't supported, and wouldn't be safe: a read that misses because it's
    # behind resolves the variant again and writes what it resolved, which for
    # anything but a deterministic rollout can differ from what was already
    # stored for that context.
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

      # Not a backslash: SQLite has no default escape character at all, so one
      # has to be named, and naming a backslash means writing a literal that
      # MySQL reads differently depending on NO_BACKSLASH_ESCAPES.
      LIKE_ESCAPE = "!"
      private_constant :LIKE_ESCAPE

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

        update(options, "DELETE FROM %<table>s WHERE %<key>s LIKE ? ESCAPE '#{LIKE_ESCAPE}'",
          key_matcher(matcher, options))
      end

      private
        def read_entry(key, **options)
          result = query(options, "SELECT %<value>s FROM %<table>s WHERE %<key>s = ?", key)

          deserialize_entry(column_value(result, "value"))
        end

        def write_entry(key, entry, **options)
          payload = binary(serialize_entry(entry, **options))
          skip = !!options[:unless_exist]

          with_connection(options) do |connection|
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

          # Keyed by the connection class and table.
          verified_indexes.compute_if_absent([connection_class(options).name, table_name(options)]) do
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

        # Escaped before the trailing wildcard is added, so only that wildcard
        # is one. Experiment names are underscored, and an underscore matches
        # any single character in a LIKE pattern -- without this, clearing
        # +foo_bar+ also clears +foo/bar+, which is what a namespaced
        # +Foo::Bar+ is named.
        def key_matcher(source, options)
          source = namespace_key(source, options)

          "#{connection_class(options).sanitize_sql_like(source, LIKE_ESCAPE)}%"
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
          with_connection(options) do |connection|
            names = {
              table: connection.quote_table_name(table_name(options)),
              key: connection.quote_column_name("key"),
              value: connection.quote_column_name("value")
            }
            names[:conflict] = conflict_clause(connection, names, options[:unless_exist]) if template.include?("%<conflict>s")

            block.call(connection, sanitize(options, format(template, names), *binds))
          end
        end

        def sanitize(options, sql, *binds)
          return sql if binds.empty?

          connection_class(options).sanitize_sql_array([sql, *binds])
        end

        def with_connection(options, &block)
          connection_class(options).connection_pool.with_connection(&block)
        end

        def connection_class(options)
          options[:connection_class] || ActiveRecord::Base
        end
    end
  end
end
