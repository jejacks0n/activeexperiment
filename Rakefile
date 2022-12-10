# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# rdoc --main README.rdoc -i lib/active_experiment/**/*

task default: :test
task test: "test:default"

namespace :test do
  Rake::TestTask.new("default") do |t|
    t.description = "Run tests"
    t.libs << "test"
    t.test_files = FileList["test/cases/**/*_test.rb"]
    t.verbose = true
    t.warning = true
    t.ruby_opts = ["--dev"] if defined?(JRUBY_VERSION)
  end
end
