# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rdoc/task"
require_relative "lib/active_experiment/version"

desc "Generate API documentation using sdoc"
RDoc::Task.new("doc:api") do |rdoc|
  ENV["HORO_PROJECT_NAME"] ||= "Active Experiment"
  ENV["HORO_PROJECT_VERSION"] ||= "v#{ActiveExperiment.version}"
  ENV["HORO_BADGE_VERSION"] ||= "v#{ActiveExperiment.version}"

  rdoc.generator = "sdoc"
  rdoc.template = "rails"
  rdoc.main = "README.md"
  rdoc.title = "Active Experiment API Documentation"
  rdoc.rdoc_dir = "doc"
  rdoc.rdoc_files.include("README.md", "CHANGELOG.md", "lib/**/*.rb")
end

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
