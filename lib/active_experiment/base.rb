# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors"
require "active_experiment"
require "active_experiment/log_subscriber"
require "active_experiment/core"
require "active_experiment/caching"
require "active_experiment/callbacks"
require "active_experiment/execution"
require "active_experiment/instrumentation"
require "active_experiment/logging"
require "active_experiment/rollout"
require "active_experiment/run_key"
require "active_experiment/segments"
require "active_experiment/variants"

module ActiveExperiment
  # = Active Experiment
  #
  # Active Experiment is a library that helps with defining, running, and
  # reporting on experiments.
  #
  # In general terms, defining an experiment is done by subclassing
  # +ActiveExperiment::Base+ and using the +control+ and +variant+ methods to
  # register the variants of the experiment. Variants are the names of the code
  # paths that will deviate from one another.
  #
  # An example of an experiment definition might look like:
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     control { }
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #   end
  #
  # The term "control" is used to refer to the default variant, or when no
  # other variant is assigned. Calling it the control is largely a convention
  # and is not enforced by the library.
  #
  # Once an experiment has been defined, it can be run in various areas of an
  # application. When running an experiment, variants can be overridden, which
  # allows utilizing the scope and helpers available where the experiment is
  # being run.
  #
  # For instance, within a view it can be useful to render different partials:
  #
  #   MyExperiment.run(current_user) do |experiment|
  #     experiment.on(:red) { render partial: "red" }
  #     experiment.on(:blue) { render partial: "blue" }
  #   end
  #
  # Or within a controller, it can be useful to redirect to different paths:
  #
  #   MyExperiment.run(current_user) do |experiment|
  #     experiment.on(:red) { redirect_to red_path }
  #     experiment.on(:blue) { redirect_to blue_path }
  #   end
  #
  # This approach allows for the same experiment to be run in different areas
  # of an application, with consistent variant assignment, even if the
  # experimental behavior is different in different parts of the application.
  class Base
    include Core
    include Caching
    include Callbacks
    include Execution
    include Instrumentation
    include Logging
    include Rollout
    include RunKey
    include Segments
    include Variants

    ActiveSupport.run_load_hooks(:active_experiment, self)
  end
end
