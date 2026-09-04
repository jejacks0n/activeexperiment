# Changelog

## 0.2.1 (unreleased)

### Requires a migration

**The Active Record cache store now requires the unique index on `key`.**

The index has been part of the store's documented migration since it was
introduced, so a table created by following those docs already has it and needs
no change. If yours doesn't, add it before upgrading:

```ruby
add_index :active_experiment_cache_entries, :key, unique: true
```

Writes upsert on that index now. Without it PostgreSQL and SQLite reject the
statement, and MySQL would quietly accumulate duplicate rows instead of failing
at all -- so on MySQL the index is checked up front, once per table, rather than
left to go wrong silently. Either way a write against a table that's missing it
raises an `ActiveExperiment::ExecutionError` naming the index to add, rather
than the adapter's error.

### Changed

* The Active Record cache store can be pointed at a database other than the one
  `ActiveRecord::Base` is connected to, by passing a class to use instead:

  ```ruby
  use_cache_store :active_record, connection_class: CacheRecord
  ```

  Entries are numerous and live as long as the experiment does, so a busy
  application may not want them in its primary database.

* Rollouts can be registered by name, and a `String` now means the name of a
  class rather than a path to one. Paths are still supported, as a `Pathname`:

  ```ruby
  ActiveExperiment::Rollouts.register(:feature_flag, "FeatureFlagRollout")
  ActiveExperiment::Rollouts.register(:feature_flag, Rails.root.join("lib/feature_flag_rollout.rb"))
  ```

  This might break your existing rollout registrations if you're using a
  String. Swap any paths to using a PathName, like using `Rails.root.join`, or
  similar.

* The log subscriber takes into consideration the log level before it builds
  the log. This improves performance based on the log level now -- so a log
  level of `:error` performs better than a log level of `:debug` for example.
  This is also related to, and required for the run_id/run_key performance
  improvements below.

* `run_id` and `run_key` are generated when they're first needed rather than
  when the experiment is initialized. A skipped experiment resolves its variant
  without a run key, and plenty of runs never need a run id, so we can get by
  without having to calculate them up front.
  Measured with logging off: building an experiment went from 3.9µs to 1.6µs, 
  and a skipped run from 13.1µs to 9.9µs.

  The context is still rendered when the experiment is initialized, which helps
  identify potential issues even while an experiment is skipped, but we don't
  have to generate the hash until it's required, which improves performance.

* Captured experiment results are html safe, so `<%=` renders them correctly
  and the raw `<%==` tag is no longer needed. Everything in the result came
  back from the view context's `capture`, which returns a SafeBuffer or escapes
  a plain String, so assembling it introduces nothing unescaped -- but `gsub`
  handed back a bare String, which left callers rendering it raw. Templates
  already using `<%==` render identically and don't need changing.

* Experiments can report how much they've cached:

  ```ruby
  MyExperiment.cache_size # => 4_111
  ```

  Cache size follows from how many distinct contexts actually reach an
  experiment. The included cache stores provide this, but it may not exist in
  other cache stores.

### Fixed

* Percent rollout percentages are validated even when the rollout is declared
  above the variants.

* `MyExperiment.clear_cache` no longer has the possibility to clear other
  experiments' entries.

* A capturable experiment run without a run block renders its variant instead
  of nothing. There's no surrounding markup to substitute into in that case, so
  the empty capture was overwriting the variant's result with an empty string.
  The same applied to a run block that rendered nothing.

* Query log tags work now.

  The experiment is now set on the execution context for the duration of the
  run, so queries made from variant blocks, segment rules and callbacks are
  attributed to it:

  ```sql
  SELECT 1 /*application='MyApp',experiment='MyExperiment'*/
  ```

  It's scoped to the run, so queries after aren't still attributed to it, and a
  nested experiment restores the outer context when it finishes.
  
  Set `config.active_experiment.log_query_tags_around_run = false` to leave the
  tagging unregistered.

* The Active Record cache store can write a key that's already been written.
  Writes were a bare `INSERT`, so anything that wrote the same key twice raised
  `ActiveRecord::RecordNotUnique`. That covered two ordinary cases: two requests
  resolving the same context concurrently -- both miss the read, both write, and
  one of them 500s -- and re-running `cache_each` over a collection that had
  already been pre-cached. Writes now upsert.

* `write` with `unless_exist: true` no longer has a gap between checking and
  writing. It was a read followed by an insert, so a concurrent write between
  the two would still raise. It's now a single statement -- `ON CONFLICT DO
  NOTHING` where there's a conflict target, and on MySQL a plain insert whose
  duplicate is caught, since `CLIENT_FOUND_ROWS` makes a matched row and an
  inserted row report the same count there. It still returns `false` when an
  entry was already present.

* An experiment is recorded in `ActiveExperiment::Executed` once, rather than
  once per call to `run`. Running an experiment that's already run returns the
  first result without resolving a second variant, as documented, but the
  recording sat in a method level `ensure` that the early return reached too.
  Calling `run` repeatedly -- in a view, or by accident from inside a run or
  variant block -- grew the list on every call, with each entry holding the
  experiment and its context for the rest of the request.

  An experiment that raises partway through is still recorded. One that raises
  `No variants registered` before it can start is no longer recorded, since it
  never ran.

* The Active Record cache store works on MySQL. Identifiers were written into
  the statements bare, and `key` is a reserved word there, so every statement
  the store issued was a syntax error -- the store had never actually run on
  MySQL despite being documented as probably fine. Table and column names now
  go through the connection's quoting, and the upsert uses `ON DUPLICATE KEY
  UPDATE` (with the row alias form on 8.0.19+) where there's no conflict target.

## 0.2.0 (released 2026-09-01)

### Breaking changes

**Variant assignment changes for every existing context.**

Run keys are computed differently in this release, and the percent rollout's
boundaries have shifted. Any context that has already been assigned a variant
may be assigned a different one after upgrading, and existing cache entries no
longer correspond to the keys that will be looked up.

If you have experiments in flight, treat this as the end of those experiments.

Collect your results, clear the experiment cache (`MyExperiment.clear_cache`),
and start new experiments fresh.

* Run keys are now computed from a context hash in a stable order. Previously
  `{a: 1, b: 2}` and `{b: 2, a: 1}` produced different digests, so the same
  context written two different ways would split a subject across variants and
  across cache entries.

* Contexts containing objects that aren't `GlobalID::Identification` now raise
  an `ArgumentError`. Such objects fell through to `inspect`, embedding a memory
  address that changes every process — which silently destroyed both consistent
  assignment and cache stability.
  Set `ActiveExperiment::Base.unsafe_context_digest = true` to restore the
  previous behavior if you don't want exceptions raised on this / want the
  existing behavior.

* The percent rollout no longer over-allocates the first bucket and
  under-allocates the last. Declared rules of `{control: 25, red: 30, blue: 45}`
  previously distributed as `26/30/44`.

* Run key digests now include a version marker, so future changes to the key
  algorithm are detectable rather than silent.

* `ActiveExperiment::Rollouts.lookup` no longer resolves constants it wasn't
  given. Lookup fell through to the top level, so an unregistered `FooRollout`
  defined anywhere in an application would answer `lookup(:foo)` and could be
  used by `use_rollout :foo`. Rollouts now have to be registered. Registering by
  path still works, including when the file defines the class at the top level.

### Fixed

* The Railtie no longer calls `Rails.application.secrets`, which was removed in
  Rails 7.2 and raised `NoMethodError` during initialization on Rails 7.2+.

* Active Experiment doesn't consider a missing `secret_key_base` an issue and 
  instead falls back to an unsalted digest rather than keeping the application
  from booting over an optional feature.

* Compatibility with Ruby 3.4+ and Rails 8.1.

### Changed

* Minimum supported versions are now Ruby 3.2 and Active Support 7.1.

* Integration tests now run as part of `rake test`. They previously existed but
  were never executed.
