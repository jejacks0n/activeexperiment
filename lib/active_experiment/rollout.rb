# frozen_string_literal: true

module ActiveExperiment
  # == Rollout Module
  #
  # Active Experiment can be configured to use one of the built in rollouts, or
  # a custom rollout.
  #
  # When configuring the default rollout, you can use a symbol or something
  # that responds to the required +enabled_for+ and +variant_for+ methods. To
  # configure the default rollout:
  #
  #   ActiveExperiment::Base.default_rollout = :random
  #
  # The above example will use the built in +:random+ rollout for all
  # experiments. A given experiment can also be configured to use a specific
  # rollout which will override the default:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #
  #     rollout :percent, rules: { blue: 60, red: 40 }
  #   end
  #
  # An experiment might even be configured to use itself as a rollout. As
  # long as the class responds to the required methods, it can be used.
  #
  #   module ExperimentRolloutExample
  #     def enabled_for?(*)
  #       true
  #     end
  #
  #     def variant_for(*)
  #       :red
  #     end
  #   end
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     extend ExperimentRolloutExample
  #
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #
  #     use_rollout self
  #   end
  #
  # The flexibility that this affords is that you can use any rollout you want
  # for any experiment. Rollouts can be defined that use a database, feature
  # flags, or any other mechanism you want.
  module Rollout
    extend ActiveSupport::Concern

    REQUIRED_ROLLOUT_METHODS = [:enabled_for, :variant_for].freeze
    private_constant :REQUIRED_ROLLOUT_METHODS

    included do
      class_attribute :rollout, instance_predicate: false
      private :rollout=

      self.default_rollout = :percent
    end

    # These methods will be included into any Active Experiment object and
    # allow setting the default rollout, the experiment specific rollout, and
    # includes the inherited behavior for default rollouts. When setting the
    # rollout, it will be validated to ensure it responds to the required
    # methods.
    module ClassMethods
      def inherited(subclass) # :nodoc:
        super
        subclass.default_rollout = @default_rollout
      end

      # Allows setting the default rollout for all experiments.
      #
      # This can be overridden on a per experiment basis, but overrides to the
      # default rollout are not be inherited. Meaning that each experiment will
      # revert to the default rollout, regardless of what it inherits from.
      def default_rollout=(name_or_rollout)
        use_rollout(name_or_rollout)
        @default_rollout = name_or_rollout
      end

      private
        def use_rollout(name_or_rollout, *args, **kws, &block)
          case name_or_rollout
          when Symbol, String
            rollout = ActiveExperiment::Rollouts.lookup(name_or_rollout)
            self.rollout = rollout.new(self, *args, **kws, &block)
          else
            unless rollout_interface?(name_or_rollout)
              raise ArgumentError, "Invalid rollout. " \
                "Rollouts must respond to #{REQUIRED_ROLLOUT_METHODS.join(", ")}."
            end

            self.rollout = name_or_rollout
          end
        end

        def rollout_interface?(object)
          REQUIRED_ROLLOUT_METHODS.all? { |meth| object.respond_to?(meth) }
        end
    end
  end
end
