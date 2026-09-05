# frozen_string_literal: true

require "helper"

# Answering "what would this experiment assign, and why?" without the act of
# asking changing the answer.
class ExplainTest < ActiveSupport::TestCase
  include ActiveExperiment::TestHelper

  def setup
    super
    SubjectExperiment.cache_store.clear
  end

  test "explaining a resolution" do
    explanation = SubjectExperiment.explain(id: 1)

    assert_equal "explain_test/subject_experiment", explanation[:experiment]
    assert_equal :red, explanation[:variant]
    assert_equal :rollout, explanation[:variant_source]
    assert_equal [:red, :blue], explanation[:variants]
    assert_equal :red, explanation[:default_variant]
    assert_equal false, explanation[:skipped]
    assert_equal :running, explanation[:state]
    assert_equal SubjectExperiment.new(id: 1).cache_key, explanation[:cache_key]
  end

  test "explaining doesn't run the variant" do
    # The variants raise, so reaching one is the failure.
    assert_nothing_raised { ExplosiveExperiment.explain(id: 1) }
  end

  test "explaining doesn't cache the variant it resolved" do
    experiment = SubjectExperiment.new(id: 1)
    SubjectExperiment.explain(id: 1)

    assert_nil SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  test "explaining reads a variant that is cached" do
    experiment = SubjectExperiment.new(id: 1)
    SubjectExperiment.cache_store.write(experiment.cache_key, :blue)

    explanation = SubjectExperiment.explain(id: 1)

    assert_equal :blue, explanation[:variant]
    assert_equal :cached, explanation[:variant_source]
  end

  test "explaining doesn't record the experiment as executed" do
    SubjectExperiment.explain(id: 1)

    assert_no_experiments
  end

  test "explaining reports a segment rule firing" do
    explanation = SegmentedExperiment.explain(id: 1)

    assert_equal :blue, explanation[:variant]
    assert_equal :segment, explanation[:variant_source]
  end

  test "explaining reports a skip" do
    explanation = SkippedExperiment.explain(id: 1)

    assert_equal :skipped, explanation[:variant_source]
    assert_equal true, explanation[:skipped]
  end

  test "explaining a concluded experiment reports the winner" do
    recorder = LifecycleRecorder.new
    SubjectExperiment.recorder = recorder
    SubjectExperiment.conclude!(variant: :blue)

    explanation = SubjectExperiment.explain(id: 1)

    assert_equal :blue, explanation[:variant]
    assert_equal :concluded, explanation[:variant_source]
    assert_equal :concluded, explanation[:state]
  ensure
    SubjectExperiment.recorder = ActiveExperiment::Base.recorder
    SubjectExperiment.refresh_lifecycle!
  end

  test "explaining doesn't record a conclusion or read one twice" do
    recorder = LifecycleRecorder.new
    SubjectExperiment.recorder = recorder
    SubjectExperiment.conclude!(variant: :blue)
    SubjectExperiment.explain(id: 1)
    writes = recorder.writes

    SubjectExperiment.explain(id: 2)

    assert_equal writes, recorder.writes
  ensure
    SubjectExperiment.recorder = ActiveExperiment::Base.recorder
    SubjectExperiment.refresh_lifecycle!
  end

  test "explaining an experiment with no variants" do
    error = assert_raises(ActiveExperiment::ExecutionError) do
      VariantlessExperiment.new(id: 1).explain
    end

    assert_equal "No variants registered", error.message
  end

  test "an explained experiment can still be run afterwards" do
    experiment = SubjectExperiment.new(id: 1)
    experiment.explain

    assert_equal "red", experiment.run
    assert_equal :red, SubjectExperiment.cache_store.read(experiment.cache_key)
  end

  # Holds lifecycle state in memory, so concluding can be exercised without a
  # database behind it.
  class LifecycleRecorder < ActiveExperiment::Recorders::BaseRecorder
    attr_reader :writes

    def initialize(**options)
      super
      @rows = {}
      @writes = 0
    end

    def experiments
      @rows.values
    end

    def experiment(experiment_name)
      @rows[experiment_name.to_s]
    end

    def update_experiment(experiment_name, **attributes)
      @writes += 1
      # Rows carry their own name, the way a real recorder's do, since that's
      # what the state cache keys them by.
      row = @rows[experiment_name.to_s] ||= { name: experiment_name.to_s }
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

  class SegmentedExperiment < SubjectExperiment
    segment(into: :blue) { true }
  end

  class SkippedExperiment < SubjectExperiment
    use_rollout :inactive
  end

  class VariantlessExperiment < ActiveExperiment::Base
  end

  class ExplosiveExperiment < ActiveExperiment::Base
    variant(:red) { raise "the variant was run" }
    variant(:blue) { raise "the variant was run" }

    use_default_variant :red
  end
end
