# frozen_string_literal: true

require "active_support/core_ext/time/calculations"
require "active_support/core_ext/string/filters"

module ActiveExperiment
  # == Lifecycle
  #
  # Concluding an experiment records a given variant won, and from then on that
  # variant will be assigned everyone who encounters the experiment.
  #
  #   MyExperiment.conclude!(variant: :red, notes: "3.2% lift, ran 6 weeks")
  #
  # Nothing about the call sites need to change, and the run blocks that are
  # already there go on rendering the winning variant. Removing the experiment
  # can then happen a file at a time, and rolling the decision back is also
  # possible via:
  #
  #   MyExperiment.reopen!
  #
  # An experiment can also be archived, which keeps it out of the way without
  # changing what it assigns:
  #
  #   MyExperiment.archive!
  #
  # == Lifecycle Requires a Recorder
  #
  # State is stored with the rest of what's recorded about an experiment, so
  # these methods need a recorder configured -- see
  # ActiveExperiment::Recording. The default, `NullRecorder`, doesn't support
  # lifecycles.
  #
  # == Reading State Back
  #
  # State is read through the recorder and held for
  # +lifecycle_refresh_interval+ seconds per process, so most runs only cost a
  # hash lookup, and a conclusion reaches every process within approximately
  # that interval. Every experiment sharing a recorder shares the lookup, so
  # it's one query per process rather than one per experiment.
  #
  # A process can be told to look again immediately:
  #
  #   MyExperiment.refresh_lifecycle!
  #
  module Lifecycle
    extend ActiveSupport::Concern

    # Archiving doesn't change what an experiment assigns, so there are only
    # two behaviors here. The state is there so experiments nobody runs
    # anymore can be kept out of the way.
    STATES = [:running, :concluded, :archived].freeze

    included do
      class_attribute :lifecycle_refresh_interval,
        instance_writer: false, instance_predicate: false, default: 60
    end

    module ClassMethods
      # The recorded state, or +:running+ if nothing has been written for it.
      def state
        lifecycle_record&.fetch(:state, nil) || :running
      end

      def concluded?
        state == :concluded
      end

      def archived?
        state == :archived
      end

      # The variant a concluded experiment assigns to everyone. +nil+ unless
      # the experiment has been concluded.
      def winning_variant
        record = lifecycle_record
        return nil unless record && record[:state] == :concluded

        record[:winning_variant]
      end

      # Concludes the experiment, and starts assigning +variant+ to every
      # context.
      #
      # Raises an +ArgumentError+ if the variant isn't registered, and an
      # +ExecutionError+ if there's no recorder to write the decision to.
      def conclude!(variant:, notes: nil)
        variant = variant.to_sym
        raise ArgumentError, "Unknown #{variant.inspect} variant" unless variants[variant]

        write_lifecycle(
          state: "concluded",
          winning_variant: variant.to_s,
          concluded_at: Time.current,
          notes: notes
        )
      end

      # Puts a concluded or archived experiment back to running, so it resolves
      # variants the way it did before.
      def reopen!
        write_lifecycle(state: "running", winning_variant: nil, concluded_at: nil)
      end

      # Marks the experiment as one nobody runs any more, without changing what
      # it assigns.
      def archive!(notes: nil)
        write_lifecycle(state: "archived", notes: notes)
      end

      # Drops this process's copy of the state, so the next read goes back to
      # the recorder. Mostly useful in tests, or right after concluding from a
      # console.
      def refresh_lifecycle!
        recorder.expire_recorded_state!
        self
      end

      private
        def lifecycle_record
          # This is on the path of every run, and the null recorder has
          # nothing to answer with, so an experiment that isn't being recorded
          # returns early.
          return nil unless recorder.recording?

          recorder.recorded_state(experiment_name, lifecycle_refresh_interval)
        end

        def write_lifecycle(**attributes)
          unless recorder.recording?
            raise ExecutionError, <<~MESSAGE.squish
              #{name} has no recorder to write its state to, so there's nowhere
              to record that it ended. Configure one with
              `config.active_experiment.default_recorder = :active_record`, or
              `use_recorder :active_record` on the experiment.
            MESSAGE
          end

          recorder.update_experiment(experiment_name, **attributes)
          refresh_lifecycle!
        end
    end

    private
      # The variant a concluded experiment assigns, or +nil+ when the experiment
      # isn't concluded.
      #
      # If the winning variant isn't registered any more then the class has
      # been edited since it was concluded, so it gets ignored. Assigning a
      # variant that doesn't exist would leave the run with no steps to call.
      def concluded_variant
        # Coerced, because a recorder that hands back a string would otherwise
        # look exactly like an experiment whose winning variant has been
        # removed, and fall through to the rollout without saying why.
        winner = self.class.winning_variant&.to_sym

        winner if winner && variants[winner]
      end
  end
end
