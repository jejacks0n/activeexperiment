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
    skip("implement me")
  end

  it "generates a runnable experiment" do
    skip("implement me")
  end

  it "can register custom rollouts" do
    skip("implement me")
  end

  it "doesn't allow duplicate experiment names" do
    run_generator("MyExperiment red blue green") do |stdout, stderr, status|
      assert_includes stderr,
        "The name 'MyExperiment' is either already used in your application "\
        "or reserved by Ruby on Rails. Please choose an alternative or use "\
        "--skip-collision-check or --force to skip this check and run this generator again."
    end
  end

  def run_generator(options, &block)
    Dir.chdir(Rails.root) do
      stdout, stderr, status = Open3.capture3("rails g experiment #{options}")
      block.call(stdout, stderr, status)
    end
  end
end
