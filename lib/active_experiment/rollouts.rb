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
  # Custom rollouts can also be registered by name, and are then only loaded
  # when an experiment uses one:
  #
  #   ActiveExperiment::Rollouts.register(:feature_flag, "FeatureFlagRollout")
  #
  # This is what a rollout in +app/+ wants. Nothing has to be loaded to
  # register one, so it can be done from an initializer, where autoloading
  # isn't available yet -- and the name being resolved on every lookup means
  # the reloader replacing the class in development is picked up.
  #
  # A rollout that lives somewhere Rails doesn't autoload from can be
  # registered with a +Pathname+ to it instead:
  #
  #   ActiveExperiment::Rollouts.register(
  #     :feature_flag,
  #     Rails.root.join("lib/feature_flag_rollout.rb")
  #   )
  module Rollouts
    extend ActiveSupport::Autoload

    autoload :InactiveRollout
    autoload :PercentRollout
    autoload :RandomRollout

    ROLLOUT_SUFFIX = "Rollout"
    private_constant :ROLLOUT_SUFFIX

    # The rollouts that ship with the library. Held as names so that looking
    # one up autoloads it, the same as any other registered rollout.
    BUILT_IN = {
      inactive: "ActiveExperiment::Rollouts::InactiveRollout",
      percent: "ActiveExperiment::Rollouts::PercentRollout",
      random: "ActiveExperiment::Rollouts::RandomRollout"
    }.freeze
    private_constant :BUILT_IN

    # Allows registering custom rollouts.
    #
    # The rollout must implement the +skipped_for+ and +variant_for+ methods,
    # which is checked when the rollout is used in an experiment.
    #
    # A rollout can be registered as a class, as the name of one, or as a
    # +Pathname+ to a file defining one:
    #
    #   ActiveExperiment::Rollouts.register(:feature_flag, FeatureFlagRollout)
    #   ActiveExperiment::Rollouts.register(:feature_flag, "FeatureFlagRollout")
    #   ActiveExperiment::Rollouts.register(:feature_flag, Rails.root.join("lib/feature_flag_rollout.rb"))
    #
    # Registering by name is what a rollout in +app/+ wants. Nothing has to be
    # loaded to register one, so it can be done from an initializer, where
    # autoloading isn't available yet -- and because the name is resolved every
    # time it's looked up, a reloaded class is picked up rather than the copy
    # that was registered.
    #
    # A class that has a name is stored by it for the same reason. One that
    # doesn't -- an anonymous class, or a +register_as+ inside +Class.new+ --
    # is held as it is, and won't survive a reload.
    #
    # Raises an +ArgumentError+ if the rollout isn't an expected type.
    def self.register(name, rollout)
      registry[name.to_sym] =
        case rollout
        when Pathname then rollout
        when String then rollout
        when Class then rollout.name || rollout
        else
          raise ArgumentError, "Provide a rollout class, the name of one, or a Pathname to one"
        end
    end

    # Allows looking up a rollout by name.
    #
    # Only names that were registered resolve, so an unrelated +FooRollout+
    # defined elsewhere in an application can't answer +lookup(:foo)+.
    #
    # Raises an +ArgumentError+ if the rollout hasn't been registered.
    def self.lookup(name)
      name = name.to_sym
      rollout = registry.fetch(name) { raise ArgumentError, "No rollout registered for #{name.inspect}" }

      case rollout
      when Class then rollout
      when Pathname then load_rollout(name, rollout)
      else rollout.to_s.constantize
      end
    rescue NameError => error
      raise ArgumentError, "No rollout registered for #{name.inspect} (#{error.message})"
    end

    def self.registry # :nodoc:
      @registry ||= BUILT_IN.dup
    end

    # The name a rollout class was registered as, or +nil+ for one that wasn't
    # registered at all -- an experiment can be handed a rollout instance
    # directly, and never has to name it.
    def self.name_for(rollout_class)
      name = rollout_class.try(:name)

      registry.each do |registered_name, rollout|
        case rollout
        when Class then return registered_name if rollout == rollout_class
        when String then return registered_name if name && rollout == name
        end
      end

      nil
    end

    # The file a +Pathname+ points at is expected to define a rollout named for
    # what it was registered as, usually at the top level.
    def self.load_rollout(name, path) # :nodoc:
      require path.to_s

      "#{name.to_s.camelize}#{ROLLOUT_SUFFIX}".constantize
    end
    private_class_method :load_rollout

    # Base class for the included rollouts. Useful for custom rollouts.
    #
    # Any rollout that inherits from this class will be valid, not skipped, and
    # will assign the first defined variant unless the provided methods are
    # overridden.
    class BaseRollout
      # Convenience method to register the rollout with Active Experiment.
      #
      # This only takes effect once the class has been loaded, so it suits a
      # rollout that's required, or one defined in an initializer. A rollout in
      # +app/+ is autoloaded, and in development nothing loads it until it's
      # referenced -- register those by name instead, with
      # +ActiveExperiment::Rollouts.register(:name, "TheRollout")+.
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

      # How this rollout would describe itself to something reporting on the
      # experiment, as a hash of:
      #
      # [+:type+]
      #   The name it was registered as, falling back to the class name.
      # [+:options+]
      #   Whatever was passed along with +use_rollout+.
      # [+:distribution+]
      #   The share of contexts each variant is expected to be assigned, as
      #   percentages keyed by variant name -- or +nil+ from a rollout that
      #   can't say, which is most of them.
      #
      # Rollouts aren't required to implement this. An experiment can use
      # anything responding to +skipped_for+ and +variant_for+ as its rollout,
      # including itself, so callers should use +rollout.try(:describe)+.
      def describe
        {
          type: Rollouts.name_for(self.class) || self.class.name,
          options: @rollout_options,
          distribution: nil
        }
      end
    end
  end
end
