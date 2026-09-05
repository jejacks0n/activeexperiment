# frozen_string_literal: true

require "active_record"

module ActiveExperiment
  module Recorders
    # == Active Experiment Active Record Recorder
    #
    # Records experiment activity into three tables. Most applications already
    # have a database, and unlike the assignments the cache store keeps, what a
    # recorder writes is small: a row per experiment, a row per variant per day,
    # and a row per pair of experiments that have been run together.
    #
    # Create the tables with:
    #
    #   bin/rails generate active_experiment:install
    #   bin/rails db:migrate
    #
    # Then turn recording on, globally or per experiment:
    #
    #   config.active_experiment.default_recorder = :active_record
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     use_recorder :active_record
    #   end
    #
    # == The Unique Indexes
    #
    # Every process buffers its own counts and flushes them as deltas, so writes
    # add to whatever is already stored rather than replacing it. That's done as
    # an upsert, which needs the unique indexes the generated migration creates
    # to conflict against -- without them the statement is rejected outright on
    # PostgreSQL and SQLite, and on MySQL duplicate rows quietly accumulate and
    # every count reads low.
    #
    # == Choosing a Database
    #
    # Statements run against +ActiveRecord::Base+'s connection. To keep
    # experiment data somewhere else, point the abstract parent at another
    # database from an initializer:
    #
    #   ActiveExperiment::Recorders::ActiveRecordRecorder::Record.connects_to(
    #     database: { writing: :experiments }
    #   )
    class ActiveRecordRecorder < BaseRecorder
      # The counters a rollup row accumulates. Kept in one place because the
      # write side names them for the insert and again for the conflict clause,
      # and the read side hands them back.
      COUNTERS = ([:runs, :skipped, :errored] + BaseRecorder::SOURCES.map { |s| :"from_#{s}" }).freeze

      class Record < ActiveRecord::Base # :nodoc:
        self.abstract_class = true
      end

      class Experiment < Record # :nodoc:
        self.table_name = "active_experiment_experiments"
      end

      class Rollup < Record # :nodoc:
        self.table_name = "active_experiment_rollups"
      end

      class Overlap < Record # :nodoc:
        self.table_name = "active_experiment_overlaps"
        self.table_name = "active_experiment_overlaps"
      end

      # The unique index each table's upsert conflicts against. Not optional --
      # see +check_schema!+ for what goes wrong without one.
      UNIQUE_INDEXES = {
        Experiment => ["name"],
        Rollup => ["experiment", "variant", "date"],
        Overlap => ["experiment_a", "variant_a", "experiment_b", "variant_b"]
      }.freeze

      def experiments
        Experiment.order(:name).map { |row| experiment_attributes(row) }
      end

      def experiment(experiment_name)
        row = Experiment.find_by(name: experiment_name.to_s)

        experiment_attributes(row) if row
      end

      # Written straight through rather than buffered, because unlike a count
      # these aren't deltas, and somebody is waiting to see them take effect.
      #
      # The seen-at timestamps are left entirely to +write_registry+, which is
      # the only thing that observes a run. Setting them here would mean
      # archiving an experiment -- the act of saying nobody runs it any more --
      # made it look like it had just run, and an experiment that gets a state
      # without ever having run should read as never seen rather than as seen
      # the moment somebody labelled it.
      def update_experiment(experiment_name, **attributes)
        attributes = attributes.merge(name: experiment_name.to_s)

        Experiment.upsert_all([attributes],
          **upsert_options(Experiment, replace: attributes.keys - [:name]))

        experiment(experiment_name)
      end

      def rollups(experiment_name, since: nil)
        scope = Rollup.where(experiment: experiment_name.to_s)
        scope = scope.where(date: since..) if since

        scope.order(:date, :variant).map do |row|
          { experiment: row.experiment, variant: row.variant.to_sym, date: row.date }
            .merge(COUNTERS.index_with { |counter| row[counter] })
        end
      end

      def overlaps(experiment_name)
        name = experiment_name.to_s
        scope = Overlap.where(experiment_a: name).or(Overlap.where(experiment_b: name))

        scope.order(count: :desc).map do |row|
          # Flipped so the experiment being asked about is always side A, which
          # is what a report about it wants. Pairs are stored in a canonical
          # order so that a pair is one row rather than two.
          flip = row.experiment_b == name
          {
            experiment: flip ? row.experiment_b : row.experiment_a,
            variant: (flip ? row.variant_b : row.variant_a).to_sym,
            other_experiment: flip ? row.experiment_a : row.experiment_b,
            other_variant: (flip ? row.variant_a : row.variant_b).to_sym,
            count: row.count,
            nested_count: row.nested_count,
            last_seen_at: row.last_seen_at
          }
        end
      end

      private
        def delete_recorded(experiment_name)
          Record.transaction do
            {
              experiments: Experiment.where(name: experiment_name).delete_all,
              rollups: Rollup.where(experiment: experiment_name).delete_all,
              # Matched on either side, because a pair is stored once in a
              # canonical order rather than once per experiment in it.
              overlaps: Overlap.where(experiment_a: experiment_name)
                .or(Overlap.where(experiment_b: experiment_name)).delete_all
            }
          end
        end

        def write(registry, runs, overlaps)
          Record.transaction do
            write_registry(registry)
            write_runs(runs)
            write_overlaps(overlaps)
          end
        # A missing table surfaces as whatever the adapter called it, and a
        # missing unique index surfaces before the statement is even built,
        # since +upsert_all+ looks for the conflict target first. Both mean the
        # migration hasn't been run, so both get checked before giving up.
        rescue ActiveRecord::StatementInvalid, ArgumentError
          check_schema!
          raise
        end

        def write_registry(registry)
          return if registry.empty?

          now = Time.current
          rows = registry.map do |name, details|
            {
              name: name,
              class_name: details[:class_name],
              variant_names: details[:variant_names].to_json,
              default_variant: details[:default_variant].to_s,
              rollout: details[:rollout].to_json,
              cache_store: details[:cache_store],
              first_seen_at: now,
              last_seen_at: now
            }
          end

          # +first_seen_at+ is left out of the conflict clause deliberately, so
          # that a row keeps the time it was first written. So are the columns
          # only +update_experiment+ writes: an experiment being run says
          # nothing about the state somebody put it in.
          Experiment.upsert_all(rows,
            **upsert_options(Experiment,
              replace: [:class_name, :variant_names, :default_variant, :rollout, :cache_store, :last_seen_at]))
        end

        def write_runs(runs)
          return if runs.empty?

          rows = runs.map do |(name, variant, date), counts|
            { experiment: name, variant: variant, date: date }
              .merge(COUNTERS.index_with { |counter| counts[counter] })
          end

          Rollup.upsert_all(rows, **upsert_options(Rollup, increment: COUNTERS))
        end

        def write_overlaps(overlaps)
          return if overlaps.empty?

          now = Time.current
          rows = overlaps.map do |(experiment_a, variant_a, experiment_b, variant_b), counts|
            {
              experiment_a: experiment_a,
              variant_a: variant_a,
              experiment_b: experiment_b,
              variant_b: variant_b,
              count: counts[:count],
              nested_count: counts[:nested_count],
              last_seen_at: now
            }
          end

          Overlap.upsert_all(rows,
            **upsert_options(Overlap, increment: [:count, :nested_count], replace: [:last_seen_at]))
        end

        # The options an upsert needs, which differ by adapter in two ways that
        # travel together.
        #
        # PostgreSQL and SQLite conflict against a named target and expose the
        # incoming row as +excluded+, so the stored row has to be qualified by
        # table name to tell the two apart. MySQL has neither: it conflicts
        # against whatever unique key the row violates, names the stored value
        # with a bare column and the incoming one with +VALUES()+, and rejects
        # +unique_by+ outright rather than ignoring it.
        #
        # Counters are added to what's already stored, since every process
        # flushes its own deltas. Everything else is overwritten.
        def upsert_options(model, increment: [], replace: [])
          model.connection_pool.with_connection do |connection|
            table = model.quoted_table_name
            targeted = connection.supports_insert_conflict_target?

            # PostgreSQL and SQLite reject the upsert outright when the unique
            # index is missing, so a mistake there surfaces on the first write.
            # MySQL doesn't: with nothing to conflict against it simply
            # inserts, duplicate rows accumulate, and every count reads low
            # forever. Checked up front there, once per model rather than per
            # write, because there's no failure to check after.
            verify_unique_index!(model, connection) unless targeted

            sets = increment.map do |column|
              column = connection.quote_column_name(column)
              targeted ? "#{column} = #{table}.#{column} + excluded.#{column}" : "#{column} = #{column} + VALUES(#{column})"
            end

            sets += replace.map do |column|
              column = connection.quote_column_name(column)
              targeted ? "#{column} = excluded.#{column}" : "#{column} = VALUES(#{column})"
            end

            options = { on_duplicate: Arel.sql(sets.join(", ")) }
            options[:unique_by] = UNIQUE_INDEXES.fetch(model) if targeted
            options
          end
        end

        def verify_unique_index!(model, connection)
          verified_indexes.compute_if_absent(model.name) do
            check_unique_index!(model, connection)
            true
          end
        end

        def verified_indexes
          @verified_indexes ||= Concurrent::Map.new
        end

        def check_unique_index!(model, connection)
          columns = UNIQUE_INDEXES.fetch(model)
          return if connection.indexes(model.table_name).any? { |index| index.unique && index.columns == columns }

          raise ExecutionError, <<~MESSAGE.squish
            The #{model.table_name} table needs a unique index on
            #{columns.to_sentence}. Every process flushes its own counts as
            deltas that are added to the stored row, and the upsert that does
            it has nothing to conflict against without one. Re-run
            `bin/rails generate active_experiment:install` for the migration
            that creates it.
          MESSAGE
        end

        # Checked only after a write has already failed, so it costs nothing on
        # the way through and a migration that hasn't been run says so instead
        # of surfacing as whatever the adapter called it.
        def check_schema!
          missing = UNIQUE_INDEXES.keys.reject(&:table_exists?).map(&:table_name)

          if missing.any?
            raise ExecutionError, <<~MESSAGE.squish
              The #{missing.to_sentence} #{"table".pluralize(missing.length)} the
              Active Record recorder writes to
              #{missing.length == 1 ? "doesn't" : "don't"} exist. Create
              #{missing.length == 1 ? "it" : "them"} with
              `bin/rails generate active_experiment:install` followed by
              `bin/rails db:migrate`.
            MESSAGE
          end

          UNIQUE_INDEXES.each_key do |model|
            model.connection_pool.with_connection { |connection| check_unique_index!(model, connection) }
          end
        end

        def experiment_attributes(row)
          {
            name: row.name,
            class_name: row.class_name,
            state: row.state.to_sym,
            variant_names: parse_json(row.variant_names, default: []).map(&:to_sym),
            default_variant: row.default_variant.presence&.to_sym,
            rollout: parse_json(row.rollout)&.deep_symbolize_keys,
            cache_store: row.cache_store,
            first_seen_at: row.first_seen_at,
            last_seen_at: row.last_seen_at,
            concluded_at: row.concluded_at,
            winning_variant: row.winning_variant.presence&.to_sym,
            notes: row.notes
          }
        end

        def parse_json(value, default: nil)
          return default if value.blank?

          ActiveSupport::JSON.decode(value)
        rescue JSON::ParserError
          default
        end
    end
  end
end
