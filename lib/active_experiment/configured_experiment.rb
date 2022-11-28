# frozen_string_literal: true

module ActiveExperiment
  # == Configured Experiment
  #
  # A wrapper around an experiment that allows setting options on, and then
  # doing more with the experiment. It includes tooling for running, or caching
  # a variant for a collection of contexts.
  #
  # When calling +MyExperiment.set+, a configured experiment will be returned.
  # Additional methods can then be called on the configured experiment instance
  # to run the experiment or cache variants.
  #
  # For example, a configured experiment can be used to configure, instantiate
  # and run an experiment:
  #
  #   MyExperiment.set(variant: :blue).run(id: 1) do |experiment|
  #     experiment.on(:blue) { "blue override" }
  #   end
  #
  # Or it can be used to cache the variant assignment for a collection of
  # contexts.
  #
  #   MyExperiment.set(variant: red).cache_each(User.find_each)
  #
  # This class is also provided to be used when adding additional tooling for
  # specific project needs. Here's an example of reopening this class to add a
  # project specific +cleanup_cache+ method:
  #
  #   class ActiveExperiment::ConfiguredExperiment
  #     def cleanup_cache
  #       store = experiment.cache_store
  #       store.delete_matched("#{experiment.cache_key_prefix}/*")
  #     end
  #   end
  #
  #  Which could then be used by calling one of the following:
  #
  #   MyExperiment.set.cleanup_cache
  #   ConfiguredExperiment.new(MyExperiment).cleanup_cache
  class ConfiguredExperiment
    def initialize(experiment_class, **options) # :nodoc:
      @experiment_class = experiment_class
      @options = options
    end

    # Runs the experiment with the configured options, context, and the given
    # block. The block will be called with the experiment instance.
    #
    # This is a convenience method for instantiating and running an experiment:
    #
    #   MyExperiment.set(variant: :blue).run(id: 1) { }
    def run(context = {}, &block)
      experiment(context).run(&block)
    end

    # When provided an enumerable, an experiment will be instantiated for each
    # item and the variant assignment will be cached. This method can be used
    # to pre-cache the variant assignment for a collection of contexts.
    #
    #   MyExperiment.set(variant: red).cache_each(User.find_each)
    def cache_each(enumerable_contexts)
      enumerable_contexts.each do |context|
        experiment(context).cache_variant!
      end
    end

    # Returns the experiment instance with the configured options and provided
    # context.
    def experiment(context = {})
      @experiment_class.new(context).set(**@options)
    end
  end
end
