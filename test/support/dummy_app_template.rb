# frozen_string_literal: true

initializer "custom_rollouts.rb", <<-RUBY
require "active_experiment" # only needed for the test environment

ActiveExperiment::Rollouts.register :red, Rails.root.join("lib/red_rollout.rb")
ActiveExperiment::Rollouts.register :blue, Class.new(ActiveExperiment::Rollouts::BaseRollout) do
  def resolve_variant_for(*)
    :blue  
  end
end
RUBY

file "lib/red_rollout.rb", <<-RUBY
class RedRollout < ActiveExperiment::Rollouts::BaseRollout
  def resolve_variant_for(*)
    :red  
  end
end
RUBY
