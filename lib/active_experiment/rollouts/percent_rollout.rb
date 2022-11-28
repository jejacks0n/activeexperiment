# frozen_string_literal: true

require "zlib"

module ActiveExperiment
  module Rollouts
    # == Active Experiment Percent Rollout
    #
    # The percent rollout is the most comprehensive included in the base
    # library, and so is set as the default. The way this rollout works is by
    # generating a crc from the experiment run key, which ensures that a given
    # context will always be assigned the same variant.
    #
    # Distribution rules can be specified using an array or a hash, and if no
    # rules are provided the default is to assign even distribution across all
    # variants.
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     control { }
    #     variant(:red) { }
    #     variant(:blue) { }
    #
    #     # Assign even distribution to all variants.
    #     rollout :percent
    #
    #     # Assign 25% to control, 30% to red, and 45% to blue.
    #     rollout :percent, rules: {control: 25, red: 30, blue: 45}
    #
    #     # Same as above, but using an array.
    #     rollout :percent, rules: [25, 30, 45]
    #   end
    #
    # To use as the default, configure it to +:percent+.
    #
    #   ActiveExperiment::Base.default_rollout = :percent
    #   Rails.application.config.active_experiment.default_rollout = :percent
    class PercentRollout < BaseRollout
      def initialize(experiment_class, ...) # :nodoc:
        super

        validate!(experiment_class)
      end

      def variant_for(experiment) # :nodoc:
        variants = experiment.variant_names
        crc = Zlib.crc32(experiment.run_key, 0)
        total = 0

        case rules
        when Array then variants[rules.find_index { |percent| crc % 100 <= total += percent }]
        when Hash then rules.find { |_, percent| crc % 100 <= total += percent }.first
        else variants[crc % variants.length]
        end
      end

      private
        def validate!(experiment_class)
          variant_names = experiment_class.try(:variants)&.keys
          return if variant_names.blank?

          case rules
          when Hash
            sum = rules.values.sum
            raise ArgumentError, "The provided rules total #{sum}%, but should be 100%" if sum != 100

            diff = rules.keys - variant_names | variant_names - rules.keys
            raise ArgumentError, "The provided rules don't match the variants: #{diff.join(", ")}" if diff.any?
          when Array
            sum = rules.sum
            raise ArgumentError, "The provided rules total #{sum}%, but should be 100%" if sum != 100

            diff = rules.length - variant_names.length
            raise ArgumentError, "The provided rules don't match the number of variants" if diff != 0
          else
            raise ArgumentError unless rules.nil?
          end
        end

        def rules
          @rollout_options[:rules]
        end
    end
  end
end
