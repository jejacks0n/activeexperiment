# frozen_string_literal: true

module ActiveExperiment
  # == Instrumentation Module
  #
  # Instrumentation is provided through +ActiveSupport::Notifications+. The
  # best example of how to utilize the instrumentation within Active Experiment
  # is look at how +ActiveExperiment::LogSubscriber+ has been implemented.
  module Instrumentation
    extend ActiveSupport::Concern

    private
      def run_callbacks(kind, **payload, &block)
        if kind.present? && __callbacks[kind.to_sym].any?
          instrument(event_name_for_callback(kind), **payload) do
            super(kind, &block)
          end
        else
          yield if block_given?
        end
      end

      def instrument(operation, **payload, &block)
        operation = "#{operation}.active_experiment"
        enhanced_block = ->(event_payload) do
          variant_before = self.variant
          value = block ? block.call : nil

          if variant_before != self.variant
            event_payload[:variant] = self.variant
          end

          if defined?(@_halted_callback_hook_called) && @_halted_callback_hook_called
            event_payload[:aborted] = true
            @_halted_callback_hook_called = nil
          end

          value
        end

        ActiveSupport::Notifications.instrument(operation, payload.merge(experiment: self), &enhanced_block)
      end

      def event_name_for_callback(kind)
        kind = kind.to_s
        if kind.end_with?("_variant")
          return "run_variant_callbacks"
        elsif kind.end_with?("_variant_steps")
          return "run_variant_steps"
        end

        "run_#{kind}_callbacks"
      end

      def halted_callback_hook(*)
        super
        @_halted_callback_hook_called = true
      end
  end
end
