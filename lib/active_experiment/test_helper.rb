# frozen_string_literal: true

require "active_support/core_ext/class/subclasses"
require "active_support/testing/assertions"

module ActiveExperiment
  # Provides helper methods for testing Active Experiments.
  module TestHelper
    include ActiveSupport::Testing::Assertions

    def setup
      super
      clear_executed_experiments
    end

    def teardown
      super
      clear_executed_experiments
    end

    # Returns all of the experiments that have been executed.
    def executed_experiments
      ActiveExperiment::Executed.as_array
    end

    # Clears the list of executed experiments.
    def clear_executed_experiments
      ActiveExperiment::Executed.clear_all
    end

    # Provides the ability to stub an experiment's variant assignment, by
    # changing the experiment to use the MockRollout within the scope of the
    # provided block.
    #
    #   class SubjectExperiment < ActiveExperiment::Base
    #     variant(:red) { "red" }
    #     variant(:blue) { "blue" }
    #     variant(:green) { "green" }
    #   end
    #
    # Given the above is our experiment, the variant assignment can be stubbed
    # to always assign the green variant.
    #
    #   stub_experiment(SubjectExperiment, :green) do
    #     assert_equal "green", SubjectExperiment.run
    #   end
    #
    # Or an array can be used to have green be assigned for the first run, and
    # blue for the second, green for the third, and so on.
    #
    #   stub_experiment(SubjectExperiment, :green, :blue) do
    #     assert_equal "green", SubjectExperiment.run
    #     assert_equal "blue", SubjectExperiment.run
    #     assert_equal "green", SubjectExperiment.run
    #   end
    #
    # A lambda or proc can be used to provide custom variant assignment using
    # whatever logic required.
    #
    #   resolver = lambda do |experiment|
    #     experiment.context[:id] == 42 ? :green : :blue
    #   end
    #
    #   stub_experiment(SubjectExperiment, resolver) do
    #     assert_equal "blue", SubjectExperiment.run(id: 1)
    #     assert_equal "blue", SubjectExperiment.run(id: 2)
    #     assert_equal "green", SubjectExperiment.run(id: 42)
    #   end
    #
    # Options can also be passed, for instance to simulate when an experiment
    # should be skipped.
    #
    #   stub_experiment(SubjectExperiment, skip: true) do |mock_rollout|
    #     assert_equal false, mock_rollout.skipped_for('_anything_')
    #     assert_equal :red, mock_rollout.variant_for('_anything_')
    #     assert_nil SubjectExperiment.run
    #   end
    #
    # By default the +MockRollout+ class will be used, which implements all of
    # the functionality described above -- however, any rollout class can be
    # used for the span of the provided block.
    #
    #   stub_experiment(SubjectExperiment, rollout_class: MyCustomRollout) do
    #     # ...
    #   end
    def stub_experiment(experiment_class, *variants, **options)
      original_rollout = experiment_class.rollout

      rollout_class = options.delete(:rollout_class) || MockRollout
      rollout_options = { variant: variants }.merge(options)
      experiment_class.rollout = rollout_class.new(experiment_class, **rollout_options)

      _assert_nothing_raised_or_warn("stub_experiment") do
        yield experiment_class.rollout
      end
    ensure
      experiment_class.rollout = original_rollout
    end

    # Asserts that the number of experiments run matches the given number.
    #
    #   def test_experiments
    #     assert_experiments 0
    #     MyExperiment.run
    #     assert_experiments 1
    #     MyExperiment.run
    #     assert_experiments 2
    #   end
    #
    # If a block is provided, that block should cause the specified number of
    # experiments to be run.
    #
    #   def test_experiments_again
    #     assert_experiments 1 do
    #       MyExperiment.run
    #     end
    #
    #     assert_experiments 2 do
    #       MyExperiment.run
    #       MyExperiment.run
    #     end
    #   end
    def assert_experiments(number, &block)
      executed_count = executed_experiments.size
      if block_given?
        _assert_nothing_raised_or_warn("assert_experiments", &block)
        executed_count = executed_experiments.size - executed_count
        assert_equal number, executed_count, "#{number} experiment runs expected, but found #{executed_count}"
      else
        assert_equal number, executed_count
      end
    end

    # Asserts that no experiments have been run.
    #
    #   def test_experiments
    #     assert_no_experiments
    #     MyExperiment.run
    #     assert_experiments 1
    #   end
    #
    # If a block is passed, that block should not cause any emails to be sent.
    #
    #   def test_experiments_again
    #     assert_no_experiments do
    #       # No experiments should be run from this block
    #     end
    #   end
    #
    # Note: This assertion is simply a shortcut for:
    #
    #   assert_experiments(0, &block)
    def assert_no_experiments(&block)
      assert_experiments(0, &block)
    end

    # Asserts that a specific experiment has been run, optionally matching args
    # and/or context.
    #
    #   def test_experiment
    #     MyExperiment.run(id: 1)
    #     assert_experiment_with MyExperiment, context: { id: 1 }
    #   end
    #
    #   def test_experiment_with_options
    #     MyExperiment.set(foo: :bar).run(id: 1)
    #     assert_experiment_with MyExperiment, options: { foo: "bar" }
    #   end
    #
    #   def test_experiment_with_variant
    #     MyExperiment.set(variant: :red).run(id: 1)
    #     assert_experiment_with MyExperiment, variant: :red
    #   end
    #
    # If a block is passed, that block should cause the specified experiment to
    # be run.
    #
    #   def test_experiment_in_block
    #     assert_experiment_with MyExperiment, context: { id: 1 } do
    #       MyExperiment.run(id: 1)
    #     end
    #   end
    def assert_experiment_with(experiment_class, context: nil, options: nil, variant: nil, &block)
      expected = { context: context, options: options, variant: variant }.compact
      experiments = executed_experiments
      if block_given?
        original_executed_experiments = experiments.dup
        _assert_nothing_raised_or_warn("assert_experiment_with", &block)
        experiments = executed_experiments - original_executed_experiments
      end

      match_potential = []
      match_class = []
      match_experiment = experiments.find do |experiment|
        match_potential << experiment
        if experiment.class == experiment_class
          match_class << experiment
          expected.all? do |key, value|
            experiment.public_send(key) == value
          end
        end
      end

      message = +"No matching run found for #{experiment_class.name}"
      message << " with #{expected.inspect}" if expected.any?
      if match_potential.empty?
        message << "\n\nNo experiment were run"
      elsif match_class.empty?
        message << "\n\nNo #{experiment_class.name} experiments were run, experiments run:"
        message << "\n  #{match_potential.map(&:class).join(", ")}"
      else
        message << "\n\nPotential matches:"
        message << "\n  #{match_class.join("\n  ")}"
      end

      assert(match_experiment, message)
      match_experiment
    end

    # Mock rollout class that can be used to stub out the variant assignment of
    # an experiment.
    #
    # This is used by the ActiveExperiment::TestHelper in the +stub_experiment+
    # method. It can be used directly, or through the helper when needing to
    # stub out the rollout of an experiment in a test. It can also be inherited
    # and customized.
    class MockRollout < Rollouts::BaseRollout
      def initialize(experiment_class, *args, **options, &block)
        @assigned = 0
        super
      end

      def skipped_for(ex)
        raise ArgumentError, "expecting a #{@experiment_class.name}" unless ex.is_a?(@experiment_class)

        skip = opts[:skip]

        # Accepts a callable in the :skip option.
        return skip.call(ex) if skip.respond_to?(:call)

        # Accepts a boolean in the :skip options, with a default of false.
        !!skip
      end

      def variant_for(ex)
        raise ArgumentError, "expecting a #{@experiment_class.name}" unless ex.is_a?(@experiment_class)

        # Accepts an array in the :variant option.
        variant = opts[:variant]
        variant = variant[((@assigned += 1) - 1) % variant.size] if variant.is_a?(Array) && !variant.empty?

        # Accepts a callable in the :variant option.
        return variant.call(ex) if variant.respond_to?(:call)

        # Accepts a symbol in the :variant option.
        return variant if variant.is_a?(Symbol)

        # Fall back to the default variant.
        ex.try(:default_variant)
      end

      def opts
        @rollout_options
      end
    end
  end
end
