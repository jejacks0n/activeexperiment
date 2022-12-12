# frozen_string_literal: true

module ActiveExperiment
  # Returns the currently loaded version of Active Experiment as a
  # +Gem::Version+.
  def self.gem_version
    Gem::Version.new(VERSION::STRING)
  end

  module VERSION
    MAJOR = 0
    MINOR = 1
    TINY  = 1
    PRE   = "alpha"

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join(".")
  end
end
