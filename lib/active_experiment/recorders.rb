# frozen_string_literal: true

module ActiveExperiment
  # == Recorders
  #
  # Read more about recording in ActiveExperiment::Recording
  #
  module Recorders
    extend ActiveSupport::Autoload

    autoload :BaseRecorder
    autoload :NullRecorder

    RECORDER_SUFFIX = "Recorder"
    private_constant :RECORDER_SUFFIX

    NAME_SUFFIX = "_recorder"
    private_constant :NAME_SUFFIX

    # Allows looking up a recorder by name.
    #
    # The suffix is optional, so +:null+ and +:null_recorder+ both resolve to
    # +NullRecorder+.
    #
    # Constants are looked up on this module only, so an unrelated +FooRecorder+
    # defined elsewhere in an application can't answer +lookup(:foo)+ -- the
    # same restriction rollouts have.
    #
    # Raises an +ArgumentError+ if the recorder isn't found.
    def self.lookup(name, *args, **options)
      class_name = "#{name.to_s.delete_suffix(NAME_SUFFIX).camelize}#{RECORDER_SUFFIX}"

      const_get(class_name, false).new(*args, **options)
    rescue NameError
      raise ArgumentError, "No recorder found for #{name.inspect}"
    end
  end
end
