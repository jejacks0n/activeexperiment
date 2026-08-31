# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# rdoc --main README.rdoc -i lib/active_experiment/**/*

task default: :test

desc "Run the unit and integration tests"
task test: ["test:units", "test:integration"]

namespace :test do
  Rake::TestTask.new("units") do |t|
    t.description = "Run the unit tests"
    t.libs << "test"
    t.test_files = FileList["test/cases/**/*_test.rb"]
    t.verbose = true
    t.warning = true
    t.ruby_opts = ["--dev"] if defined?(JRUBY_VERSION)
  end

  # Integration tests boot a generated Rails app, so they run in their own
  # process rather than alongside the unit tests.
  Rake::TestTask.new("integration") do |t|
    t.description = "Run the integration tests against a generated Rails app"
    t.libs << "test"
    t.test_files = FileList["test/integration/**/*_test.rb"]
    t.verbose = true
    t.warning = false
    t.ruby_opts = ["--dev"] if defined?(JRUBY_VERSION)
  end
end
