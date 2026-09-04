# frozen_string_literal: true

module ActiveExperiment
  # == Execution Module
  #
  # This module provides most of the logic for running experiments. Running an
  # experiment can be performed in a few ways, some of which are provided as
  # convenience.
  #
  # 1. Calling +run+ on the class, passing the context and a block:
  #
  #   MyExperiment.run(context) do |experiment|
  #     experiment.on(:treatment) { "treatment" }
  #   end
  #
  # 2. Instantiating the experiment with the context, and calling +run+:
  #
  #   MyExperiment.new(context).run do |experiment|
  #     experiment.on(:treatment) { "treatment" }
  #   end
  #
  # 3. Using the +ConfiguredExperiment+ API to +set+ and then +run+:
  #
  #   MyExperiment.set(variant: :treatment).run(id: 1) do |experiment|
  #     experiment.on(:treatment) { "treatment" }
  #   end
  #
  # In all cases, a block can be provided to the +run+ method. The block will
  # be called with the experiment, which allows overriding the variant
  # behaviors using the scope of where the experiment is being run.
  #
  # When the experiment is run, the variant will be determined and the variant
  # steps will be executed. The result of the variant execution will be
  # returned unless the experiment is aborted in a +before_run+ or
  # +before_variant+ callback.
  #
  # In general, the following decision tree diagram helps illustrate the order
  # that things will be executed in running an experiment, utilizing caching
  # when possible:
  #                             run
  #                              |
  #                         _ skipped? _
  #                        |            |
  #                        no          yes
  #                        |            |
  #                        |    assigned/default_variant
  #                        |
  #               _ cached_variant? _
  #              |                   |
  #              no                 yes
  #              |                   |
  #       _ segmented? _      (cached value)
  #      |              |
  #     yes             no
  #      |              |
  #      |  ___ rollout.variant_for __
  #      | |            |             |
  #    (cache)       (cache)       (cache)
  #   variant_a     variant_b     variant_c
  #
  module Execution
    extend ActiveSupport::Concern

    NESTING_KEY = :active_experiment_running
    private_constant :NESTING_KEY

    # These methods will be included into any Active Experiment object and
    # expose the class level run method, and the ability to get a configured
    # experiment instance using the set method.
    module ClassMethods
      # Instantiates and runs an experiment with the provided context and
      # block. This is a convenience method.
      #
      # An example of using this method to run an experiment:
      #
      #   MyExperiment.run(id: 1) do |experiment|
      #     experiment.on(:treatment) { "red" }
      #   end
      def run(*args, **kws, &block)
        new(*args, **kws).run(&block)
      end

      # Creates a configured experiment with the provided options. Configured
      # experiments expose a few helpful methods for running and caching
      # experiment details.
      #
      # The following options can be provided to configure an experiment:
      #
      # * +:variant+ - The variant to assign.
      #
      # An example of using this method to set a variant and run an experiment:
      #
      #   MyExperiment.set(variant: :red).run(id: 1) do |experiment|
      #     experiment.on(:red) { "red" }
      #   end
      def set(**options)
        ConfiguredExperiment.new(self, **options)
      end
    end

    # Runs the experiment. Calling +run+ returns the value of the assigned
    # variant block or method.
    #
    # When running an experiment, a block can be provided and it will be called
    # with the experiment, which provides the ability to override variant
    # behaviors when running the experiment.
    #
    #   MyExperiment.new(id: 1).run do |experiment|
    #     experiment.on(:treatment) { "treatment" }
    #   end
    #
    # Running an experiment that's already been run returns the result of the
    # first run instead of running it again, and the block isn't called. That
    # makes +run+ safe to call more than once -- repeatedly in a view, or by
    # accident from within a run or variant block -- without resolving a second
    # variant or recording a second execution.
    #
    # Raises an ActiveExperiment::ExecutionError if there are no variants
    # registered.
    def run(&block)
      return @results if defined?(@results)
      raise ExecutionError, "No variants registered" if variant_names.empty?

      @results = nil

      # Keep track of the current running experiment in case any are nested.
      @nested_within = ActiveSupport::IsolatedExecutionState[NESTING_KEY]

      begin
        ActiveSupport::IsolatedExecutionState[NESTING_KEY] = self

        # Scoped to the run rather than assigned outright the way Active Job
        # assigns its job: a job is the whole unit of work, but an experiment
        # runs inside one, often more than once. Setting it with a block puts
        # back whatever was there before, so queries after the run aren't still
        # attributed to it, and a nested experiment hands the outer one back.
        ActiveSupport::ExecutionContext.set(experiment: self) do
          instrument(:start_experiment)
          instrument(:process_run) do
            run_callbacks(:run, :process_run_callbacks) do
              call_run_block(&block) if block.present?
              @variant = resolve_variant
              @results = resolve_results
            end
          end
        end

        @results
      ensure
        ActiveSupport::IsolatedExecutionState[NESTING_KEY] = @nested_within
        Executed << self
      end
    end

    private
      # Resolves the variant, and understands how it was resolved.
      def resolve_variant
        if skipped?
          @variant_source = variant ? :preset : :skipped
          return variant || default_variant
        end

        @variant_source = variant ? :preset : :cached

        resolved = cached_variant(variant) do
          @variant_source = :rollout
          run_callbacks(:segment, :process_segment_callbacks)
          if variant
            @variant_source = :segment
            variant
          else
            rollout.variant_for(self)
          end
        end

        if variant
          variant
        elsif resolved
          resolved
        else
          @variant_source = :default
          default_variant
        end
      end

      def resolve_results
        resolved = nil
        run_callbacks(variants[variant], :process_variant_callbacks) do
          resolved = variant_step_chains[variant]&.call
        end

        resolved || @results
      end

      def call_run_block(&block)
        block.call(self)
      end
  end
end
