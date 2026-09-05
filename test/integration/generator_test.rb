# frozen_string_literal: true

require "open3"
require "integration_helper"

describe "using the rails generator" do
  i_suck_and_my_tests_are_order_dependent! # because performance of course.

  it "generates the expected files" do
    run_generator("MyExperiment red blue green") do |stdout, stderr, status|
      assert_equal 0, status
      assert_equal <<-OUTPUT, stdout
      invoke  test_unit
      create    test/experiments/my_experiment_test.rb
      create  app/experiments/my_experiment.rb
      create  app/experiments/application_experiment.rb
      OUTPUT
    end
  end

  it "generates a runnable test" do
    path = Rails.root.join("test/experiments/my_experiment_test.rb")
    generated = path.read

    assert_includes generated, "class MyExperimentTest < ActiveExperiment::TestCase"

    # The generated test is an empty shell, so it would pass no matter what it
    # inherited from. Give it an assertion that only resolves if the generated
    # case actually provides the experiment helpers, then run it for real.
    path.write(generated.sub(/^end$/, <<~RUBY))
      \s\stest "the generated case provides the experiment helpers" do
      \s\s\s\sassert_experiment_with(MyExperiment, variant: :red) do
      \s\s\s\s\s\sMyExperiment.set(variant: :red).run
      \s\s\s\send
      \s\send
      end
    RUBY

    run_command("rails test test/experiments/my_experiment_test.rb") do |stdout, stderr, status|
      assert_equal 0, status, "generated test failed:\n#{stdout}\n#{stderr}"
      assert_includes stdout, "1 runs"
      assert_includes stdout, "0 failures, 0 errors, 0 skips"
    end
  end

  it "generates a runnable experiment" do
    run_command(%(rails runner 'ActiveExperiment.logger = nil; e = MyExperiment.new(:ctx); e.run; puts e.variant')) do |stdout, stderr, status|
      assert_equal 0, status, stderr
      assert_includes %w[red blue green], stdout.strip
    end
  end

  it "can register custom rollouts" do
    path = Rails.root.join("app/experiments/my_experiment.rb")
    path.write(path.read.sub(/^(class MyExperiment .*)$/, "\\1\n  use_rollout :red"))

    run_command(%(rails runner 'ActiveExperiment.logger = nil; e = MyExperiment.new(:ctx); e.run; puts e.variant')) do |stdout, stderr, status|
      assert_equal 0, status, stderr
      assert_equal "red", stdout.strip
    end
  end

  it "doesn't allow duplicate experiment names" do
    run_generator("MyExperiment red blue green") do |stdout, stderr, status|
      assert_includes stderr,
        "The name 'MyExperiment' is either already used in your application "\
        "or reserved by Ruby on Rails. Please choose an alternative or use "\
        "--skip-collision-check or --force to skip this check and run this generator again."
    end
  end

  it "generates a migration that creates every table" do
    # From a clean schema, whatever any other integration test left behind --
    # the migration is what's under test, so it has to be the thing that
    # creates them.
    connection = ActiveRecord::Base.connection
    %w[
      active_experiment_experiments active_experiment_rollups
      active_experiment_overlaps active_experiment_cache_entries
    ].each { |table| connection.drop_table(table, if_exists: true) }

    run_command("rails g active_experiment:install") do |stdout, _stderr, status|
      assert_equal 0, status
      assert_match(/create\s+db\/migrate\/\d+_create_active_experiment_tables\.rb/, stdout)
    end

    migration = Dir[Rails.root.join("db/migrate/*_create_active_experiment_tables.rb")].sole
    generated = File.read(migration)

    # Both halves, and the comments that say when each is wanted -- the
    # migration is meant to be read and edited before it's run.
    assert_includes generated, "create_table :active_experiment_experiments"
    assert_includes generated, "create_table :active_experiment_rollups"
    assert_includes generated, "create_table :active_experiment_overlaps"
    assert_includes generated, "create_table :active_experiment_cache_entries"
    assert_includes generated, "== Recording"
    assert_includes generated, "== Caching"

    run_command("rails db:migrate") { |_stdout, _stderr, status| assert_equal 0, status }

    connection = ActiveRecord::Base.connection
    connection.schema_cache.clear!

    %w[
      active_experiment_experiments active_experiment_rollups
      active_experiment_overlaps active_experiment_cache_entries
    ].each { |table| assert connection.table_exists?(table), "#{table} wasn't created" }

    # Every table an upsert conflicts against needs its unique index.
    assert connection.indexes("active_experiment_cache_entries").any? { |i| i.unique && i.columns == ["key"] }
    assert connection.indexes("active_experiment_rollups").any? { |i| i.unique }
  ensure
    File.delete(*Dir[Rails.root.join("db/migrate/*_create_active_experiment_tables.rb")])
  end

  def run_generator(options, &block)
    run_command("rails g experiment #{options}", &block)
  end

  def run_command(command, &block)
    # These run in a child process, which only inherits a load path that can
    # find the gem when the suite was started through bundler. Put lib on it
    # explicitly so `rake` and `bundle exec rake` behave the same.
    lib_path = File.expand_path("../../lib", __dir__)
    env = { "RUBYOPT" => "-I#{lib_path} #{ENV["RUBYOPT"]}".strip }

    Dir.chdir(Rails.root) do
      stdout, stderr, status = Open3.capture3(env, command)
      block.call(stdout, stderr, status)
    end
  end
end
