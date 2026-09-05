# frozen_string_literal: true

namespace :active_experiment do
  # Resolves what was typed into a record name, and the class itself when
  # there's still one around.
  #
  # The class is consulted when it exists, because it's the only thing that
  # knows its own record name. An experiment that moved and kept the old one
  # with `def self.experiment_name` is recorded under a name that has nothing
  # to do with what the class is called now, so going by the name alone would
  # quietly do nothing and report success.
  #
  # These tasks mostly exist for experiments whose class might already have been
  # deleted though, and there's nothing left to ask in that case, so the name
  # gets used as it was given. Both spellings find a class that's still around
  # -- `MyExperiment` and `my_experiment`, as do `My::Experiment` and
  # `my/experiment`. If the class isn't around anymore, and you know the name
  # changed, use the old name if that had been overridden.
  def resolve_experiment(given) # :nodoc:
    raise "Provide an experiment, like `active_experiment:forget[MyExperiment]`" if given.blank?

    experiment_class = given.camelize.safe_constantize
    experiment_class = nil unless experiment_class.is_a?(Class) && experiment_class <= ActiveExperiment::Base

    [experiment_class ? experiment_class.experiment_name : given.underscore, experiment_class]
  end

  # How many assignments are still cached under a name, or +nil+ when the store
  # can't count them. Without a class this asks the default cache store, which
  # is a guess, but it's the same store `clear_cache` would delete from.
  def cached_entries(name, experiment_class) # :nodoc:
    (experiment_class || ActiveExperiment::Base).cache_size(name)
  rescue ActiveExperiment::ExecutionError
    nil
  end

  # These need the class, unlike forgetting. The state they write goes to the
  # experiment's own recorder, and there isn't much to conclude about an
  # experiment that no longer exists.
  def active_experiment(given) # :nodoc:
    raise "Provide an experiment, like `active_experiment:conclude[MyExperiment,red]`" if given.blank?

    experiment_class = given.camelize.safe_constantize
    unless experiment_class.is_a?(Class) && experiment_class <= ActiveExperiment::Base
      raise "No experiment class named #{given.camelize}."
    end

    experiment_class
  end

  desc "Conclude an experiment on a variant, which is then assigned to everyone"
  task :conclude, [:experiment, :variant, :notes] => :environment do |_task, args|
    experiment = active_experiment(args[:experiment])
    raise "Provide the variant that won" if args[:variant].blank?

    experiment.conclude!(variant: args[:variant], notes: args[:notes])

    puts "#{experiment.name} concluded on #{experiment.winning_variant}, which every context is now assigned."
    puts "Its cached assignments are still there, so this can still be reversed. " \
      "Clear them once you're sure."
  end

  desc "Put a concluded or archived experiment back to running"
  task :reopen, [:experiment] => :environment do |_task, args|
    experiment = active_experiment(args[:experiment])
    experiment.reopen!

    puts "#{experiment.name} is running again, and resolves variants the way it did before."
  end

  desc "Mark an experiment as no longer interesting, without changing what it assigns"
  task :archive, [:experiment, :notes] => :environment do |_task, args|
    experiment = active_experiment(args[:experiment])
    experiment.archive!(notes: args[:notes])

    puts "#{experiment.name} archived. It still assigns what it assigned before."
  end

  desc "Delete an experiment's cached assignments, a batch at a time"
  task :clear_cache, [:experiment, :batch_size] => :environment do |_task, args|
    name, experiment_class = resolve_experiment(args[:experiment].to_s)
    batch_size = (args[:batch_size] || 1_000).to_i

    # A deleted class leaves its assignments behind, and nothing else removes
    # them. `clear_cache` takes the key prefix and any class works as the
    # receiver, so the base class is the fallback.
    owner = experiment_class || ActiveExperiment::Base
    puts "No experiment class named #{args[:experiment]}, so clearing #{name} by name." if experiment_class.nil?

    print "Clearing #{name}... "
    total = owner.clear_cache(name, batch_size: batch_size) do |_deleted, running|
      print "\rClearing #{name}... #{running}"
    end

    puts "\rCleared #{total} entries for #{name}."
  end

  desc "Delete everything recorded about an experiment"
  task :forget, [:experiment] => :environment do |_task, args|
    given = args[:experiment].to_s
    name, experiment_class = resolve_experiment(given)

    # An experiment that opted out of recording can still have rows from before
    # it did, and those are in the default recorder rather than its own.
    recorder = experiment_class&.recorder
    recorder = ActiveExperiment::Base.recorder unless recorder&.recording?

    unless recorder.recording?
      raise "Nothing is recorded. Configure a recorder with " \
        "`config.active_experiment.default_recorder = :active_record`."
    end

    if experiment_class.nil?
      puts "No experiment class named #{given.camelize}, so going by name."
    elsif name != given.underscore
      puts "#{experiment_class.name} records as #{name}."
    end

    deleted = recorder.delete_experiment(name)
    if deleted.values.sum.zero?
      puts "Nothing recorded for #{name}."
    else
      counts = deleted.map { |kind, count| "#{count} #{kind.to_s.singularize.pluralize(count)}" }

      puts "Forgot #{name}: #{counts.join(", ")}."
      puts "Anything still running it will start recording it again on the next flush."
    end

    # The record that named these is gone now, so it's worth mentioning them
    # here. Clearing the cache first and forgetting afterward is usually the
    # easier order.
    cached = cached_entries(name, experiment_class)
    if cached&.positive?
      puts "#{cached} cached #{"assignment".pluralize(cached)} are still there. " \
        "Clear them with `active_experiment:clear_cache[#{given}]`."
    end
  end
end
