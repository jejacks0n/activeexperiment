# frozen_string_literal: true

require "active_support/log_subscriber"

module ActiveExperiment
  # == Log Subscriber
  #
  # Renders the instrumentation Active Experiment emits into logs.
  #
  # It's attached to the +active_experiment+ notification namespace when
  # loaded, and serves as an example of how you can write a custom reporter.
  #
  # An experiment run logs when it starts and when it finishes, and anything
  # notable in between:
  #
  #   MyExperiment[31bc574e]  Running my_experiment (Run ID: f2a9c6d6-cae7-...)
  #   MyExperiment[31bc574e]  Segmented into the `red` variant (0.0ms)
  #   MyExperiment[31bc574e]  Completed running red variant (Duration: 0.1ms | Allocations: 299)
  #
  # The prefix is the experiment class and the first 8 characters of its run
  # key, which is what ties lines together when experiments are nested or
  # several run in the same request.
  #
  # == Levels
  #
  # Roughly: +:info+ is the story of a run, +:debug+ fills in the callback
  # chains, and anything above those would be something worth looking at.
  #
  # - +:error+ -- a run raised, or finished without resolving a variant, or
  #   resolved one that isn't registered -- probably an issue.
  # - +:warn+ -- an experiment was run inside another experiment's run. Nesting
  #   isn't prevented, but it can be a sign of something to be documented.
  # - +:info+ -- a run starting, the variant it completed with, a segment
  #   assigning a variant, and a callback chain resolving one.
  # - +:debug+ -- callback chains completing without resolving a variant.
  #
  # == Logging the Context
  #
  # Contexts are left out of the log by default, since they're often user
  # records or anything else that identifies a subject. An experiment can opt
  # in when its context is safe to write down:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     self.log_context = true
  #   end
  #
  # Which appends it to the line the run starts on:
  #
  #   MyExperiment[9432f43c]  Running my_experiment (Run ID: a13ea567-...) with context: {id: 1}
  #
  # == Replacing It
  #
  # The events are public, so this subscriber can be swapped for one that logs
  # differently, or turned off without silencing the rest of the library:
  #
  #   ActiveExperiment::LogSubscriber.detach_from(:active_experiment)
  #
  # +ActiveExperiment::Instrumentation+ covers the events themselves, and the
  # methods below are one per event if you want to see what each has to work
  # with.
  class LogSubscriber < ActiveSupport::LogSubscriber
    # Run callbacks can only ever log at :debug -- the :info branch in
    # +build_callback_message+ excludes them by name -- so declaring it lets
    # Active Support skip building an event for one that can't be written.
    subscribe_log_level :process_run_callbacks, :debug

    LEVEL_PREDICATES = { debug: :debug?, info: :info?, warn: :warn?, error: :error? }.freeze
    private_constant :LEVEL_PREDICATES

    def start_experiment(event)
      warn_of_nested_experiment(event) if execution_stack.any?
      experiment_logger(event) do |experiment|
        execution_stack.push(experiment)

        build_message(:info, context: experiment.log_context?) do
          info = ["Run ID: #{experiment.run_id}"]
          info << "Variant: #{experiment.variant}" if experiment.variant.present?

          "Running #{experiment.name} (#{info.join(", ")})"
        end
      end
    end

    def process_run(event)
      errored = event.payload[:exception_object]
      aborted = !errored && event.payload[:aborted]

      experiment_logger(event) do |experiment|
        execution_stack.pop

        if errored
          build_message(:error) { "Run failed: #{errored.class} (#{errored.message})" }
        elsif aborted
          build_message(:info, details: true) { "Run aborted in #{aborted} callbacks" }
        else
          variant_name = experiment.variant
          if experiment.variant_names.include?(variant_name)
            build_message(:info, details: true) { "Completed running #{experiment.variant} variant" }
          elsif variant_name.present?
            build_message(:error, details: true) { "Run errored: unknown `#{variant_name}` variant resolved" }
          else
            build_message(:error, details: true) { "Run errored: no variant resolved" }
          end
        end
      end
    end

    def process_segment_callbacks(event)
      return if event.payload[:exception_object].present?

      experiment_logger(event) do |experiment|
        if event.payload[:aborted] == :segment
          build_message(:info, duration: true) { "Segmented into the `#{experiment.variant}` variant" }
        else
          build_callback_message(event)
        end
      end
    end

    def process_run_callbacks(event)
      experiment_logger(event) { build_callback_message(event) }
    end

    def process_variant_callbacks(event)
      experiment_logger(event) { build_callback_message(event) }
    end

    def process_variant_steps(event)
      experiment_logger(event) { build_callback_message(event) }
    end

    private
      def warn_of_nested_experiment(event)
        experiment_logger(event) do
          build_message(:warn) { "Nesting experiment in #{experiment_identifier(execution_stack.last)}" }
        end
      end

      def experiment_logger(event, &block)
        return unless logger.present?

        experiment = event.payload[:experiment]
        result = block.call(experiment)
        return unless result.present?

        level = result[:level]
        return unless logger.public_send(LEVEL_PREDICATES.fetch(level))

        logger.public_send(level) do
          log = +colorized_prefix(experiment)
          log << colorized_message(result[:message].call, level: level)
          log << colorized_duration(event, parens: true) if result[:duration]
          log << colorized_details(event) if result[:details]
          log << colorized_context(experiment) if result[:context]
          log
        end
      end

      def build_message(level, **kws, &message)
        { level: level, message: message, **kws }
      end

      def build_callback_message(event)
        return if event.payload[:exception_object].present?

        variant = event.payload[:variant]
        process = event.name.split(".").first.gsub("process_", "").tr("_", " ")

        if variant.present? && process != "run callbacks"
          build_message(:info, duration: true) { "Resolved `#{variant}` variant in #{process}" }
        elsif process != "variant steps"
          build_message(:debug, duration: true) { "Completed #{process}" }
        end
      end

      def colorized_prefix(experiment)
        color("  #{experiment_identifier(experiment)}  ", GREEN)
      end

      def colorized_message(message, level: :info)
        case level
        when :error
          color(message, RED, bold: true)
        when :warn
          color(message, YELLOW, bold: true)
        else
          message
        end
      end

      def colorized_details(event)
        " (Duration:#{colorized_duration(event, parens: false)} | Allocations: #{event.allocations})"
      end

      def colorized_duration(event, parens: true)
        duration = event.duration.round(1)
        if duration > 1000
          ret = color("#{duration}ms", RED, bold: true)
        elsif duration > 500
          ret = color("#{duration}ms", YELLOW, bold: true)
        else
          ret = "#{duration}ms"
        end

        parens ? " (#{ret})" : " #{ret}"
      end

      def colorized_context(experiment)
        return "" unless experiment.log_context?

        " with context: #{format_context(experiment.context).inspect}"
      end

      def format_context(arg)
        case arg
        when Hash
          arg.transform_values { |value| format_context(value) }
        when Array
          arg.map { |value| format_context(value) }
        when GlobalID::Identification
          arg.to_global_id.to_s rescue arg
        else
          arg
        end
      end

      def experiment_identifier(experiment)
        "#{experiment.class.name}[#{experiment.run_key.slice(0, 8)}]"
      end

      def execution_stack
        ActiveSupport::IsolatedExecutionState[:active_experiment_log_subscriber_execution_stack] ||= []
      end

      def logger
        ActiveExperiment.logger
      end
  end
end

ActiveExperiment::LogSubscriber.attach_to(:active_experiment)
