# frozen_string_literal: true

require "helper"

class RolloutsTest < ActiveSupport::TestCase
  test "registering a rollout by class" do
    FooRollout = Class.new(ActiveExperiment::Rollouts::BaseRollout)
    ActiveExperiment::Rollouts.register(:foo, FooRollout)

    assert_equal FooRollout, ActiveExperiment::Rollouts.lookup(:foo)
  end

  test "registering a rollout by Pathname" do
    ActiveExperiment::Rollouts.register(:autoload, Pathname.new("support/autoload_rollout"))

    assert_equal "AutoloadRollout", ActiveExperiment::Rollouts.lookup(:autoload).name
  end

  test "registering a rollout with the class method" do
    BarRollout = Class.new(ActiveExperiment::Rollouts::BaseRollout) do
      register_as :bar
    end

    assert_equal BarRollout, ActiveExperiment::Rollouts.lookup(:bar)
  end

  test "trying to register a rollout with an unknown type" do
    error = assert_raises(ArgumentError) do
      ActiveExperiment::Rollouts.register(:foo, :symbol)
    end

    assert_equal "Provide a class to register, or string for autoloading", error.message
  end

  test "trying to look up a rollout that doesn't exist" do
    error = assert_raises(ArgumentError) do
      ActiveExperiment::Rollouts.lookup(:missing)
    end

    assert_equal "No rollout registered for :missing", error.message
  end
end
