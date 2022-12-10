# frozen_string_literal: true

module ActiveExperiment
  # == Core Module
  #
  # Provides general behavior that will be included into every Active
  # Experiment object that inherits from ActiveExperiment::Base.
  module Core
    extend ActiveSupport::Concern

    # The experiment context.
    #
    # Experiment contexts should be consistent and unique values that are used
    # to assign the same variant over many runs. Examples can range from an
    # Active Record object to the weekday name. If a given variant is assigned
    # on Tuesdays, it will always be assigned on Tuesdays, or if a variant is
    # assigned for a given Active Record object, it will always be assigned for
    # that record.
    #
    # Context is used to generate the cache key, so including something that
    # would change the cache key on every run is not recommended.
    attr_reader :context

    # The experiment name.
    #
    # This is an underscored version of the experiment class name. If within a
    # namespace, the namespace will be included in the name, separated by a
    # slash (e.g. "my_namespace/my_experiment").
    attr_reader :name

    # The experiment run identifier.
    #
    # A unique UUID, per experiment instantiation.
    attr_reader :run_id

    # The experiment run key.
    #
    # This is a hexdigest that's generated from the experiment context. The run
    # key is used as the cache key and can be used by the rollout to determine
    # variant assignment.
    attr_reader :run_key

    # The variant that's been assigned or resolved for this run.
    #
    # This can be manually provided before the experiment is run, or can be
    # resolved by segment rules or asking the rollout.
    attr_reader :variant

    # Experiment options.
    #
    # Generally not used within the core library, this is provided to expose
    # additional data when running experiments. Use the +set+ method to set a
    # variant, or other options.
    attr_reader :options

    # These methods will be included into any Active Experiment object and
    # provide variant registration methods.
    module ClassMethods
      # The experiment name.
      #
      # An underscored version of the experiment class name. If within a
      # namespace, the namespace will be included in the name, separated by a
      # slash (e.g. "my_namespace/my_experiment").
      def experiment_name
        name.underscore
      end

      private
        def control(...)
          variant(:control, ...)
        end

        def variant(name, ...)
          register_variant_callback(name, ...)
        end
    end

    # Creates a new experiment instance.
    #
    # The context provided to an experiment should be a consistent and unique
    # value used to assign the same variant over many runs.
    def initialize(context = {})
      @context = context
      @name = self.class.experiment_name
      @run_id = SecureRandom.uuid
      @run_key = run_key_hexdigest(context)
      @options = {}
    end

    # Configures the experiment with the given options.
    #
    # This is used to set the variant, and can be used to set other options
    # that may be used within an experiment. It's separate from the context to
    # allow for the context to be used for variant assignment, while other
    # options might still be useful.
    #
    # Raises an +ArgumentError+ if the variant is unknown.
    # Returns self to allow chaining, typically for calling run.
    def set(variant: nil, **options)
      @options = @options.merge(options)
      if variant.present?
        variant = variant.to_sym
        raise ArgumentError, "Unknown #{variant.inspect} variant" unless variants[variant]

        @variant = variant
      end

      self
    end

    # Allows providing overrides for registered variants.
    #
    # When running experiments, any variant can be overridden to only invoke
    # the provided override. This allows access to the scope and helpers where
    # the experiment is being run. An example in a controller might look like:
    #
    #   MyExperiment.run(current_user) do |experiment|
    #     experiment.on(:red) { render "red_pill" }
    #     experiment.on(:blue) { redirect_to "blue_pill" }
    #   end
    #
    # Raises an +ArgumentError+ if the variant is unknown, or if no block has
    # been provided.
    def on(*variant_names, &block)
      variant_names.each do |variant|
        variant = variant.to_sym
        raise ArgumentError, "Unknown #{variant.inspect} variant" unless variants[variant]
        raise ArgumentError, "Missing block" unless block

        variant_step_chains[variant] = block
      end
    end

    # Allows skipping the experiment.
    #
    # When an experiment is skipped, the default variant will be assigned, and
    # generally means that no reporting should be generated for the run.
    def skip
      @skip = true
    end

    # Returns true if the experiment should be skipped.
    #
    # If the experiment has been instructed to be skipped, or if the rollout is
    # not enabled, then the experiment should be viewed as skipped.
    def skipped?
      return @skip if defined?(@skip)

      @skip = !self.rollout.enabled_for(self)
    end

    # Returns a hash with the experiment data.
    #
    # This is used to serialize the experiment data for logging and reporting,
    # And can be overridden to provide additional data relevant to the
    # experiment.
    #
    # Calling this before the variant has been assigned or resolved will result
    # in the variant being empty. Generally, this should be called after the
    # experiment has been run.
    def serialize
      {
        "experiment" => name,
        "run_id" => run_id,
        "run_key" => run_key,
        "variant" => variant.to_s,
        "skipped" => skipped?
      }
    end

    def to_s # :nodoc:
      details = [@variant.inspect, @skip.inspect, (@run_key.slice(0, 16) + "..."), @context.inspect, @options.inspect]
      string = "#<%s:%#0x @variant=%s @skip=%s @run_key=%s @context=%s, @options=%s>"
      sprintf(string, self.class.name, object_id, *details)
    end
  end
end
