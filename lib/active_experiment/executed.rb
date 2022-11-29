# frozen_string_literal: true

require "active_support/current_attributes"

module ActiveExperiment
  # == Executed Experiments
  #
  # This is useful for surfacing experiments to the client layer. For example,
  # if you have a client only experiment, an empty experiment can be defined
  # and then run in the controller layer. The client layer can then use the
  # experiment information to render the appropriate client code based on the
  # variant that's been assigned, or other information available the experiment
  # can provide in its +serialize+ method.
  #
  # An example of an empty experiment might be as simple as:
  #
  #   class MyClientExperiment < ActiveExperiment::Base
  #     variant(:red) { }
  #     variant(:blue) { }
  #   end
  #
  # In the controller, this experiment can be run in a before action, or
  # anywhere else that makes sense for your application:
  #
  #   class MyController < ApplicationController
  #     before_action :run_my_client_experiment
  #     # ... controller code
  #
  #     private
  #
  #     def run_my_client_experiment
  #       MyClientExperiment.run(current_user)
  #     end
  #   end
  #
  # Then in the layout, or appropriate view, all experiments that have been run
  # during the request can be surfaced:
  #
  #   <title>My App</title>
  #   <script>
  #     window.experiments = <%= ActiveExperiment::Executed.to_json %>
  #   </script>
  #
  # Or the experiments that have been run can be iterated:
  #
  #   <% ActiveExperiment::Executed.experiments.each do |experiment| %>
  #     <meta name="<%= experiment.name %>" content="<%= experiment.variant %>">
  #   <% end %>
  class Executed < ActiveSupport::CurrentAttributes
    attribute :experiments

    # Interface to add an experiment to the executed experiments. This is
    # intended to be used by the +run+ method of the experiment class.
    #
    # Experiments are added to the executed experiments if they have been
    # assigned a variant.
    def self.<<(experiment)
      self.experiments ||= []
      experiments << experiment
    end

    # Returns a json of the experiments that have been run, with the experiment
    # name as the key, and the serialized experiment as the value. This assumes
    # that if an experiment is run multiple times, the same variant has been
    # assigned for all runs, which may not be true, like when using the random
    # rollout.
    #
    # When needed, the executed experiments can be accessed and/or iterated
    # directly, or the +to_json_array+ method can be used.
    def self.to_json
      experiments.each_with_object({}) { |e, hash| hash[e.name] = e.serialize }.to_json
    end

    # Returns an array of experiments that have been run.
    def self.to_json_array
      experiments.map(&:serialize).to_json
    end
  end
end
