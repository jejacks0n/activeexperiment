# frozen_string_literal: true

module ActiveExperiment
  # == Logging Module
  #
  # Within experiments, you can log information about the experiment. This can
  # be done by simply calling +logger+ within the experiment definition. By
  # default the logger will be tagged with "ActiveExperiment" to help identify
  # where the log message is coming from.
  #
  # The logger can also be tagged, and then used from within a block. The tag
  # will be removed after the block has been executed.
  #
  # For instance, an experiment could implement tag the logger like this when
  # run:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     around_run(prepend: true) do |_, block|
  #       tag_logger("MyExperiment", "run", &block)
  #     end
  #   end
  #
  # Any logging that occurs within this experiment, while it's being run, will
  # be tagged with "MyExperiment" and "run". Those log lines might look like:
  #
  #   "[ActiveExperiment] [MyExperiment] [run] Experiment started..."
  #
  # The +log_context+ class attribute is used as configuration within the
  # +ActiveExperiment::LogSubscriber+. For some experiments that contain
  # sensitive information, it might be useful to not log the context. This can
  # be done by setting that experiment class's +log_context+ to false.
  #
  # More logging details can be found in the +ActiveExperiment::LogSubscriber+.
  module Logging # :nodoc:
    extend ActiveSupport::Concern

    TAG_NAME = "ActiveExperiment"
    private_constant :TAG_NAME

    included do
      class_attribute :log_context, instance_predicate: true, default: false
      private :log_context=, :log_context
    end

    # Returns logger that can be used within the experiment.
    #
    # The logger will be tagged with "ActiveExperiment" if possible, to help
    # identify where the log messages are coming from.
    def logger
      @logger ||= ActiveExperiment.logger.try(:tagged, TAG_NAME) || ActiveExperiment.logger
    end

    private
      def tag_logger(*tags, &block)
        if logger.respond_to?(:tagged)
          logger.tagged(*tags, &block)
        else
          yield
        end
      end
  end
end
