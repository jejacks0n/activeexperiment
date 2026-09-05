# frozen_string_literal: true

require "helper"

class LifecycleTest < ActiveSupport::TestCase
  def setup
    SubjectExperiment.recorder = MemoryRecorder.new
    SubjectExperiment.refresh_lifecycle!
    SubjectExperiment.cache_store.clear
  end

  def teardown
    SubjectExperiment.recorder = ActiveExperiment::Base.recorder
    SubjectExperiment.refresh_lifecycle!
  end

  test "an experiment starts out running" do
    assert_equal :running, SubjectExperiment.state
    assert_equal false, SubjectExperiment.concluded?
    assert_equal false, SubjectExperiment.archived?
    assert_nil SubjectExperiment.winning_variant
  end

  test "an experiment with no recorder is running" do
    SubjectExperiment.recorder = ActiveExperiment::Recorders::NullRecorder.new
    SubjectExperiment.refresh_lifecycle!

    assert_equal :running, SubjectExperiment.state
  end

  test "concluding on a variant" do
    SubjectExperiment.conclude!(variant: :blue, notes: "blue won")

    assert_equal :concluded, SubjectExperiment.state
    assert_equal true, SubjectExperiment.concluded?
    assert_equal :blue, SubjectExperiment.winning_variant
  end

  test "a concluded experiment assigns the winner to everyone" do
    SubjectExperiment.conclude!(variant: :blue)

    5.times do |i|
      experiment = SubjectExperiment.new(id: i)

      assert_equal "blue", experiment.run
      assert_equal :concluded, experiment.variant_source
    end
  end

  test "a concluded experiment doesn't ask its rollout anything" do
    SubjectExperiment.conclude!(variant: :blue)

    # The rollout raising is the assertion here. An experiment usually gets
    # concluded when nobody wants it consulted any more, and the rollout it was
    # running under might be gone by then.
    stubbed = Class.new(ActiveExperiment::Rollouts::BaseRollout) {
      def skipped_for(*) = raise("rollout was asked")
      def variant_for(*) = raise("rollout was asked")
    }.new(SubjectExperiment)

    original, SubjectExperiment.rollout = SubjectExperiment.rollout, stubbed

    assert_equal "blue", SubjectExperiment.run(id: 1)
  ensure
    SubjectExperiment.rollout = original
  end

  test "a concluded experiment doesn't write to the cache" do
    SubjectExperiment.conclude!(variant: :blue)
    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_nil SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  test "a variant set before the run still wins over the conclusion" do
    SubjectExperiment.conclude!(variant: :blue)

    experiment = SubjectExperiment.new(id: 1).set(variant: :red)

    assert_equal "red", experiment.run
    assert_equal :preset, experiment.variant_source
  end

  test "concluding on a variant that isn't registered" do
    error = assert_raises(ArgumentError) { SubjectExperiment.conclude!(variant: :green) }

    assert_match(/Unknown :green variant/, error.message)
  end

  test "a winner that's no longer a registered variant is ignored" do
    SubjectExperiment.conclude!(variant: :blue)
    SubjectExperiment.recorder.update_experiment(
      SubjectExperiment.experiment_name, winning_variant: "removed"
    )
    SubjectExperiment.refresh_lifecycle!

    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_equal :rollout, experiment.variant_source
    assert_includes SubjectExperiment.variants.keys, experiment.variant
  end

  test "reopening a concluded experiment" do
    SubjectExperiment.conclude!(variant: :blue)
    SubjectExperiment.reopen!

    assert_equal :running, SubjectExperiment.state
    assert_nil SubjectExperiment.winning_variant

    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_equal :rollout, experiment.variant_source
  end

  test "archiving doesn't change what the experiment assigns" do
    SubjectExperiment.archive!(notes: "superseded")

    assert_equal :archived, SubjectExperiment.state
    assert_equal true, SubjectExperiment.archived?

    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_equal :rollout, experiment.variant_source
  end

  test "an unknown variant is rejected before the recorder is consulted" do
    error = assert_raises(ArgumentError) { SubjectExperiment.conclude!(variant: :green) }

    assert_match(/Unknown :green variant/, error.message)
  end

  test "archiving without a recorder to write it to" do
    SubjectExperiment.recorder = ActiveExperiment::Recorders::NullRecorder.new

    error = assert_raises(ActiveExperiment::ExecutionError) { SubjectExperiment.archive! }

    assert_match(/no recorder to write its state to/, error.message)
  end

  test "concluding without a recorder to write it to" do
    SubjectExperiment.recorder = ActiveExperiment::Recorders::NullRecorder.new

    error = assert_raises(ActiveExperiment::ExecutionError) do
      SubjectExperiment.conclude!(variant: :blue)
    end

    assert_match(/no recorder to write its state to/, error.message)
  end

  test "state is held rather than read on every run" do
    SubjectExperiment.conclude!(variant: :blue)
    SubjectExperiment.run(id: 0)
    reads = SubjectExperiment.recorder.reads

    10.times { |i| SubjectExperiment.run(id: i) }

    assert_equal reads, SubjectExperiment.recorder.reads
  end

  test "state is read again once the interval has passed" do
    SubjectExperiment.lifecycle_refresh_interval = 0
    SubjectExperiment.conclude!(variant: :blue)
    SubjectExperiment.run(id: 0)
    reads = SubjectExperiment.recorder.reads

    3.times { |i| SubjectExperiment.run(id: i) }

    assert_operator SubjectExperiment.recorder.reads, :>, reads
  ensure
    SubjectExperiment.lifecycle_refresh_interval = 60
  end

  test "an experiment that isn't recorded never asks the recorder" do
    recorder = ActiveExperiment::Recorders::NullRecorder.new
    SubjectExperiment.recorder = recorder
    SubjectExperiment.refresh_lifecycle!

    # The null recorder answers +nil+ to +experiment+ anyway, so this is
    # checking that recording? gates it before the lookup happens.
    def recorder.experiment(*) = raise("asked the null recorder")

    assert_equal "red", SubjectExperiment.new(id: 1).run
  end

  # Keeps lifecycle rows in a hash, and counts reads so the caching can be
  # asserted on without needing a database.
  class MemoryRecorder < ActiveExperiment::Recorders::BaseRecorder
    attr_reader :reads

    def initialize(**options)
      super
      @rows = {}
      @reads = 0
    end

    def experiment(experiment_name)
      @reads += 1
      @rows[experiment_name.to_s]
    end

    def update_experiment(experiment_name, **attributes)
      row = @rows[experiment_name.to_s] ||= { name: experiment_name.to_s, state: :running }
      attributes.each do |key, value|
        row[key] = case key
                   when :state then value.to_sym
                   when :winning_variant then value.presence&.to_sym
                   else value
        end
      end
      row
    end

    private
      def write(registry, runs, overlaps)
      end
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }

    use_rollout :percent, rules: { red: 100, blue: 0 }
    use_cache_store :memory_store
    use_default_variant :red
  end
end
