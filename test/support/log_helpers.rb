# frozen_string_literal: true

module LogHelpers
  def capture_logger(with_subscriber: TestLogSubscriber, logger: nil, level: 0, &block)
    old_logger = ActiveExperiment.logger
    ActiveExperiment.logger = logger.nil? ? ActiveSupport::TaggedLogging.new(TestLogger.new(level: level)) : logger
    ActiveExperiment::LogSubscriber.detach_from(:active_experiment)
    with_subscriber.attach_to(:active_experiment, inherit_all: true) if with_subscriber
    SecureRandom.stub(:uuid, "1fbde0db") do
      block.call(ActiveExperiment.logger)
    end
  ensure
    ActiveExperiment.logger = old_logger
    ActiveExperiment::LogSubscriber.attach_to(:active_experiment)
    with_subscriber.detach_from(:active_experiment) if with_subscriber
  end

  class TestLogger < ::ActiveSupport::Logger
    def initialize(...)
      @file = StringIO.new
      super(@file, ...)
    end

    def messages
      @file.rewind
      @file.read
    end
  end

  class TestLogSubscriber < ActiveExperiment::LogSubscriber
    private
      def log_exception(name, exception)
        super(name, RuntimeError.new(exception.message))
      end

      def colorized_prefix(experiment)
        super.gsub(/\s+\w+::/, "").gsub(/\[\w+\]/, "[key]")
      end

      def colorized_duration(event, parens: false)
        duration = event.payload[:experiment].context.try(:dig, :duration)
        return super.gsub(/\d+\.\d+/, "0.0") unless duration

        event.stub(:duration, event.payload[:experiment].context[:duration]) do
          super
        end
      end

      def colorized_details(event)
        super.gsub(/Allocations: \d+/, "Allocations: 0")
      end

      def colorize_logging
        false
      end
  end
end
