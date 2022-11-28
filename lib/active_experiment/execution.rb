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
  #                run
  #                 |
  #            _ skipped? _
  #           |            |
  #          yes           no
  #           |            |
  #    default_variant     |
  #                        |
  #               _ cached_variant? _
  #              |                   |
  #              no                 yes
  #              |                   |
  #       _ segmented? _      (cached value)
  #      |              |
  #     yes             no
  #      |              |
  #      |  ___ rollout.variant_for _
  #      | |            |            |
  #    (cache)       (cache)      (cache)
  #   variant_a     variant_b    variant_c
  #
  module Execution
    extend ActiveSupport::Concern

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
    # Raises an ActiveExperiment::ExecutionError if there are no variants
    # registered, or if the experiment is already running, in the case of
    # accidentally calling run again within a run or variant block.
    def run(&block)
      return @results if defined?(@results)
      raise ExecutionError, "No variants registered" if variant_names.empty?

      @results = nil
      instrument(:run) do
        run_callbacks(:run) do
          block.call(self) if block
          @variant = resolve_variant
          @results = resolve_results
        end
      end

      @results
    ensure
      Executed.experiments << self
    end

    private
      def resolve_variant
        return variant || default_variant if skipped?

        resolved = cached_variant(variant) do
          run_callbacks(:segment)
          variant || rollout.variant_for(self)
        end

        variant || resolved || default_variant
      end

      def resolve_results
        resolved = nil
        run_callbacks(variants[variant]) do
          resolved = variant_step_chains[variant]&.call
        end

        resolved || @results
      end
  end
end
