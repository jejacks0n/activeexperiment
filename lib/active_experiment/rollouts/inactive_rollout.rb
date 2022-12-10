# frozen_string_literal: true

module ActiveExperiment
  module Rollouts
    # == Active Experiment Inactive Rollout
    #
    # Using this rollout will disable experiments as though they were
    # intentionally skipped.
    #
    # To use as the default, configure it to +:inactive+.
    #
    #   ActiveExperiment::Base.default_rollout = :inactive
    #   Rails.application.config.active_experiment.default_rollout = :inactive
    class InactiveRollout < BaseRollout
      def enabled_for(*)
        false
      end

      def variant_for(*)
        nil
      end
    end
  end
end
