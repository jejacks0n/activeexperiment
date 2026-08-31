# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require "tmpdir"
require "rails/generators/rails/app/app_generator"
require "minitest/spec"
require "helper"

dummy_app_path = Dir.mktmpdir + "/dummy"
# dummy_app_path = File.expand_path("dummy_", __dir__)

original_working_directory = Dir.pwd

Rails::Generators::AppGenerator.start(
  Rails::Generators::ARGVScrubber.new([
    "new", dummy_app_path,
    "--skip-gemfile",
    "--skip-bundle",
    "--skip-git",
    "--skip-javascript",
    "--skip-asset-pipeline",
    "--force",
    "--quiet",
    "-d", "sqlite3",
    "--template", File.expand_path("support/dummy_app_template.rb", __dir__)
  ]).prepare!
)

Dir.chdir(original_working_directory)

require "active_experiment/railtie"

require "#{dummy_app_path}/config/environment.rb"
require "rails/test_help"

Dir.chdir(original_working_directory)

Rails.backtrace_cleaner.remove_silencers!
