# frozen_string_literal: true

# This is an example of how to define an entire ActiveExperiment adapter layer.
#
# The concepts here are to define a rollout, and a log subscriber to utilize
# all of the functionality that ActiveExperiment provides.
#
#
#

module FlipperActiveExperimentAdapter
  class Rollout < ActiveExperiment::Rollouts::PercentRollout
    def enabled_for(experiment)
      Flipper.enabled?(experiment.name, experiment.context)
    end
  end

  ActiveExperiment::Rollouts.register(:flipper, Rollout)
  ActiveExperiment::Base.default_rollout = :flipper

  class EventSubscriber < ActiveSupport::LogSubscriber
    def run(event)
      return if event.payload[:exception_object]
      experiment = event.payload[:experiment]

      build_message(:info, "Completed running #{experiment.variant} variant", details: true)
    end
  end

  LogSubscriber.attach_to :active_experiment
end
