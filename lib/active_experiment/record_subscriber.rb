# frozen_string_literal: true

require "active_support/subscriber"

module ActiveExperiment
  # == Record Subscriber
  #
  # Hands a finished experiment run to the experiment's recorder.
  #
  # This is a subscriber that listens to +process_run+, so handles runs that
  # were skipped and runs that raised.
  #
  # It's attached whenever Active Experiment is loaded, and does nothing until
  # a recorder is configured.
  class RecordSubscriber < ActiveSupport::Subscriber
    def process_run(event)
      experiment = event.payload[:experiment]
      recorder = experiment.class.recorder
      return unless recorder&.recording?

      recorder.record_run(experiment, errored: event.payload[:exception_object].present?)
    end
  end
end

ActiveExperiment::RecordSubscriber.attach_to(:active_experiment)
