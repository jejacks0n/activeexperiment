# Active Experiment – Decide what to do next

[![Gem Version](https://badge.fury.io/rb/activeexperiment.svg)](https://badge.fury.io/rb/activeexperiment)
[![License](https://img.shields.io/badge/license-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Maintainability](https://api.codeclimate.com/v1/badges/551c00c66f8558c7a01b/maintainability)](https://codeclimate.com/github/jejacks0n/active_experiment/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/551c00c66f8558c7a01b/test_coverage)](https://codeclimate.com/github/jejacks0n/active_experiment/test_coverage)

Active Experiment is a framework for defining and running experiments. It supports using a variety of rollout and reporting strategies and/or services.

Experiments can be everything from determining which query has the best performance, to which feature gets the most engagement, to rolling out a canary version of a new api service.

Experimentation is complex. There are a lot of different ways to run experiments, and even more ways to report on them. Active Experiment is designed to be flexible enough to support a variety of use cases, but also to be consistent and easy to use.

## Usage

Define your experiments using easily testable classes:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }
end
```

This experiment can be generated using the Rails generator:

```bash
rails generate experiment my_experiment red blue
```

Run the experiment with a context, like the current user, or the post being rendered:

```ruby
MyExperiment.run(current_user) # => "red" or "blue"
```

Optionally override the defaults using local scope and helpers:

```ruby
MyExperiment.run(current_user) do |experiment|
  experiment.on(:red) { redirect_to red_path }
  experiment.on(:blue) { redirect_to blue_path }
end
```

That's it! When this experiment is encountered by different users, half<sup>&#8224;</sup> will get the red variant, half will get the blue variant, and each will always get the same.

<small>&#8224; roughly half, for the statistically pedantic.</small> 

## Download and Installation

Add this line to your Gemfile:

```ruby
gem "activeexperiment"
```

Or install the latest version with RubyGems:

```bash
gem install activeexperiment
```

Source code can be downloaded as part of the project on GitHub:

* https://github.com/jejacks0n/active_experiment

Adapters can be added to integrate with various services:

- [Unleash adapter](https://github.com/jejacks0n/activeexperiment-unleash) 

## Advanced Experimentation

This area provides a high level overview of the tools that more complex experiments can benefit from.

For example, some experiments need to define a default variant (also known as a _control_) that will be assigned if the experiment is skipped:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  # The term control is simply a convention that means the default variant, and
  # any variant can be set as the default with +use_default_variant(:red)+
  control { "default" }
end
```

Callbacks can be used to hook into the lifecycle when experiments are run, and can be targeted to when a specific variant has been assigned:

```ruby
class MyExperiment < ActiveExperiment::Base
  control { "default" }
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  # Skipping an experiment will always assign the default variant, which could
  # be nothing, but since there's a control defined, it will be used.
  before_run { skip if context.admin? }
  
  # Only invoked when the red variant has been assigned.
  before_variant(:red) { puts "running the red variant" }
  
  # Maybe there's cleanup or logging to do afterwards?
  after_run { puts "run complete with the #{variant} variant" unless skipped? }
end
```

Segment rules can be used to assign specific variants for certain cases:

```ruby
class MyExperiment < ActiveExperiment::Base
  control { "default" }
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  segment :admins, into: :red
  segment :old_accounts, into: :control
  
  private
  
  def admins
    context.admin?
  end

  def old_accounts
    context.created_at < 1.year.ago
  end
end
```

## Rollouts

Rollouts are a core concept in Active Experiment. They allow specifying how an experiment should be rolled out, and even if it should be skipped or not. For example, the default rollout in Active Experiment is percentage based and accepts distribution rules -- if no rules are provided, even distribution is used.

A rollout can implement any number of different strategies, interact with services, and can be used on a per-experiment basis.

Here's an example of using the default percent rollout with custom distribution rules:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }
  variant(:green) { "green" }

  # Will assign the green variant 80% of the time, red and blue 10% each.
  use_rollout :percent, rules: { red: 10, blue: 10, green: 80 }
end
```

### Defining Custom Rollouts

Project specific rollouts can be defined and registered too. To illustrate, here's a custom rollout that inherits from the base rollout, uses a fictional feature flag library, and assigns a random variant.

```ruby
class FeatureFlagRollout < ActiveExperiment::Rollouts::BaseRollout
  register_as :feature_flag

  def skipped_for(experiment)
    !Feature.enabled?(@rollout_options[:flag_name] || experiment.name)
  end

  def variant_for(experiment)
    experiment.variant_names.sample
  end
end
```

This rollout can now be used the same way the built-in rollouts are:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  # Using a custom rollout with options.
  use_rollout :feature_flag, flag_name: "my_feature_flag"
end
```

Custom rollouts can be registered to autoload as well, so they're only loaded when needed:

```ruby
ActiveExperiment::Rollouts.register(
  :feature_flag, 
  "lib/feature_flag_rollout.rb"
)
```

There's a world of flexibility with custom rollouts. One creative and simple rollout concept is to use the experiment itself:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  def self.skipped_for(*)
    false
  end

  def self.variant_for(*)
    variant_names.sample
  end
  
  use_rollout self
end
```

## Reporting

Reporting is a core concept in Active Experiment. It allows for collecting data about experiments and variants, and can be used to track performance metrics, analyze results, and more.

Some simple reporting strategies might simply be added to `after_run` callbacks, but more complex reporting strategies can be implemented using a subscriber.

A subscriber can be used to listen for experiment events and report them to a service. For example, here's a subscriber that reports to a fictional analytics service:

```ruby
class MyAnalyticsSubscriber < ActiveSupport::Subscriber
  attach_to :active_experiment

  def process_run(event)
    experiment = event.payload[:experiment]
    return if experiment.skipped?

    Analytics.report(
      experiment.serialize,
      error: event.payload[:exception_object]
    )
  end
end
```

The following Active Experiment events are available for subscribers:

- `start_experiment` - The experiment has begun.
- `process_segment_callbacks` - The experiment has processed all segment rules. A variant may have been resolved through this step.
- `process_variant_steps` - An experiment variant has been run.
- `process_variant_callbacks` - The experiment has processed variant callbacks.
- `process_run_callbacks` - The experiment has processed run callbacks.
- `process_run` - The experiment has completed and can be reported on.

In each of these events, the experiment instance is available in the `event.payload` hash.

## Experiments in Views

Experiments can be used in views, just like in any other part of your application. Sometimes though, you might want to render markup inside your run block too, and to do this, you'll need to "capture" the experiment.

To accomplish this, you can ask the experiment to capture itself by providing the view scope. The following examples (HAML or ERB) help illustrate how to avoid duplicating markup within each variant block by putting it (the container div for instance) in the run block.

Remember to include the `ActiveExperiment::Capturable` module in your experiment class:

```ruby
class MyExperiment < ActiveExperiment::Base
  include ActiveExperiment::Capturable
  
  variant(:red) { "red" }
  variant(:blue) { "blue" }
end
```

<details>
<summary>Expand HAML example</summary>

```haml
!= MyExperiment.set(capture: self).run(current_user) do |experiment|
  %div.container
    = experiment.on(:red) do
      %button.red-pill Red
    = experiment.on(:blue) do
      %button.blue-pill Blue
```
</details>

<details>
<summary>Expand ERB example</summary>

```erb
<%== MyExperiment.set(capture: self).run(current_user) do |experiment| %>
  <div class="container">
    <%= experiment.on(:red) do %>
      <button class="red-pill">Red</button>
    <% end %>
    <%= experiment.on(:blue) do %>
      <button class="blue-pill">Blue</button>
    <% end %>
  </div>
<% end %>
```
</details>

If you don't need to capture the experiment, simply run like you would anywhere else:

```erb
<% MyExperiment.run(current_user) do |experiment| %>
  <% experiment.on(:red) do %>
    <button class="red-pill">Red</button>
  <% end %>
  <% experiment.on(:blue) do %>
    <button class="blue-pill">Blue</button>
  <% end %>
<% end %>
```

## Client Side Experimentation

While Active Experiment doesn't include any specific tooling for client side experimentation at this time, it does provide the ability to surface experiments in the client layer.

Whenever an experiment is run in the request lifecycle, it's stored so it can be provided to the client. This means that if an experiment is run in controller, a view, a helper, etc. it will be available to the client.

In the layout, the experiment data can be rendered as JSON for instance:

```erb
<title>My App</title>
<script>
  window.experiments = <%== ActiveExperiment::Executed.to_json %>
</script>
```

Or each experiment can be iterated over and rendered individually:

```erb
<% ActiveExperiment::Executed.as_array.each do |experiment| %>
  <meta name="<%= experiment.name %>" content="<%== experiment.serialize.to_json %>">
<% end %>
```

## Testing

Active Experiment provides a test helper that can be used to stub experiments and assert that the expected experiments have been run.

To use the test helper, include it in your test case:

```ruby
class MyTestCase < ActiveSupport::TestCase
  include ActiveExperiment::TestHelper
end
```

Now you can stub experiments in your tests:

```ruby
test "stubbing experiments" do
  stub_experiment(MyExperiment, :red) do
    # Now all MyExperiment experiments will assign the :red variant.
  end

  stub_experiment(MyExperiment, skip: true) do
    # Now all MyExperiment experiments will be skipped.
  end
end
```

Assertion helpers are also available:

```ruby
test "asserting experiments" do
  # Assert that no experiments have been run.
  assert_no_experiments

  MyExperiment.run(id: 1)

  # Assert that 1 experiment has been run.
  assert_experiments 1

  # Assert that within the block, 2 experiments will be run.
  assert_experiments 2 do
    MyExperiment.run(id: 2)
    MyExperiment.run(id: 3)
  end
  
  # Assert an experiment has been run with a given context.
  assert_experiment_with(MyExperiment, context: { id: 1 })
  
  # Assert that within the block, a matching experiment will be run.
  assert_experiment_with(MyExperiment, variant: :red, context: { id: 4 }) do
    MyExperiment.set(variant: :red).run(id: 4)
  end
end
```

RSpec support can be added by requiring `active_experiment/rspec` in the appropriate spec helper.

## GlobalID support

Active Experiment supports [GlobalID serialization](https://github.com/rails/globalid/) for experiment contexts. This is part of what makes it possible to utilize Active Record objects as context to consistently assign the same variant across multiple runs.

## License

Active Experiment is released under the MIT license:

* https://opensource.org/licenses/MIT

Copyright 2022 [jejacks0n](https://github.com/jejacks0n)

## Make Code Not War
