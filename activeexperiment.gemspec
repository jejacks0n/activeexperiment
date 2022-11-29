# frozen_string_literal: true

begin
  version = File.read(File.expand_path("../RAILS_VERSION", __dir__)).strip
rescue Errno::ENOENT
  require_relative "lib/active_experiment/version"
  version = ActiveExperiment.version
end

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = "activeexperiment"
  s.version     = version
  s.summary     = "Experiment framework with pluggable rollouts and instrumentation."
  s.description = "Declare experiments using classes that can be run in different layers of an application."

  s.required_ruby_version = ">= 2.7.0"

  s.license = "MIT"

  s.author   = "Jeremy Jackson"
  s.email    = "jejacks0n@gmail.com"
  s.homepage = "https://github.com/jejacks0n/active_experiment"

  s.files        = Dir["CHANGELOG.md", "MIT-LICENSE", "README.md", "lib/**/*"]
  s.require_path = "lib"

  s.metadata = {
    "homepage_uri"      => s.homepage,
    "source_code_uri"   => s.homepage,
    "bug_tracker_uri"   => s.homepage + "/issues",
    "changelog_uri"     => s.homepage + "/CHANGELOG.md",
    "documentation_uri" => s.homepage + "/README.md",
    "rubygems_mfa_required" => "true",
  }

  s.add_dependency "activesupport", ">= 7.0.4" # TODO: use `version` here
  s.add_dependency "globalid", ">= 0.3.6"
end
