# Active Experiment – Decide what to do next

Active Experiment is a framework for declaring experiments and allowing them to run using a variety of rollout strategies and/or services. It is designed to be used in a variety of ways, and to be as flexible but as consistent as possible.

Experiments can be everything from determining which query has the best performance, to which feature gets the most engagement, to rolling out a new version of a service. In the most simplistic usage, experiments can function as feature flags.

The main point is to ensure that all Rails apps will have a consistent way to implement feature flags, experiments, and to allow for easy integration with other services through gems that define rollout logic and reporting implementations.

## Usage

Declare an experiment like so:

```ruby
class MyExperiment < ActiveExperiment::Base
  control { "control" } # Control is a convention that means the default behavior.
  variant(:red) { "red" }
  variant(:blue) { "blue" }
end
```

Run the experiment, with a context:

```ruby
MyExperiment.run(current_user)
```

Use local scope to override default variant behavior:

```ruby
MyExperiment.run(current_user) do |experiment|
  experiment.on(:red) { render partial: "red_pill_button" }
  experiment.on(:blue) { render partial: "blue_pill_button" }
end
```

Run the experiment, assigning a specific variant:

```ruby
MyExperiment.set(variant: :red).run(current_user)
```

That's it!

## Custom rollouts

Custom rollouts can be registered. Rollouts generally only need to implement two methods to be considered valid, which can be easily achieved by inheriting the base class. To illustrate, here's a rollout that's based on a fictional feature flag library that assigns a random variant.

```ruby
class FeatureFlagRollout < ActiveExperiment::Rollouts::BaseRollout
  def enabled_for(experiment)
    FeatureFlag.enabled?(@rollout_options[:flag_name] || experiment.name)
  end

  def variant_for(experiment)
    experiment.variant_names.sample
  end
end

ActiveExperiment::Rollouts.register(:feature_flag, FeatureFlagRollout)
```

This `FeatureFlagRollout` can now be used the same way the built-in rollouts are. They can be used in the experiment definition:

```ruby
class MyExperiment < ActiveExperiment::Base
  control { }
  variant(:treatment) { }

  # Using the custom rollout with options.
  rollout :feature_flag, flag_name: "my_feature_flag"
end
```

They can be configured as the default rollout for all experiments:

```ruby
ActiveExperiment::Base.default_rollout = :feature_flag
```

Custom experiments can even be registered to use autoloading. If the custom rollout is defined `lib/feature_flag_rollout.rb`, it can registered by providing the file path instead of a class, and it will only be loaded when needed.

```ruby
ActiveExperiment::Rollouts.register(
  :feature_flag, 
  Rails.root.join("lib/feature_flag_rollout.rb")
)
```

## GlobalID support

Active Experiment supports [GlobalID serialization](https://github.com/rails/globalid/) for experiment contexts. This is part of what makes it possible to utilize Active Record objects as context to consistently assign the same variant across multiple runs.

## Download and installation

When using the gem in Rails, simply add this line to your application's Gemfile:

```ruby
gem "activeexperiment", github: "jejacks0n/active_experiment", require: "active_experiment/railtie"
```

The latest version of Active Experiment can be installed with RubyGems:

```
  $ gem install activeexperiment
```

Source code can be downloaded as part of the Rails project on GitHub:

* https://github.com/jejacks0n/activeexperiment


## License

Active Experiment is released under the MIT license:

* https://opensource.org/licenses/MIT

## Things that should be finished up

The library is generally in a usable state, but there are a few things that should be finished up:

- Release the gem.
- Test against rails main (there's some deprecations and I'm not sure it works yet).
- Finish adding test helpers and a base test case for experiments.
- Finish the redis hash cache store implementation.
- Write tests to cover the generator and railtie.
- Write a complex custom rollout implementation with its own log subscriber.
  - Consider using unleash or launchdarkly as an example?
  - Include details to understand variant resolution lifecycle.
    - assigned before run
    - set in the run block
    - set in run callbacks (before and around)
    - resolved through the cache
    - resolved through segment rules
    - resolved through the rollout
    - was the variant cached?
