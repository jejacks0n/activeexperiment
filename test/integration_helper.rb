# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require "tmpdir"
require "rails/generators/rails/app/app_generator"
require "minitest/spec"
require "helper"

dummy_app_path = Dir.mktmpdir + "/dummy"
# dummy_app_path = File.expand_path("dummy_", __dir__)

Rails::Generators::AppGenerator.start(
  Rails::Generators::ARGVScrubber.new([
    "new", dummy_app_path,
    "--skip-gemfile",
    "--skip-bundle",
    "--skip-git",
    "--skip-javascript",
    "--force",
    "--quiet",
    "-d", "sqlite3",
    "--template", File.expand_path("support/dummy_app_template.rb", __dir__)
  ]).prepare!
)

require "#{dummy_app_path}/config/environment.rb"
require "rails/test_help"

Rails.backtrace_cleaner.remove_silencers!
