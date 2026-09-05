# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module ActiveExperiment # :nodoc:
  module Generators # :nodoc:
    # Creates the migration for the parts of Active Experiment that are backed
    # by Active Record -- recording, and optionally the assignment cache.
    #
    # Both are opt in, so the generated migration creates tables an application
    # may not want. It's meant to be read and edited before it's run.
    class InstallGenerator < Rails::Generators::Base # :nodoc:
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def create_migration_file
        migration_template "create_active_experiment_tables.rb",
          "db/migrate/create_active_experiment_tables.rb"
      end
    end
  end
end
