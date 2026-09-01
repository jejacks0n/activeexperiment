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

    # Looked up twice on purpose: the file defines the class at the top level,
    # so once the autoload has fired there's no longer an entry for it on the
    # Rollouts module to find it by.
    assert_equal "AutoloadRollout", ActiveExperiment::Rollouts.lookup(:autoload).name
  end

  test "not looking up rollouts that were never registered" do
    # Defined at the top level on purpose. Constant lookup used to fall through
    # to Object, so an unrelated StrayRollout anywhere in the application would
    # answer lookup(:stray) without ever having been registered.
    Object.const_set(:StrayRollout, Class.new(ActiveExperiment::Rollouts::BaseRollout))

    error = assert_raises(ArgumentError) do
      ActiveExperiment::Rollouts.lookup(:stray)
    end

    assert_equal "No rollout registered for :stray", error.message
  ensure
    Object.send(:remove_const, :StrayRollout)
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
