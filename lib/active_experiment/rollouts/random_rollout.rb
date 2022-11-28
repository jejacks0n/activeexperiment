# frozen_string_literal: true

module ActiveExperiment
  module Rollouts
    # == Active Experiment Random Rollout
    #
    # The random rollout will assign a random variant every time the experiment
    # is run.
    #
    # The behavior with random assignment is dependent on if caching is being
    # used or not. This can be specified by providing the +cache:+ option to
    # the rollout.
    #
    # When caching, the same variant will be assigned given the same experiment
    # context, and will also slowly increases the number of contexts included
    # in the experiment since with each run there's a chance that a context can
    # be promoted out of the control group.
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     control { }
    #     variant(:red) { }
    #     variant(:blue) { }
    #
    #     # Randomize between all variants, every run.
    #     rollout :random
    #
    #     # Random, but once assigned, cache the assignment.
    #     rollout :random, cache: true
    #   end
    #
    # To use as the default, configure it to +:random+.
    #
    #   ActiveExperiment::Base.default_rollout = :random
    #   Rails.application.config.active_experiment.default_rollout = :random
    class RandomRollout < BaseRollout
      def variant_for(experiment) # :nodoc:
        if @rollout_options[:cache]
          experiment.variant_names.sample
        else
          experiment.set(variant: experiment.variant_names.sample)
          nil # returning nil bypasses caching
        end
      end
    end
  end
end
