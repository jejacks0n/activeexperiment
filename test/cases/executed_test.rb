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
    # Serializing has to happen inside the stub too: run ids are generated when
    # they're first asked for, and a run doesn't ask for one on its own.
    SecureRandom.stub(:uuid, "1fbde0db") do
      SubjectExperiment.run("foo") # overridden in our json object!
      SubjectExperiment.set(variant: :blue).run("bar")

      expected = {
        "executed_test/subject_experiment" => {
          "experiment" => "executed_test/subject_experiment",
          "run_id" => "1fbde0db",
          "run_key" => "32977ecb981cc727be359d0a688180cf822b1f6ba15680db6cad82d349e250a2",
          "variant" => "blue",
          "variant_source" => "preset",
          "skipped" => false,
        }
      }

      assert_equal expected, JSON.parse(ActiveExperiment::Executed.to_json)
    end
  end

  test "getting the experiments run as a json array" do
    SecureRandom.stub(:uuid, "1fbde0db") do
      SubjectExperiment.run("foo")
      SubjectExperiment.set(variant: :blue).run("bar")

      expected = [
        {
          "experiment" => "executed_test/subject_experiment",
          "run_id" => "1fbde0db",
          "run_key" => "cf50425bc514577c720ff7ee9fc21f4b4162699e7f4ba5119abb5381efc4588b",
          "variant" => "red",
          "variant_source" => "rollout",
          "skipped" => false,
        },
        {
          "experiment" => "executed_test/subject_experiment",
          "run_id" => "1fbde0db",
          "run_key" => "32977ecb981cc727be359d0a688180cf822b1f6ba15680db6cad82d349e250a2",
          "variant" => "blue",
          "variant_source" => "preset",
          "skipped" => false,
        }
      ]

      assert_equal expected, JSON.parse(ActiveExperiment::Executed.to_json_array)
    end
  end

  test "running an experiment more than once records it once" do
    experiment = SubjectExperiment.new("foo")

    3.times { experiment.run }

    assert_equal 1, ActiveExperiment::Executed.as_array.length
  end

  test "running an experiment from within its own run block records it once" do
    SubjectExperiment.run("foo") { |experiment| experiment.run }

    assert_equal 1, ActiveExperiment::Executed.as_array.length
  end

  test "an experiment that raises while running is still recorded" do
    assert_raises(RuntimeError) { RaisingExperiment.run("foo") }

    assert_equal 1, ActiveExperiment::Executed.as_array.length
  end

  test "an experiment that can't run isn't recorded" do
    assert_raises(ActiveExperiment::ExecutionError) { NoVariantsExperiment.run("foo") }

    assert_empty ActiveExperiment::Executed.as_array
  end

  test "serializing to json in a process that's loaded nothing else" do
    # The suite has stdlib json loaded through other gems, and it defines its
    # own Hash#to_json, so a missing require doesn't show here. A process
    # holding nothing but the library is the only place it does.
    script = <<~RUBY
      require "active_experiment"
      ActiveExperiment.logger = nil

      experiment = Class.new(ActiveExperiment::Base) do
        def self.name = "BareExperiment"

        variant(:red) { "red" }
      end
      experiment.run(id: 1)

      print ActiveExperiment::Executed.to_json
    RUBY

    output = IO.popen(
      [RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script],
      err: [:child, :out],
      &:read
    )

    assert_predicate $?, :success?, output
    assert_includes output, "bare_experiment"
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

  class RaisingExperiment < ActiveExperiment::Base
    variant(:red) { raise "from the variant" }
  end

  class NoVariantsExperiment < ActiveExperiment::Base
  end
end
