# frozen_string_literal: true

# Off by default outside development, and the railtie only registers the
# experiment tagging when it's on.
environment "config.active_record.query_log_tags_enabled = true"

initializer "custom_rollouts.rb", <<-RUBY
require "active_experiment" # only needed for the test environment

ActiveExperiment::Rollouts.register :red, Rails.root.join("lib/red_rollout.rb")
# Use braces -- a do/end block binds to `register` rather than to `Class.new`,
# leaving a bare BaseRollout that assigns the first variant instead of :blue.
ActiveExperiment::Rollouts.register :blue, Class.new(ActiveExperiment::Rollouts::BaseRollout) {
  def variant_for(*)
    :blue
  end
}
RUBY

file "lib/red_rollout.rb", <<-RUBY
class RedRollout < ActiveExperiment::Rollouts::BaseRollout
  def variant_for(*)
    :red
  end
end
RUBY

# Turn reloading on for the dummy environment so we can test hot reloading.
gsub_file "config/environments/test.rb",
  "config.enable_reloading = false", "config.enable_reloading = true"

# This represents a rollout that lives in app/, so Zeitwerk manages it.
# A dev reload should reload this. It's registered by name from the
# initializer that's below.
file "app/rollouts/reloadable_rollout.rb", <<-RUBY
class ReloadableRollout < ActiveExperiment::Rollouts::BaseRollout
  def variant_for(*)
    :red
  end
end
RUBY

initializer "reloadable_rollout.rb", <<-RUBY
ActiveExperiment::Rollouts.register :reloadable, "ReloadableRollout"
RUBY

# The same thing through the application config, which is the other place a
# rollout can be named without needing it loaded.
file "app/rollouts/configured_rollout.rb", <<-RUBY
class ConfiguredRollout < ActiveExperiment::Rollouts::BaseRollout
  def variant_for(*)
    :blue
  end
end
RUBY

environment 'config.active_experiment.custom_rollouts = { configured: "ConfiguredRollout" }'

# Configured through the application config rather than on the class, to check
# the railtie resolves it the way `default_cache_store =` does directly.
environment "config.active_experiment.default_cache_store = :memory_store"
