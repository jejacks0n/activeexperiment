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

  test "registering a rollout by name, without loading it" do
    ActiveExperiment::Rollouts.register(:lazy, "LazyRollout")

    assert_raises(ArgumentError) { ActiveExperiment::Rollouts.lookup(:lazy) }

    Object.const_set(:LazyRollout, Class.new(ActiveExperiment::Rollouts::BaseRollout))

    assert_equal LazyRollout, ActiveExperiment::Rollouts.lookup(:lazy)
  ensure
    Object.send(:remove_const, :LazyRollout) if Object.const_defined?(:LazyRollout)
  end

  test "a registered class is resolved by name, so a reloaded one is picked up" do
    Object.const_set(:SwappedRollout, Class.new(ActiveExperiment::Rollouts::BaseRollout))
    ActiveExperiment::Rollouts.register(:swapped, SwappedRollout)
    original = ActiveExperiment::Rollouts.lookup(:swapped)

    Object.send(:remove_const, :SwappedRollout)
    Object.const_set(:SwappedRollout, Class.new(ActiveExperiment::Rollouts::BaseRollout))

    assert_not_equal original, ActiveExperiment::Rollouts.lookup(:swapped)
    assert_equal SwappedRollout, ActiveExperiment::Rollouts.lookup(:swapped)
  ensure
    Object.send(:remove_const, :SwappedRollout) if Object.const_defined?(:SwappedRollout)
  end

  test "an anonymous class is held as it is" do
    rollout = Class.new(ActiveExperiment::Rollouts::BaseRollout)
    ActiveExperiment::Rollouts.register(:anon, rollout)

    assert_same rollout, ActiveExperiment::Rollouts.lookup(:anon)
  end

  test "registering the same name again replaces it" do
    first = Class.new(ActiveExperiment::Rollouts::BaseRollout)
    second = Class.new(ActiveExperiment::Rollouts::BaseRollout)

    ActiveExperiment::Rollouts.register(:replaced, first)
    ActiveExperiment::Rollouts.register(:replaced, second)

    assert_same second, ActiveExperiment::Rollouts.lookup(:replaced)
  end

  test "trying to register a rollout with an unknown type" do
    error = assert_raises(ArgumentError) do
      ActiveExperiment::Rollouts.register(:foo, :symbol)
    end

    assert_equal "Provide a rollout class, the name of one, or a Pathname to one", error.message
  end

  test "a rollout describes itself by the name it was registered as" do
    # Unlike cache stores and recorders, looking a rollout up hands back the
    # class rather than an instance.
    described = ActiveExperiment::Rollouts.lookup(:random).new(nil).describe

    assert_equal :random, described[:type]
    assert_equal({}, described[:options])
    # Most rollouts can't say how they'll distribute, and saying nothing is
    # the honest answer rather than a guess.
    assert_nil described[:distribution]
  end

  test "a rollout that was never registered describes itself by class" do
    rollout = Class.new(ActiveExperiment::Rollouts::BaseRollout) do
      def self.name = "UnregisteredRollout"
    end

    assert_equal "UnregisteredRollout", rollout.new(nil).describe[:type]
  end

  test "a rollout describes the options it was given" do
    rollout = ActiveExperiment::Rollouts.lookup(:random).new(nil, weight: 3)

    assert_equal({ weight: 3 }, rollout.describe[:options])
  end

  test "trying to look up a rollout that doesn't exist" do
    error = assert_raises(ArgumentError) do
      ActiveExperiment::Rollouts.lookup(:missing)
    end

    assert_equal "No rollout registered for :missing", error.message
  end
end
