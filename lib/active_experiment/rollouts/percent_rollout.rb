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
    #     use_rollout :percent
    #
    #     # Assign 25% to control, 30% to red, and 45% to blue.
    #     use_rollout :percent, rules: {control: 25, red: 30, blue: 45}
    #
    #     # Same as above, but using an array.
    #     use_rollout :percent, rules: [25, 30, 45]
    #   end
    #
    # To use as the default, configure it to +:percent+.
    #
    #   ActiveExperiment::Base.default_rollout = :percent
    #   Rails.application.config.active_experiment.default_rollout = :percent
    class PercentRollout < BaseRollout
      def initialize(experiment_class, ...) # :nodoc:
        super

        @variant_names_validated = validate!(experiment_class)
      end

      def variant_for(experiment) # :nodoc:
        # Checked again only when the variants weren't registered in time to
        # be compared against. By the time a variant is being assigned they
        # are, and after that this costs an ivar read.
        @variant_names_validated ||= validate!(experiment.class)

        variants = experiment.variant_names
        crc = Zlib.crc32(experiment.run_key, 0)

        case rules
        when Array then variants[bucket_index(crc, rules)]
        when Hash then rules.keys[bucket_index(crc, rules.values)]
        else variants[crc % variants.length]
        end
      end

      # The declared distribution, alongside what +BaseRollout#describe+
      # reports.
      def describe # :nodoc:
        super.merge(distribution: distribution)
      end

      private
        # The percentage of contexts each variant is expected to be assigned,
        # keyed by variant name.
        #
        # Rules are normalized here rather than reported as they were written,
        # since the same split can be declared as a hash, an array matching the
        # variants, or left out entirely for an even split.
        #
        # Returns an empty hash when the variants aren't registered yet and the
        # rules alone don't name them.
        def distribution
          variant_names = @experiment_class.try(:variants)&.keys || []

          case rules
          when Hash then rules.to_h { |variant, percent| [variant.to_sym, percent.to_f] }
          when Array then variant_names.zip(rules.map(&:to_f)).to_h
          else
            # An even split is what +variant_for+ falls back to, dividing the
            # run key across the variants with a modulo.
            return {} if variant_names.empty?

            even = 100.0 / variant_names.length
            variant_names.index_with { even }
          end
        end

        # Determine which of the declared percentages the run key lands within.
        #
        # The percentages are widths, so 25, 30, 45 means the boundaries are at
        # 25, 55 and 100.
        def bucket_index(crc, percents)
          position = crc % 100
          boundary = 0

          percents.find_index { |percent| position < boundary += percent }
        end

        # The percentages are checked even if the variants haven't been
        # registered yet. The variant names can only be compared if they're
        # registered, so it's best to specify your rollout strategy after
        # registering your variants -- when it's specified first, the names
        # are checked on the first run instead.
        #
        # Returns whether the names were compared, so the caller knows whether
        # that still has to happen.
        def validate!(experiment_class)
          variant_names = experiment_class.try(:variants)&.keys

          case rules
          when Hash
            sum = rules.values.sum
            raise ArgumentError, "The provided rules total #{sum}%, but should be 100%" if sum != 100
            return false if variant_names.blank?

            unexpected = rules.keys - variant_names
            missing = variant_names - rules.keys
            diff = unexpected | missing
            raise ArgumentError, "The provided rules don't match the variants: #{diff.join(", ")}" if diff.any?
          when Array
            sum = rules.sum
            raise ArgumentError, "The provided rules total #{sum}%, but should be 100%" if sum != 100
            return false if variant_names.blank?

            diff = rules.length - variant_names.length
            raise ArgumentError, "The provided rules don't match the number of variants" if diff != 0
          else
            raise ArgumentError unless rules.nil?
          end

          true
        end

        def rules
          @rollout_options[:rules]
        end
    end
  end
end
