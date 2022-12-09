# frozen_string_literal: true

module ActiveExperiment
  # == Variant Registration
  #
  # Variants are registered using the +control+ and +variant+ methods within an
  # experiment. The +control+ method is a convenience for registering a variant
  # with the name +:control+ -- a convention used to describe the default
  # variant.
  #
  # Registering a variant can be done by providing a name, and a block or a
  # symbol referencing a method.
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     control { "control" } # defines a variant named :control
  #     variant :treatment, :treatment_method
  #
  #     private
  #
  #     def treatment_method
  #       "treatment"
  #     end
  #   end
  #
  # Subclassing experiments will inherit variants. Existing variants can be
  # overridden or added to, and new variants can registered.
  #
  #   class NewExperiment < MyExperiment
  #     control(override: true) { "new control" }
  #     variant(:treatment, add: true, prepend: true) { "new treatment" }
  #     variant(:new_variant) { "new variant" }
  #   end
  #
  # In the above example, the control is overridden, a new variant is added,
  # and a new step is added to the treatment variant.
  #
  # When running an experiment, variants can be overridden by using the +on+
  # method. This allows utilizing the scope of where the experiment is run to
  # change the experiment behavior.
  #
  #   NewExperiment.run do |experiment|
  #     experiment.on(:treatment) { "overridden treatment" }
  #   end
  #
  # By default, the "control" variant is assigned as the default variant, but
  # any variant can be specified as the default. The concept of the control
  # variant is only a convention.
  #
  # To specify a different default variant:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #
  #     use_default_variant :blue
  #   end
  #
  # The default variant is assigned if the experiment is skipped or if no other
  # variant has been resolved after asking the rollout -- when the rollout may
  # not be working properly.
  module Variants
    extend ActiveSupport::Concern
    include ActiveSupport::Callbacks

    VARIANT_CHAIN_SUFFIX = "_variant"
    private_constant :VARIANT_CHAIN_SUFFIX

    STEP_CHAIN_SUFFIX = "_steps"
    private_constant :STEP_CHAIN_SUFFIX

    included do
      class_attribute :variants, instance_writer: false, instance_predicate: false, default: {}
      class_attribute :default_variant, instance_writer: false, instance_predicate: false, default: :control
    end

    # These methods will be included into any Active Experiment object, adding
    # the the ability to set the default variant, defining variants and their
    # behaviors and callback helpers.
    module ClassMethods
      private
        def use_default_variant(variant)
          variant = variant.to_sym
          raise ArgumentError, "Unknown #{variant.inspect} variant" unless variants[variant]

          self.default_variant = variant
        end

        def register_variant_callback(variant, *filters, override: false, add: false, **options, &block)
          raise ArgumentError, "Provide either `override: true` or `add: true` but not both" if override && add

          variant = variant.to_sym
          if variants[variant].present?
            unless override || add
              raise ArgumentError, "The #{variant.inspect} variant is already registered. " \
                "Provide `override: true` or `add: true` to make changes to it."
            end
          elsif override || add
            raise ArgumentError, "Unable to override or add to unknown #{variant.inspect} variant"
          end

          self.variants = variants.dup unless singleton_class.method_defined?(:variants, false)

          variants[variant] = callback_chain = :"#{variant}#{VARIANT_CHAIN_SUFFIX}"

          unless add
            define_variant_callbacks(callback_chain) # variant callback chain
            define_variant_callbacks("#{callback_chain}#{STEP_CHAIN_SUFFIX}") # variant step chain
          end

          filters.push(block) if block.present?
          filters.unshift(callback_chain) if filters.empty?
          set_callback_with_target("#{callback_chain}#{STEP_CHAIN_SUFFIX}", *filters, **options) do |target, callback|
            target.instance_variable_set(:@results, callback.call(target, nil))
          end
        end

        def define_variant_callbacks(callback_chain)
          define_callbacks(callback_chain)
          private :"_#{callback_chain}_callbacks", :"_run_#{callback_chain}_callbacks"
        end

        def set_variant_callback(variant, type, *filters, &block)
          raise ArgumentError, "Unknown `#{variant}` variant" unless variants[variant.to_sym]

          set_callback("#{variant}#{VARIANT_CHAIN_SUFFIX}", type, *filters, &block)
        end
    end

    # The names for all registered variants.
    #
    # This is most commonly used by rollouts, where knowing the variant names
    # is important for determining which variant to assign.
    def variant_names
      variants.keys
    end

    private
      def variant_step_chains
        @variant_step_chains ||= variants.transform_values do |callback_chain|
          chain_name = "#{callback_chain}#{STEP_CHAIN_SUFFIX}"
          -> { run_callbacks(chain_name, :process_variant_steps) { @results } }
        end
      end
  end
end
