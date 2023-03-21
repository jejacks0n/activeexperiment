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
      def run_callbacks(kind, event_name, **payload, &block)
        if kind.present? && __callbacks[kind.to_sym].any?
          instrument(event_name, **payload) do
            super(kind, &block)
          end
        else
          yield if block_given?
        end
      end

      def instrument(operation, **payload, &block)
        operation = "#{operation}.active_experiment"
        payload = payload.merge(experiment: self)
        return ActiveSupport::Notifications.instrument(operation, payload) unless block.present?

        ActiveSupport::Notifications.instrument(operation, payload) do |event_payload|
          @variant = nil unless defined?(@variant)
          @halted_callback = nil unless defined?(@halted_callback)

          variant = @variant
          results = block.call

          event_payload[:variant] = @variant if variant != @variant
          event_payload[:aborted] = @halted_callback if @halted_callback.present?
          @halted_callback = nil if @halted_callback == :segment

          results
        end
      end

      def halted_callback_hook(filter, name)
        super
        @halted_callback = name
      end
  end
end
