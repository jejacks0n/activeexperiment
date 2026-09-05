# frozen_string_literal: true

namespace :active_experiment do
  desc "Delete everything recorded about an experiment"
  task :forget, [:experiment] => :environment do |_task, args|
    given = args[:experiment].to_s
    raise "Provide an experiment, like `active_experiment:forget[MyExperiment]`" if given.blank?

    # The class is consulted if there is one, because it's the only thing
    # that knows its own record name and recorder. An experiment that moved and
    # kept the old one with `def self.experiment_name` is recorded under a name
    # that has nothing to do with what the class is called now, and going by
    # the name alone would quietly delete nothing and report success.
    #
    # Falling back to the name is the case this task mostly exists for, though,
    # the experiment most worth forgetting is one whose class has probably been
    # deleted, so there's nothing left to ask. Both spellings find a class
    # that's still around -- `MyExperiment` and `my_experiment`, as do
    # `My::Experiment` and `my/experiment`.
    experiment_class = given.camelize.safe_constantize
    experiment_class = nil unless experiment_class.is_a?(Class) && experiment_class <= ActiveExperiment::Base

    name = experiment_class ? experiment_class.experiment_name : given.underscore

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
  end
end
