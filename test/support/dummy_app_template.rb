# frozen_string_literal: true

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
