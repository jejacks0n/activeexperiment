# frozen_string_literal: true

module ActiveExperiment
  # == Recording
  #
  # Recorders allow reporting on the recorded data of experiments. They record
  # the results of an experiment run so that data can then be reported on.
  #
  # Nothing is recorded by default. The default is the +:null_recorder+, which
  # does nothing, so adding the library doesn't add a datastore to migrate and
  # clean up.
  #
  # == Turning It On
  #
  # Recording can be configured globally, and per experiment, the same way
  # cache stores are configured.
  #
  #   ActiveExperiment::Base.default_recorder = :active_record
  #   Rails.application.config.active_experiment.default_recorder = :active_record
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     use_recorder :active_record
  #   end
  #
  # Unlike rollouts, recorders are inherited. An experiment that shouldn't be
  # recorded can opt out with +use_recorder :null_recorder+.
  #
  # == What Gets Recorded
  #
  # * A registry entry per experiment. This includes the variants it has
  #   defined, the rollout it uses, the cache store, and when it was first
  #   and last seen being run.
  # * Daily rollups per variant. This allows us to see how many runs, how
  #   many were skipped, how many runs raised exceptions, and how the variant
  #   came to be assigned.
  # * Overlaps. Experiments can overlap and be nested, so this allows us to
  #   see how often two experiments were run together, per pair of variants,
  #   and how often one was nested inside the other.
  #
  # Experiment runs are recorded by ActiveExperiment::RecordSubscriber, which
  # listens to the same events any reporting subscriber would.
  #
  # == Reading It Back
  #
  # A recorder answers +experiments+, +experiment+, +rollups+ and +overlaps+.
  #
  #   MyExperiment.recorder.rollups("my_experiment", since: 2.weeks.ago.to_date)
  module Recording
    extend ActiveSupport::Concern

    # Holds the guard below. +class_attribute+ defines its writer straight onto
    # the singleton class, so overriding it means getting ahead of that rather
    # than defining a method in +ClassMethods+, which lands behind it.
    module RecorderAssignment # :nodoc:
      def recorder=(recorder)
        if recorder.is_a?(Symbol) || recorder.is_a?(String)
          raise ArgumentError, <<~MESSAGE.squish
            Assign a recorder rather than the name of one -- this attribute
            holds the recorder itself. Use
            `default_recorder = #{recorder.inspect}` to look one up, or
            `use_recorder #{recorder.inspect}` within an experiment.
          MESSAGE
        end

        super
      end
    end

    included do
      class_attribute :recorder, instance_writer: false, instance_predicate: false
      singleton_class.prepend(RecorderAssignment)

      self.default_recorder = :null_recorder
    end

    # Records the experiments that were run together.
    #
    # Called with everything ActiveExperiment::Executed collected, which is
    # every experiment that ran during a request or a job. Overlap is a
    # property of the set rather than of any one experiment in it, so the whole
    # set goes to each distinct recorder the set uses -- normally exactly one.
    def self.record_executed(experiments)
      return unless experiments && experiments.length > 1

      recorders = experiments.filter_map { |experiment| experiment.class.try(:recorder) }.uniq
      recorders.each do |recorder|
        recorder.record_overlap(experiments) if recorder.recording?
      end
    end

    module ClassMethods
      # Sets the recorder used by experiments that don't specify one.
      def default_recorder=(name_or_recorder)
        use_recorder(name_or_recorder)
      end

      private
        def use_recorder(name_or_recorder, *args, **kws)
          case name_or_recorder
          when Symbol, String
            self.recorder = ActiveExperiment::Recorders.lookup(name_or_recorder, *args, **kws)
          else
            self.recorder = name_or_recorder
          end
        end
    end
  end
end
