# Active Experiment – Decide what to do next

<img alt="Active Experiment" width="150" height="183" src="https://user-images.githubusercontent.com/13765/208318101-b48c9493-15ed-4a99-b42f-b20720dd7c77.png" align="right" hspace="20">

[![Gem Version](https://badge.fury.io/rb/activeexperiment.svg)](https://badge.fury.io/rb/activeexperiment)
[![License](https://img.shields.io/badge/license-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/jejacks0n/activeexperiment/actions/workflows/ci.yml/badge.svg)](https://github.com/jejacks0n/activeexperiment/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/jejacks0n/activeexperiment/branch/main/graph/badge.svg)](https://codecov.io/gh/jejacks0n/activeexperiment)

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

* https://github.com/jejacks0n/activeexperiment

Two optional parts of Active Experiment can be backed by Active Record. These are two separate and independent features -- [recording](#recording), which tracks experiment data it can be reported on, and [caching](#caching), which keeps variant assignments stable. Both are off by default, until they're configured.

```bash
bin/rails generate active_experiment:install
bin/rails db:migrate
```


If you only want to install the migration for one of the features, you can specify which using flags.

```bash
bin/rails generate active_experiment:install --recorder
bin/rails generate active_experiment:install --cache
```

Adapters can be added to integrate with various services / tooling:

- [Flipper adapter](https://github.com/jejacks0n/activeexperiment-flipper) -- an flipper adapter (doesn't yet exist).
- [Unleash adapter](https://github.com/jejacks0n/activeexperiment-unleash) -- an unleash adapter.

You can visualize and look at experiment data that have been recorded:

- [Dashboard](https://github.com/jejacks0n/activeexperiment-dashboard) -- a mountable engine that lists and displays experiment data.

## Advanced experimentation

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

### Defining custom rollouts

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

Note: `register_as` only takes effect once this file/class has been loaded, which is fine for a rollout that's defined in an initializer or something. In the development environment though, nothing loads it until something references it -- register those by name, as below.

This rollout can now be used the same way the built-in rollouts are:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  # Using a custom rollout with options.
  use_rollout :feature_flag, flag_name: "my_feature_flag"
end
```

Custom rollouts can be registered by name, so they're only loaded when needed:

```ruby
ActiveExperiment::Rollouts.register(:feature_flag, "FeatureFlagRollout")
```

Nothing has to be loaded to register one, so it can go in an initializer -- where autoloading isn't available yet.

Rollouts can also be named in the application config, which is registered on boot:

```ruby
# config/application.rb
config.active_experiment.custom_rollouts = { feature_flag: "FeatureFlagRollout" }
```

A rollout that isn't somewhere Rails autoloads from can be registered with a `Pathname` to it instead:

```ruby
ActiveExperiment::Rollouts.register(
  :feature_flag,
  Rails.root.join("lib/feature_flag_rollout.rb")
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

## Caching

Experiments don't cache by default, so a variant is resolved on every run. That's fine until the answer can change -- a segment rule like `context.created_at < 1.week.ago` puts a subject in one variant this week and another next week. That's when caching the assignment can come in handy, and can keep assignment stable for the life of the experiment.

Set a store on an experiment:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  use_cache_store :redis_hash
end
```

Or for all of them, on the class or through the application config:

```ruby
ActiveExperiment::Base.default_cache_store = :redis_hash
config.active_experiment.default_cache_store = :redis_hash
```

Two cache stores ship with the library: `:redis_hash`, which uses a Redis hash per experiment, and `:active_record`, which needs a table. Use `bin/rails generate active_experiment:install` to get the migration.

Technically any `ActiveSupport::Cache::Store` will work too, as long as it can hold on to entries for as long as the experiment runs.

You can get the size of an experiments cache by asking an experiment that has caching enabled using:

```ruby
MyExperiment.cache_size # => 4211
```

Both of the included cache stores count a single experiment's entries without walking the whole cache. Other stores probably raise an exception, since counting a subset of keys isn't part of the `ActiveSupport::Cache::Store` interface.

When an experiment is over, `clear_cache` removes everything it cached. Passing a batch size deletes in chunks, and yields the size of each chunk along with the running total:

```ruby
MyExperiment.clear_cache
MyExperiment.clear_cache(batch_size: 1_000) do |deleted, total|
  puts "cleared #{total}"
end
```

```bash
bin/rails active_experiment:clear_cache[MyExperiment,1000]
```

The Active Record store can be pointed at a database other than the one `ActiveRecord::Base` is connected to. If you want to store experiment data in a database other than your primary, you can define a model and then use that as your `connection_class`. You can even use this pattern to store each experiments' data in a different table if you wanted to.

```ruby
class CacheRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :experiments }
end

class MyExperiment < ActiveExperiment::Base
  use_cache_store :active_record, connection_class: CacheRecord
end
```

Note: The experiment name is part of the run key and the cache key, so renaming an experiment class generates new run keys and cache keys, orphaning everything already cached for it. If a class has to move mid-experiment, you can keep the old name by specifying the `experiment_name` manually.

```ruby
class NewCheckoutExperiment < ActiveExperiment::Base
  def self.experiment_name
    "checkout_experiment"
  end
end
```

## Recording

Nothing about experiments is recorded by default. The default is the `:null_recorder`, which does nothing, but Active Experiment comes with the ability to record experiment data into Active Record, and is setup so you can write your own recorders if you want to.  

To setup recording into Active Record, create the tables (see [Installation](#download-and-installation)) and configure the default recorder to use it with one of these lines:

```ruby
ActiveExperiment::Base.default_recorder = :active_record
config.active_experiment.default_recorder = :active_record
```

Or per experiment, the same way cache stores are configured:

```ruby
class MyExperiment < ActiveExperiment::Base
  use_recorder :active_record
end
```

An experiment that shouldn't be recorded can opt out with `use_recorder :null_recorder`.

Recorders subscribes to the same events any subscriber would -- `ActiveExperiment::RecordSubscriber` is a simple subscriber next to `ActiveExperiment::LogSubscriber`, and the [Writing a custom recorder](#writing-a-custom-recorder--subscriber) section below covers writing your own.

### What gets recorded

Three things are stored:

- **An entry per experiment** This includes the name of the experiment, the variants it registers, the rollout it uses, the cache store it uses, and when it was first and last seen being run.
- **Daily counts per variant** How many runs, how many runs were skipped, how many raised exceptions, and how the variants came to be assigned.
- **Overlaps** How two experiments that ran together are related, per pair of variants. At depth 0 they simply ran together. Above that one ran inside the other, and the depth is how far apart they were, so depth 1 is the call graph and anything deeper is an experiment that only ran because something further up did.

That last one is worth noting. Two experiments overlapping can be normal. What isn't normal is one experiment's variants being split differently inside each of another's, which means the two are entangled and neither experiment can be evaluated on its own.

### Reading it back

A recorder answers five questions, and returns plain hashes, so something reporting on experiments doesn't have to know which recorder it's talking to:

```ruby
recorder = ActiveExperiment::Base.recorder

recorder.experiments                                          # list of experiments
recorder.experiment("my_experiment")                          # details of an experiment
recorder.rollups("my_experiment", since: 2.weeks.ago.to_date) # daily counts
recorder.overlaps("my_experiment")                            # co-occurrence details
recorder.nestings("my_experiment")                            # what ran inside what
```


### Forgetting an experiment

Under certain circumstances you might have to remove an experiment. You usually don't want to do this, but if you've accidentally recorded data for an experiment, or renamed an experiment and legitimately want to clean up old data, you can run the following:

```ruby
recorder.delete_experiment("my_experiment")
```

```
bin/rails active_experiment:forget[my_experiment]
```               

Overlaps are stored once per pair rather than once per experiment, so forgetting one experiment might also remove a still running experiment's view of that overlap.

Forgetting an experiment removes what was recorded about it, but not the variant assignments it cached. Those are separate:

```
bin/rails active_experiment:clear_cache[my_experiment]
```

This is irreversible, and likely isn't how you want to end an experiment that ran to a conclusion. That history is often worth keeping and can be useful if you want to reopen the experiment.

### Buffering and durability

Counts accumulate in per-process counters and are written in batches, so running an experiment doesn't cost a write. A batch goes out when enough runs have piled up or enough time has passed, both configurable:

```ruby
use_recorder :active_record, flush_interval: 60, flush_threshold: 1_000
```

If your processes are cycled regularly, for example a Heroku dyno restart, or any deploy, you can flush on puma shutdown. How you handle this depends a bit on your deployment strategy though, so this is just an example.

```ruby
# config/puma.rb
on_worker_shutdown { ActiveExperiment::Base.recorder.flush! }
```

`flush!` writes immediately, which you'd also want to do in a test before attempting to read data back.

### Storing it elsewhere

Statements run against `ActiveRecord::Base`'s connection. Since these tables are written to constantly and read from rarely, a busy application may not want them alongside everything else:

```ruby
# config/initializers/active_experiment.rb
ActiveExperiment::Recorders::ActiveRecordRecorder::Record.connects_to(
  database: { writing: :experiments }
)
```

## Ending an experiment

Concluding an experiment allows recording the variant that won. From then on the experiment will assign that variant to everyone, without asking the rollout, segment rules, or its cache:

```ruby
MyExperiment.conclude!(variant: :red, notes: "3.2% lift, ran 6 weeks")
```

Nothing at the call sites changes, and the run blocks already there go on rendering the winning variant. Removing the experiment becomes ordinary cleanup you can do a file at a time, and rolling the decision back is a single call:

```ruby
MyExperiment.reopen!
```

An experiment that's long dead can be archived as well, which keeps it out of the way without changing what it assigns.

```ruby
MyExperiment.archive!
```

These need a recorder, since that's where the state is kept. With the default `:null_recorder` they raise instead of looking like they worked, so [Recording](#recording) has to be configured first.

```bash
bin/rails active_experiment:conclude[MyExperiment,red,"3.2% lift"]
bin/rails active_experiment:reopen[MyExperiment]
bin/rails active_experiment:archive[MyExperiment]
```

Concluding leaves the cached assignments alone, since they're what makes rolling back possible. Clearing them is a separate step, and worth doing in batches for a large experiment, see [Caching](#caching).

State is read through the recorder and held per process, so most runs only cost a hash lookup, and every experiment sharing a recorder shares the lookup. A conclusion reaches other processes within `lifecycle_refresh_interval` seconds, 60 by default. To pick it up immediately in a console, `MyExperiment.refresh_lifecycle!`.

## Explaining an assignment

To ask what an experiment would assign for a context, without assigning it:

```ruby
MyExperiment.explain(current_user)
# => { variant: :red, variant_source: :cached, run_key: "...", ... }
```

Running the experiment to find out would cache the assignment, record the run, and execute whatever the variant does, which in a view means rendering a partial or issuing a redirect. An explanation resolves the variant the same way a run does and then stops, so nothing is cached or recorded, the variant steps aren't called, and the experiment isn't added to `ActiveExperiment::Executed`.

Segment rules do run, and so does the rollout. Both are expected to be free of side effects.

## Writing a custom recorder / subscriber

Custom recorders can be written, for forwarding experiment run data to a metrics service, say -- they don't have to write to a database. You just need to subclass `ActiveExperiment::Recorders::BaseRecorder` and implement `write`; the buffering, flush timing and counting are handled for you.

Being able to answer questions afterwards is optional, so a recorder that only forwards doesn't have to implement the reads.

```ruby
class StatsdRecorder < ActiveExperiment::Recorders::BaseRecorder
  private
    def write(registry, runs, overlaps)
      runs.each do |(experiment, variant, _date), counts|
        StatsD.increment("experiment.runs", by: counts[:runs],
          tags: { experiment: experiment, variant: variant })
      end
    end
end

ActiveExperiment::Base.default_recorder = StatsdRecorder.new
```

`write` is handed everything the process buffered since its last flush, as three hashes:

```
# registry
{ "checkout_experiment" => {
    class_name: "CheckoutExperiment",
    variant_names: [:red, :blue],
    default_variant: :control, rollout: nil,
    cache_store: "ActiveSupport::Cache::NullStore" } }

# runs
{ ["checkout_experiment", "red", Fri, 04 Sep 2026] => {
    runs: 1,
    skipped: 0,
    errored: 0,
    from_preset: 1 } }

# overlaps, keyed by the pair of variants and the depth between them
{ ["banner_experiment", "on", "checkout_experiment", "red", 0] => {
    count: 1 } }
```

Counts are deltas. The `from_*` keys in the runs section say how each variant was decided, and only appear for sources that actually occurred.

In addition to custom recorders, a generic subscriber can be used to listen for experiment events and report them to a service. For example, here's a subscriber that reports to a fictional analytics service:

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

What gets sent is up to the experiment. `serialize` is the payload the example above reports, and it can be overridden to add whatever the reporting side needs to join on:

```ruby
class MyExperiment < ActiveExperiment::Base
  variant(:red) { "red" }
  variant(:blue) { "blue" }

  def serialize
    super.merge(account_id: context.account_id, plan: context.plan_name)
  end
end
```

By default it includes the experiment name, run id, run key, assigned variant, how that variant was decided, and whether the run was skipped.

That last pair is worth having in whatever you report to. `variant_source` says which of the several ways a variant could have been arrived at actually happened -- `:rollout`, `:cached`, `:segment`, `:preset`, `:skipped`, or `:default` when nothing assigned one and the default variant was used, which usually means the rollout isn't working.

## Experiments in views

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
= MyExperiment.set(capture: self).run(current_user) do |experiment|
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
<%= MyExperiment.set(capture: self).run(current_user) do |experiment| %>
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

## Client side experimentation

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

## Similar and noteworthy projects

- [Vanity](https://vanity.labnotes.org/) - Experiment Driven Development framework for Rails.
- [Scientist](https://github.com/github/scientist) - A Ruby library for carefully refactoring critical paths.
- [Gitlab::Experiment](https://gitlab.com/gitlab-org/ruby/gems/gitlab-experiment) - A framework for running experiments, by GitLab.
- [Split](https://github.com/splitrb/split) - The Rack Based A/B testing framework.

## License

Active Experiment is released under the MIT license:

* https://opensource.org/licenses/MIT

Copyright 2022-2026 &copy; [jejacks0n](https://github.com/jejacks0n)

## Make Code Not War ♥
