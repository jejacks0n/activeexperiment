# frozen_string_literal: true

module ActiveExperiment
  # == Included Rollouts
  #
  # Active Experiment provides a few base rollout concepts that can be used to
  # determine if an experiment should be skipped, and which variant to assign.
  #
  # A default rollout can be configured globally, and different rollouts can be
  # specified on a per-experiment basis. Rollouts aren't inherited from parent
  # classes.
  #
  # The included rollouts are:
  #
  # * +:random+ - Randomly assigns a variant (each run, or once with caching).
  # * +:percent+ - Assigns a variant based on distribution rules, or evenly.
  #
  # == Custom Rollouts
  #
  # Custom rollouts can be created and registered with Active Experiment. A
  # rollout must implement two methods to be considered valid, which can be
  # achieved by inheriting the base class or one of the included rollouts.
  #
  # To illustrate, here's a simple rollout based on a fictional feature flag
  # library that also assigns a random variant.
  #
  #   class FeatureFlagRollout < ActiveExperiment::Rollouts::BaseRollout
  #     def skipped_for(experiment)
  #       !FeatureFlag.enabled?(@rollout_options[:flag_name] || experiment.name)
  #     end
  #
  #     def variant_for(experiment)
  #       experiment.variant_names.sample
  #     end
  #   end
  #
  # This can now be registered and used the same way the included rollouts are:
  #
  #   ActiveExperiment::Rollouts.register(:feature_flag, FeatureFlagRollout)
  #
  # After registering the custom rollout, it can be used in experiments:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     variant(:red) { }
  #     variant(:blue) { }
  #
  #     use_rollout :feature_flag, flag_name: "my_feature_flag"
  #   end
  #
  # Or it can be configured as the default rollout for all experiments:
  #
  #   ActiveExperiment::Base.default_rollout = :feature_flag
  #
  # Custom rollouts can also be registered using autoloading. For example, if a
  # custom rollout is defined in +lib/feature_flag_rollout.rb+, it can be
  # registered to be autoloaded, and is only loaded when needed.
  #
  #   ActiveExperiment::Rollouts.register(
  #     :feature_flag,
  #     Rails.root.join("lib/feature_flag_rollout.rb")
  #   )
  #
  # Now, the custom rollout will only be loaded when used in an experiment.
  module Rollouts
    extend ActiveSupport::Autoload

    autoload :InactiveRollout
    autoload :PercentRollout
    autoload :RandomRollout

    ROLLOUT_SUFFIX = "Rollout"
    private_constant :ROLLOUT_SUFFIX

    # Allows registering custom rollouts.
    #
    # The rollout must implement the +skipped_for+ and +variant_for+ methods,
    # which is checked when the rollout is used in an experiment.
    #
    # If a string or +Pathname+ is provided, the rollout will be autoloaded.
    #
    # Raises an +ArgumentError+ if the rollout isn't an expected type.
    def self.register(name, rollout)
      const_name = "#{name.to_s.camelize}#{ROLLOUT_SUFFIX}"
      case rollout
      when String, Pathname
        autoload(const_name, rollout)
      when Class
        const_set(const_name, rollout)
      else
        raise ArgumentError, "Provide a class to register, or string for autoloading"
      end
    end

    # Allows looking up a rollout by name.
    #
    # Raises an +ArgumentError+ if the rollout hasn't been registered.
    def self.lookup(name)
      const_get("#{name.to_s.camelize}#{ROLLOUT_SUFFIX}")
    rescue NameError
      raise ArgumentError, "No rollout registered for #{name.inspect}"
    end

    # Base class for the included rollouts. Useful for custom rollouts.
    #
    # Any rollout that inherits from this class will be valid, not skipped, and
    # will assign the first defined variant unless the provided methods are
    # overridden.
    class BaseRollout
      # Convenience method to register the rollout with Active Experiment.
      def self.register_as(name)
        Rollouts.register(name, self)
      end

      def initialize(experiment_class, *args, **options, &block) # :nodoc:
        @experiment_class = experiment_class
        @rollout_args = args
        @rollout_options = options
        yield if block
      end

      # The base rollout is never skipped.
      def skipped_for(_experiment)
        false
      end

      # The base rollout always assigns the first variant.
      def variant_for(experiment)
        experiment.variant_names.first
      end
    end
  end
end
