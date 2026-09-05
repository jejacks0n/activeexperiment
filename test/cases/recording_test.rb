# frozen_string_literal: true

require "helper"

class RecordingTest < ActiveSupport::TestCase
  include ActiveExperiment::TestHelper

  def setup
    super
    @recorder = CapturingRecorder.new(flush_interval: 1_000_000, flush_threshold: 1_000_000)
    SubjectExperiment.recorder = @recorder
  end

  def teardown
    SubjectExperiment.recorder = ActiveExperiment::Base.recorder
    super
  end

  test "the default recorder is the null recorder" do
    DefaultRecorderExperiment = Class.new(ActiveExperiment::Base)

    assert_instance_of ActiveExperiment::Recorders::NullRecorder,
      DefaultRecorderExperiment.recorder
    assert_equal false, DefaultRecorderExperiment.recorder.recording?
  end

  test "recorders are inherited, unlike rollouts" do
    subclass = Class.new(SubjectExperiment)

    assert_same @recorder, subclass.recorder
  end

  test "assigning the name of a recorder to the attribute that holds one" do
    error = assert_raises(ArgumentError) { SubjectExperiment.recorder = :active_record }

    assert_match(/default_recorder = :active_record/, error.message)
    assert_match(/use_recorder :active_record/, error.message)
  end

  test "looking a recorder up with or without the name suffix" do
    # Cache stores accept both spellings depending on where the store came
    # from, so recorders accept both rather than picking one.
    assert_instance_of ActiveExperiment::Recorders::NullRecorder,
      ActiveExperiment::Recorders.lookup(:null_recorder)
    assert_instance_of ActiveExperiment::Recorders::NullRecorder,
      ActiveExperiment::Recorders.lookup(:null)
  end

  test "looking up a recorder that isn't registered" do
    error = assert_raises(ArgumentError) { ActiveExperiment::Recorders.lookup(:nope) }

    assert_match(/No recorder found for :nope/, error.message)
  end

  test "counting a run" do
    SubjectExperiment.run(id: 1)
    @recorder.flush!

    key, counts = @recorder.runs.first

    assert_equal ["recording_test/subject_experiment", "blue", Date.current], key
    assert_equal 1, counts[:runs]
    assert_equal 1, counts[:from_rollout]
    assert_equal 0, counts[:skipped]
    assert_equal 0, counts[:errored]
  end

  test "counting runs of the same variant together" do
    3.times { |i| SubjectExperiment.run(id: i) }
    @recorder.flush!

    assert_equal 3, @recorder.runs.values.sum { |counts| counts[:runs] }
  end

  test "counting a skipped run" do
    SkippedExperiment.recorder = @recorder
    SkippedExperiment.run(id: 1)
    @recorder.flush!

    counts = @recorder.runs.values.first

    assert_equal 1, counts[:runs]
    assert_equal 1, counts[:skipped]
    assert_equal 1, counts[:from_skipped]
  ensure
    SkippedExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "counting a run that raised" do
    RaisingExperiment.recorder = @recorder

    assert_raises(RuntimeError) { RaisingExperiment.run(id: 1) }
    @recorder.flush!

    counts = @recorder.runs.values.first

    assert_equal 1, counts[:runs]
    assert_equal 1, counts[:errored]
  ensure
    RaisingExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "describing the experiment alongside its counts" do
    SubjectExperiment.run(id: 1)
    @recorder.flush!

    described = @recorder.registry.fetch("recording_test/subject_experiment")

    assert_equal "RecordingTest::SubjectExperiment", described[:class_name]
    assert_equal [:red, :blue], described[:variant_names]
    assert_equal :red, described[:default_variant]
    assert_equal "ActiveSupport::Cache::NullStore", described[:cache_store]
    assert_equal({ red: 25.0, blue: 75.0 }, described[:rollout][:distribution])
  end

  test "describing an experiment whose rollout can't describe itself" do
    # An experiment can use anything responding to `skipped_for` and
    # `variant_for` as its rollout, including itself, so a rollout always has
    # to be allowed to say nothing about how it distributes.
    UndescribableExperiment.recorder = @recorder
    UndescribableExperiment.run(id: 1)
    @recorder.flush!

    described = @recorder.registry.fetch("recording_test/undescribable_experiment")

    assert_nil described[:rollout]
  ensure
    UndescribableExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "flushing when the threshold is reached" do
    recorder = CapturingRecorder.new(flush_interval: 1_000_000, flush_threshold: 2)
    SubjectExperiment.recorder = recorder

    SubjectExperiment.run(id: 1)
    assert_equal 0, recorder.writes.length

    SubjectExperiment.run(id: 2)
    assert_equal 1, recorder.writes.length
  end

  test "flushing empties the buffer" do
    SubjectExperiment.run(id: 1)

    assert_equal true, @recorder.flush!
    assert_equal false, @recorder.flush!
  end

  test "the null recorder records nothing" do
    recorder = ActiveExperiment::Recorders::NullRecorder.new
    SubjectExperiment.recorder = recorder

    SubjectExperiment.run(id: 1)

    assert_equal false, recorder.flush!
    assert_equal({ experiments: 0, rollups: 0, overlaps: 0 },
      recorder.delete_experiment("recording_test/subject_experiment"))
    assert_empty recorder.experiments
    assert_empty recorder.rollups("recording_test/subject_experiment")
    assert_empty recorder.overlaps("recording_test/subject_experiment")
    assert_nil recorder.experiment("recording_test/subject_experiment")
  end

  test "counting the experiments that were run together" do
    OtherExperiment.recorder = @recorder

    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    assert_equal({
      ["recording_test/other_experiment", "on", "recording_test/subject_experiment", "red"] =>
        { count: 1, nested_count: 0 }
    }, @recorder.overlaps.transform_values(&:to_h))
  ensure
    OtherExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "a single experiment isn't an overlap" do
    SubjectExperiment.run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    assert_empty @recorder.overlaps
  end

  test "an experiment run twice isn't an overlap with itself" do
    SubjectExperiment.run(id: 1)
    SubjectExperiment.run(id: 2)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    assert_empty @recorder.overlaps
  end

  test "the same pair of variants counts once however many runs it took" do
    OtherExperiment.recorder = @recorder

    3.times { |i| SubjectExperiment.set(variant: :red).run(id: i) }
    OtherExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    assert_equal 1, @recorder.overlaps.values.sum { |counts| counts[:count] }
  ensure
    OtherExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "pairs are stored the same way whichever order they ran in" do
    OtherExperiment.recorder = @recorder

    OtherExperiment.set(variant: :on).run(id: 1)
    SubjectExperiment.set(variant: :red).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    assert_equal [["recording_test/other_experiment", "on", "recording_test/subject_experiment", "red"]],
      @recorder.overlaps.keys
  ensure
    OtherExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "an experiment run inside another is flagged as nested" do
    NestingExperiment.recorder = @recorder

    NestingExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    counts = @recorder.overlaps.values.first

    assert_equal 1, counts[:count]
    assert_equal 1, counts[:nested_count]
  ensure
    NestingExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "nesting is reported on the experiment that was nested" do
    NestingExperiment.recorder = @recorder
    NestingExperiment.set(variant: :on).run(id: 1)

    nested, outer = ActiveExperiment::Executed.as_array

    assert_same outer, nested.nested_within
    assert_nil outer.nested_within
  ensure
    NestingExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "an experiment that isn't recorded doesn't hold up the ones that are" do
    OtherExperiment.recorder = ActiveExperiment::Recorders::NullRecorder.new

    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    # The pair is still counted, because overlap is a property of the set
    # rather than of either experiment in it.
    assert_equal 1, @recorder.overlaps.values.sum { |counts| counts[:count] }
  ensure
    OtherExperiment.recorder = ActiveExperiment::Base.recorder
  end

  # Collects what would have been written, so the buffering and pairing can be
  # tested without a datastore under it.
  class CapturingRecorder < ActiveExperiment::Recorders::BaseRecorder
    attr_reader :writes

    def initialize(**options)
      super
      @writes = []
    end

    def registry
      @writes.last&.first || {}
    end

    def runs
      @writes.last&.second || {}
    end

    def overlaps
      @writes.flat_map { |(_, _, overlaps)| overlaps.to_a }.to_h
    end

    private
      def write(registry, runs, overlaps)
        @writes << [registry, runs, overlaps]
      end
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }

    use_rollout :percent, rules: { red: 25, blue: 75 }
    use_default_variant :red
  end

  class OtherExperiment < ActiveExperiment::Base
    variant(:on) { "on" }
    variant(:off) { "off" }
  end

  class NestingExperiment < ActiveExperiment::Base
    variant(:on) { OtherExperiment.set(variant: :on).run(id: 1) }
    variant(:off) { "off" }
  end

  class SkippedExperiment < SubjectExperiment
    use_rollout :inactive
  end

  class RaisingExperiment < ActiveExperiment::Base
    variant(:red) { raise "nope" }

    use_default_variant :red
  end

  class UndescribableExperiment < ActiveExperiment::Base
    variant(:red) { "red" }

    def self.skipped_for(*) = false
    def self.variant_for(*) = :red

    use_rollout self
    use_default_variant :red
  end
end
