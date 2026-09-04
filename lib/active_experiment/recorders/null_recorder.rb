# frozen_string_literal: true

module ActiveExperiment
  module Recorders
    # == Null Recorder
    #
    # The default recorder. Recording means writing experiment activity to a
    # datastore that has to be migrated and cleaned up, so it's something an
    # application has to opt into.
    #
    # It's also what an experiment that shouldn't be recorded uses:
    #
    #   class MyExperiment < ActiveExperiment::Base
    #     use_recorder :null_recorder
    #   end
    #
    # Nothing is buffered and nothing is written, and +recording?+ is +false+ so
    # that callers skip building anything to hand it in the first place.
    class NullRecorder < BaseRecorder
      def recording?
        false
      end

      def record_run(experiment, errored: false)
      end

      def record_overlap(experiments)
      end

      def flush!
        false
      end
    end
  end
end
