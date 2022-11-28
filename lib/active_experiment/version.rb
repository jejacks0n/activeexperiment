# frozen_string_literal: true

require_relative "gem_version"

module ActiveExperiment
  # Returns the currently loaded version of Active Experiment as a
  # +Gem::Version+.
  def self.version
    gem_version
  end
end
