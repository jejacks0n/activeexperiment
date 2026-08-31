# Changelog

## 0.2.0 (unreleased)

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
