# frozen_string_literal: true

require "active_support/callbacks"

module ActiveExperiment
  # == Callbacks
  #
  # Active Experiment provides several callbacks to hook into the lifecycle of
  # running an experiment. Using callbacks in Active Experiment is the same as
  # using other callbacks within Rails.
  #
  # The callbacks are generally separated into two concepts: run and variant.
  # Run callbacks are invoked whenever an experiment is run, and variant
  # callbacks are only invoked when that variant is assigned or resolved.
  #
  # The following run callback methods are available:
  #
  # * +before_run+
  # * +after_run+
  # * +around_run+
  #
  # The variant may not be known when each run callback is invoked, so it's not
  # advised to rely on a variant within run callbacks. The variant callbacks
  # are useful for that however, since they're only invoked for a given
  # variant. The variant name must be provided to the variant callback methods.
  #
  # The following variant callback methods are available:
  #
  # * +before_variant+
  # * +after_variant+
  # * +around_variant+
  #
  # An example of an experiment that uses run and variant callbacks:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #
  #     after_run :after_run_callback_method, if: -> { true }
  #     before_run { puts "before #{name}" }
  #     around_run do |_experiment, block|
  #       puts "around #{name} [#{block.call}]"
  #     end
  #
  #     after_variant(:red) { puts "after:red #{name}" }
  #     before_variant(:red) { puts "before:red #{name}" }
  #     around_variant(:blue) do |_experiment, block|
  #       puts "around:blue #{name} [#{block.call}]"
  #     end
  #
  #     private
  #
  #     def after_run_callback_method
  #       puts "after #{name}"
  #     end
  #   end
  module Callbacks
    extend ActiveSupport::Concern
    include ActiveSupport::Callbacks

    included do
      define_callbacks :run, skip_after_callbacks_if_terminated: true
      private :__callbacks, :__callbacks?, :run_callbacks, :_run_callbacks, :_run_run_callbacks
    end

    # These methods will be included into any Active Experiment object, adding
    # the run and variant callback methods, and tooling to build callbacks with
    # a target, which is used by segment rules and variant steps.
    module ClassMethods
      private
        def before_run(*filters, &block)
          set_callback(:run, :before, *filters, &block)
        end

        def after_run(*filters, &block)
          set_callback(:run, :after, *filters, &block)
        end

        def around_run(*filters, &block)
          set_callback(:run, :around, *filters, &block)
        end

        def before_variant(variant, *filters, &block)
          set_variant_callback(variant, :before, *filters, &block)
        end

        def after_variant(variant, *filters, &block)
          set_variant_callback(variant, :after, *filters, &block)
        end

        def around_variant(variant, *filters, &block)
          set_variant_callback(variant, :around, *filters, &block)
        end

        def set_callback_with_target(chain, *filters, default: nil, **options)
          filters = filters.compact

          if filters.empty? && !default.nil?
            filters = [default] if options[:if].present? || options[:unless].present?
          end

          filters = filters.map do |filter|
            result_lambda = ActiveSupport::Callbacks::CallTemplate.build(filter, self).make_lambda
            ->(target) { yield(target, result_lambda) }
          end

          set_callback(chain, *filters, **options)
        end
    end
  end
end
