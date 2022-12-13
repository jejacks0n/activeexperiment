# frozen_string_literal: true

require "helper"

class TestHelpersTest < ActiveSupport::TestCase
  include ActiveExperiment::TestHelper

  test "stub rollout with no overrides" do
    stub_experiment(OtherExperiment) do |rollout|
      assert_equal "control", OtherExperiment.run # default variant was assigned
      assert_instance_of MockRollout, rollout
    end
  end

  test "stub variant assignment" do
    stub_experiment(SubjectExperiment, :green) do
      assert_equal "green", SubjectExperiment.run
      assert_equal "green", SubjectExperiment.run
    end
  end

  test "stub variant assignment with multiple variants" do
    stub_experiment(SubjectExperiment, :green, :blue, :missing, nil) do
      assert_equal "green", SubjectExperiment.run
      assert_equal "blue", SubjectExperiment.run
      assert_nil SubjectExperiment.run # missing variant
      assert_nil SubjectExperiment.run # nil variant
      assert_equal "green", SubjectExperiment.run # back to the first
    end
  end

  test "stub variant assignment using options" do
    stub_experiment(SubjectExperiment, variant: :green) do
      assert_equal "green", SubjectExperiment.run
      assert_equal "green", SubjectExperiment.run
    end
  end

  test "stub variant assignment using a lambda" do
    stub_experiment(SubjectExperiment, ->(ex) { ex.context[:id] == 42 ? :green : :blue }) do
      assert_equal "blue", SubjectExperiment.run(id: 1)
      assert_equal "green", SubjectExperiment.run(id: 42)
    end
  end

  test "stub skipping an experiment" do
    stub_experiment(OtherExperiment, :red, skip: true) do |rollout|
      assert_equal "control", OtherExperiment.run
      assert_equal true, rollout.skipped_for(OtherExperiment.new) # skipped
      assert_equal :red, rollout.variant_for(OtherExperiment.new) # still assigns red
      assert_equal true, OtherExperiment.new.skipped?
    end
  end

  test "nested stubbed experiments" do
    stub_experiment(OtherExperiment, :red) do
      stub_experiment(SubjectExperiment, :blue) do
        assert_equal "blue", SubjectExperiment.run
        assert_equal "red", OtherExperiment.run
      end
    end
  end

  test "skipped experiments are counted in runs" do
    stub_experiment(SubjectExperiment, skip: true) do
      assert_experiments 0

      SubjectExperiment.run

      assert_experiments 1
    end
  end

  test "assert experiment run counts" do
    assert_no_experiments
    assert_experiments 0 # same as assert_no_experiments

    SubjectExperiment.run

    assert_experiments 1
  end

  test "assert experiment run counts (failure)" do
    error = assert_raises(Minitest::Assertion) do
      assert_experiments 1
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      Expected: 1
        Actual: 0
    MESSAGE
  end

  test "assert experiment run counts in block" do
    assert_experiments 2 do
      SubjectExperiment.run
      SubjectExperiment.run
    end
  end

  test "assert experiment run counts in block (failure)" do
    error = assert_raises(Minitest::Assertion) do
      assert_experiments(2) { SubjectExperiment.run }
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      2 experiment runs expected, but found 1.
      Expected: 2
        Actual: 1
    MESSAGE
  end

  test "assert no experiments run in block" do
    assert_no_experiments { }
  end

  test "assert no experiments run in block (failure)" do
    error = assert_raises(Minitest::Assertion) do
      assert_no_experiments { SubjectExperiment.run }
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      0 experiment runs expected, but found 1.
      Expected: 0
        Actual: 1
    MESSAGE
  end

  test "assert experiment with nothing else" do
    SubjectExperiment.run(id: 1)

    assert_experiment_with(SubjectExperiment)
  end

  test "assert experiment with nothing else (failure)" do
    error = assert_raises(Minitest::Assertion) do
      assert_experiment_with(SubjectExperiment)
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      No matching run found for TestHelpersTest::SubjectExperiment

      No experiment were run
    MESSAGE
  end

  test "assert experiment with context" do
    SubjectExperiment.run(id: 1)
    SubjectExperiment.run(id: 1)
    SubjectExperiment.run(id: 2)
    assert_experiment_with(SubjectExperiment, context: { id: 1 })
  end

  test "assert experiment with context (failure)" do
    SubjectExperiment.run(id: 1)
    SubjectExperiment.run(id: 2)
    OtherExperiment.run(id: 3)
    error = assert_raises(Minitest::Assertion) do
      assert_experiment_with(SubjectExperiment, context: { id: 3 })
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      No matching run found for TestHelpersTest::SubjectExperiment with {:context=>{:id=>3}}

      Potential matches:
        #<TestHelpersTest::SubjectExperiment:0x3e8 @variant=:red @skip=false @run_key=9b1551c89e75d943... @context={:id=>1}, @options={}>
        #<TestHelpersTest::SubjectExperiment:0x3e8 @variant=:red @skip=false @run_key=4a2afe7b0b474d29... @context={:id=>2}, @options={}>
    MESSAGE
  end

  test "assert experiment with options and variant" do
    SubjectExperiment.set(variant: :blue, foo: "bar").run

    assert_experiment_with(SubjectExperiment, options: { foo: "bar" }, variant: :blue)
  end

  test "assert experiment with options and variant (failure)" do
    SubjectExperiment.set(variant: :blue, foo: "bar").run
    error = assert_raises(Minitest::Assertion) do
      assert_experiment_with(SubjectExperiment, options: { foo: "foo" })
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      No matching run found for TestHelpersTest::SubjectExperiment with {:options=>{:foo=>"foo"}}

      Potential matches:
        #<TestHelpersTest::SubjectExperiment:0x3e8 @variant=:blue @skip=false @run_key=d2bcee5abbe0b418... @context={}, @options={:foo=>"bar"}>
    MESSAGE
  end

  test "assert experiment with block" do
    assert_experiment_with(SubjectExperiment, variant: :blue, context: { id: 1 }, options: { foo: "bar" }) do
      SubjectExperiment.set(variant: :blue, foo: "bar").run(id: 1)
    end
  end

  test "assert experiment with block (failure)" do
    error = assert_raises(Minitest::Assertion) do
      assert_experiment_with(SubjectExperiment, variant: :blue, context: { id: 1 }, options: { foo: "bar" }) do
        SubjectExperiment.set(variant: :blue, foo: "bar").run(id: 2)
      end
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      No matching run found for TestHelpersTest::SubjectExperiment with {:context=>{:id=>1}, :options=>{:foo=>\"bar\"}, :variant=>:blue}

      Potential matches:
        #<TestHelpersTest::SubjectExperiment:0x3e8 @variant=:blue @skip=false @run_key=4a2afe7b0b474d29... @context={:id=>2}, @options={:foo=>\"bar\"}>
    MESSAGE
  end

  test "assert experiment with when no experiment classes run (failure)" do
    OtherExperiment.run
    error = assert_raises(Minitest::Assertion) do
      assert_experiment_with(SubjectExperiment)
    end

    assert_equal(<<~MESSAGE.strip, error.message)
      No matching run found for TestHelpersTest::SubjectExperiment

      No TestHelpersTest::SubjectExperiment experiments were run, experiments run:
        TestHelpersTest::OtherExperiment
    MESSAGE
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }
    variant(:green) { "green" }
  end

  class OtherExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    control { "control" }
  end

  silence_warnings do # Silence warnings about object_id
    class SubjectExperiment
      def object_id
        1000
      end
    end
  end
end
