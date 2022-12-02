# frozen_string_literal: true

require "helper"

class ExecutedTest < ActiveSupport::TestCase
  def setup
    ActiveExperiment::Executed.reset
    super
  end

  test "experiments that are run are available in the executed experiments" do
    SecureRandom.stub(:uuid, "1fbde0db") do
      SubjectExperiment.run("foo")
      SubjectExperiment.set(variant: :blue).run("bar")
    end

    assert_equal 2, ActiveExperiment::Executed.experiments.length
  end

  test "getting the experiments run as json" do
    SecureRandom.stub(:uuid, "1fbde0db") do
      SubjectExperiment.run("foo") # overridden in our json object!
      SubjectExperiment.set(variant: :blue).run("bar")
    end

    assert_equal JSON.parse(ActiveExperiment::Executed.to_json), {
      "executed_test/subject_experiment" => {
        "experiment" => "executed_test/subject_experiment",
        "run_id" => "1fbde0db",
        "run_key" => "1a4faf1902a78648456ead5dc882f514685936698e1c60094cf17c238fe1f858",
        "variant" => "blue",
      }
    }
  end

  test "getting the experiments run as a json array" do
    SecureRandom.stub(:uuid, "1fbde0db") do
      SubjectExperiment.run("foo")
      SubjectExperiment.set(variant: :blue).run("bar")
    end

    assert_equal JSON.parse(ActiveExperiment::Executed.to_json_array), [
      {
        "experiment" => "executed_test/subject_experiment",
        "run_id" => "1fbde0db",
        "run_key" => "1f82a46e1375cbd4e302489f0a1931908a50cd7216965687bee202d08cacf789",
        "variant" => "red"
      },
      {
        "experiment" => "executed_test/subject_experiment",
        "run_id" => "1fbde0db",
        "run_key" => "1a4faf1902a78648456ead5dc882f514685936698e1c60094cf17c238fe1f858",
        "variant" => "blue"
      }
    ]
  end

  test "resetting the executed experiments" do
    SubjectExperiment.run("foo")

    assert_equal 1, ActiveExperiment::Executed.experiments.length

    ActiveExperiment::Executed.reset

    assert_nil ActiveExperiment::Executed.experiments
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }
  end
end
