# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module ActiveExperiment # :nodoc:
  module Generators # :nodoc:
    # Creates the migrations for the parts of Active Experiment that are backed
    # by Active Record.
    #
    # Recording and caching are independent, and most applications want one of
    # them rather than both, so they're separate migrations. Naming either one
    # generates only that one, and naming neither generates both.
    class InstallGenerator < Rails::Generators::Base # :nodoc:
      include ActiveRecord::Generators::Migration

      class_option :recorder, type: :boolean, default: false,
        desc: "Only the tables the Active Record recorder writes to"
      class_option :cache, type: :boolean, default: false,
        desc: "Only the table the Active Record cache store keeps assignments in"

      source_root File.expand_path("templates", __dir__)

      def create_recorder_migration
        return unless recorder?

        migration_template "create_active_experiment_recorder_tables.rb",
          "db/migrate/create_active_experiment_recorder_tables.rb"
      end

      def create_cache_migration
        return unless cache?

        migration_template "create_active_experiment_cache_entries.rb",
          "db/migrate/create_active_experiment_cache_entries.rb"
      end

      private
        # Asking for neither means asking for both, since that's what running
        # the generator with no arguments is going to mean.
        def everything?
          !options[:recorder] && !options[:cache]
        end

        def recorder?
          everything? || options[:recorder]
        end

        def cache?
          everything? || options[:cache]
        end
    end
  end
end
