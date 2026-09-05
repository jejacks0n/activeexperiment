# frozen_string_literal: true

require "helper"
require "active_record"

class ActiveRecordRecorderTestCase < ActiveSupport::TestCase
  RECORDER = ActiveExperiment::Recorders::ActiveRecordRecorder

  # Abstract: only the adapter specific subclasses run.
  def self.runnable_methods
    self == ActiveRecordRecorderTestCase ? [] : super
  end

  def before_setup
    establish_connection
  end

  # Overridden per adapter.
  def connection_config
    raise NotImplementedError
  end

  def establish_connection(**overrides)
    ActiveRecord::Base.establish_connection(connection_config.merge(overrides))
    connection = ActiveRecord::Base.connection

    RECORDER::UNIQUE_INDEXES.each_key do |model|
      model.reset_column_information
      model.send(:initialize_find_by_cache)
    end

    connection.drop_table("active_experiment_experiments", if_exists: true)
    connection.create_table("active_experiment_experiments") do |t|
      t.string :name, null: false, limit: 191
      t.string :class_name
      t.string :state, null: false, default: "running"
      t.text :variant_names
      t.string :default_variant
      t.text :rollout
      t.string :cache_store
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.datetime :concluded_at
      t.string :winning_variant
      t.text :notes
    end
    connection.add_index("active_experiment_experiments", :name,
      unique: true, name: "index_ae_experiments_on_name")

    connection.drop_table("active_experiment_rollups", if_exists: true)
    connection.create_table("active_experiment_rollups") do |t|
      t.string :experiment, null: false, limit: 191
      t.string :variant, null: false, limit: 64
      t.date :date, null: false
      RECORDER::COUNTERS.each { |counter| t.integer counter, null: false, default: 0 }
    end
    connection.add_index("active_experiment_rollups", [:experiment, :variant, :date],
      unique: true, name: "index_ae_rollups_uniqueness")

    connection.drop_table("active_experiment_overlaps", if_exists: true)
    connection.create_table("active_experiment_overlaps") do |t|
      t.string :experiment_a, null: false, limit: 191
      t.string :variant_a, null: false, limit: 64
      t.string :experiment_b, null: false, limit: 191
      t.string :variant_b, null: false, limit: 64
      t.integer :count, null: false, default: 0
      t.integer :nested_count, null: false, default: 0
      t.datetime :last_seen_at
    end
    connection.add_index("active_experiment_overlaps",
      [:experiment_a, :variant_a, :experiment_b, :variant_b],
      unique: true, name: "index_ae_overlaps_uniqueness")
  end

  def setup
    ActiveExperiment::Executed.clear_all

    @recorder = RECORDER.new(flush_interval: 1_000_000, flush_threshold: 1_000_000)
    SubjectExperiment.recorder = @recorder
    OtherExperiment.recorder = @recorder
  end

  def teardown
    ActiveExperiment::Executed.clear_all

    SubjectExperiment.recorder = ActiveExperiment::Base.recorder
    OtherExperiment.recorder = ActiveExperiment::Base.recorder
  end

  test "looking this recorder up by name, with or without the suffix" do
    assert_instance_of RECORDER, ActiveExperiment::Recorders.lookup(:active_record)
    assert_instance_of RECORDER, ActiveExperiment::Recorders.lookup(:active_record_recorder)
  end

  test "recording a run" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    @recorder.flush!

    rollup = @recorder.rollups(SubjectExperiment.experiment_name).sole

    assert_equal :red, rollup[:variant]
    assert_equal Date.current, rollup[:date]
    assert_equal 1, rollup[:runs]
    assert_equal 1, rollup[:from_preset]
    assert_equal 0, rollup[:from_rollout]
  end

  test "counts from separate flushes add up rather than overwrite" do
    2.times { SubjectExperiment.set(variant: :red).run(id: 1) && @recorder.flush! }
    3.times { SubjectExperiment.set(variant: :red).run(id: 1) && @recorder.flush! }

    assert_equal 5, @recorder.rollups(SubjectExperiment.experiment_name).sole[:runs]
  end

  test "counts from two recorders add up, the way two processes would" do
    other = RECORDER.new(flush_interval: 1_000_000, flush_threshold: 1_000_000)

    SubjectExperiment.set(variant: :red).run(id: 1)
    @recorder.flush!

    SubjectExperiment.recorder = other
    SubjectExperiment.set(variant: :red).run(id: 2)
    other.flush!

    assert_equal 2, @recorder.rollups(SubjectExperiment.experiment_name).sole[:runs]
  end

  test "variants are counted separately" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    SubjectExperiment.set(variant: :blue).run(id: 2)
    SubjectExperiment.set(variant: :blue).run(id: 3)
    @recorder.flush!

    counts = @recorder.rollups(SubjectExperiment.experiment_name).to_h { |r| [r[:variant], r[:runs]] }

    assert_equal({ blue: 2, red: 1 }, counts)
  end

  test "rollups can be limited to recent days" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    @recorder.flush!

    assert_equal 1, @recorder.rollups(SubjectExperiment.experiment_name, since: Date.current).length
    assert_equal 0, @recorder.rollups(SubjectExperiment.experiment_name, since: Date.current + 1).length
  end

  test "recording what an experiment is" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    @recorder.flush!

    recorded = @recorder.experiment(SubjectExperiment.experiment_name)

    assert_equal SubjectExperiment.name, recorded[:class_name]
    assert_equal [:red, :blue], recorded[:variant_names]
    assert_equal :red, recorded[:default_variant]
    assert_equal :percent, recorded[:rollout][:type].to_sym
    assert_equal({ red: 25.0, blue: 75.0 }, recorded[:rollout][:distribution])
    assert_equal :running, recorded[:state]
    assert_not_nil recorded[:first_seen_at]
  end

  test "an experiment keeps the time it was first seen" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    @recorder.flush!
    first_seen = @recorder.experiment(SubjectExperiment.experiment_name)[:first_seen_at]

    SubjectExperiment.set(variant: :red).run(id: 2)
    @recorder.flush!

    assert_equal first_seen, @recorder.experiment(SubjectExperiment.experiment_name)[:first_seen_at]
  end

  test "updating an experiment doesn't make it look like it just ran" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    @recorder.flush!
    ran_at = @recorder.experiment(SubjectExperiment.experiment_name)[:last_seen_at]

    @recorder.update_experiment(SubjectExperiment.experiment_name, state: "archived")

    # Archiving is how you say nobody runs this any more. It shouldn't be the
    # thing that makes it look freshly run.
    assert_equal ran_at, @recorder.experiment(SubjectExperiment.experiment_name)[:last_seen_at]
  end

  test "an experiment that gets a state without ever running was never seen" do
    recorded = @recorder.update_experiment("labelled_experiment", state: "archived")

    assert_nil recorded[:first_seen_at]
    assert_nil recorded[:last_seen_at]
  end

  test "listing every recorded experiment" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    @recorder.flush!

    assert_equal [OtherExperiment.experiment_name, SubjectExperiment.experiment_name],
      @recorder.experiments.map { |e| e[:name] }
  end

  test "an experiment that's never been recorded" do
    assert_nil @recorder.experiment("nope")
    assert_empty @recorder.rollups("nope")
    assert_empty @recorder.overlaps("nope")
  end

  test "a run doesn't overwrite what was set on the experiment" do
    @recorder.update_experiment(SubjectExperiment.experiment_name,
      state: "concluded", winning_variant: "blue", notes: "blue won")

    SubjectExperiment.run(id: 1)
    @recorder.flush!

    recorded = @recorder.experiment(SubjectExperiment.experiment_name)

    assert_equal :concluded, recorded[:state]
    assert_equal :blue, recorded[:winning_variant]
    assert_equal "blue won", recorded[:notes]
    # And the run still filled in what it knows, which the update never wrote.
    assert_equal SubjectExperiment.name, recorded[:class_name]
  end

  test "updating an experiment that's never been recorded creates it" do
    @recorder.update_experiment("brand_new_experiment", state: "archived")

    assert_equal :archived, @recorder.experiment("brand_new_experiment")[:state]
  end

  test "forgetting an experiment removes everything recorded about it" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    deleted = @recorder.delete_experiment(SubjectExperiment.experiment_name)

    assert_equal({ experiments: 1, rollups: 1, overlaps: 1 }, deleted)
    assert_nil @recorder.experiment(SubjectExperiment.experiment_name)
    assert_empty @recorder.rollups(SubjectExperiment.experiment_name)
    assert_empty @recorder.overlaps(SubjectExperiment.experiment_name)
  end

  test "forgetting an experiment leaves the others alone" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    @recorder.flush!

    @recorder.delete_experiment(SubjectExperiment.experiment_name)

    assert_not_nil @recorder.experiment(OtherExperiment.experiment_name)
    assert_equal 1, @recorder.rollups(OtherExperiment.experiment_name).length
  end

  test "forgetting an experiment takes the overlap off the other side too" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    @recorder.delete_experiment(SubjectExperiment.experiment_name)

    # A pair is stored once rather than once per side, so there's no half of it
    # left behind pointing at an experiment that's gone.
    assert_empty @recorder.overlaps(OtherExperiment.experiment_name)
  end

  test "forgetting an experiment discards what this process had buffered" do
    SubjectExperiment.set(variant: :red).run(id: 1)

    # Deliberately not flushed: a buffered count would otherwise land after the
    # delete and put the experiment straight back.
    @recorder.delete_experiment(SubjectExperiment.experiment_name)
    @recorder.flush!

    assert_nil @recorder.experiment(SubjectExperiment.experiment_name)
    assert_empty @recorder.rollups(SubjectExperiment.experiment_name)
  end

  test "forgetting an experiment that was never recorded" do
    assert_equal({ experiments: 0, rollups: 0, overlaps: 0 },
      @recorder.delete_experiment("never_heard_of_it"))
  end

  test "recording an overlap" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    overlap = @recorder.overlaps(SubjectExperiment.experiment_name).sole

    assert_equal SubjectExperiment.experiment_name, overlap[:experiment]
    assert_equal :red, overlap[:variant]
    assert_equal OtherExperiment.experiment_name, overlap[:other_experiment]
    assert_equal :on, overlap[:other_variant]
    assert_equal 1, overlap[:count]
    assert_equal 0, overlap[:nested_count]
  end

  test "an overlap reads the same from either side" do
    SubjectExperiment.set(variant: :red).run(id: 1)
    OtherExperiment.set(variant: :on).run(id: 1)
    ActiveExperiment::Executed.reset
    @recorder.flush!

    from_other = @recorder.overlaps(OtherExperiment.experiment_name).sole

    assert_equal OtherExperiment.experiment_name, from_other[:experiment]
    assert_equal :on, from_other[:variant]
    assert_equal SubjectExperiment.experiment_name, from_other[:other_experiment]
    assert_equal :red, from_other[:other_variant]
  end

  test "overlap counts accumulate across flushes" do
    3.times do
      SubjectExperiment.set(variant: :red).run(id: 1)
      OtherExperiment.set(variant: :on).run(id: 1)
      ActiveExperiment::Executed.reset
      @recorder.flush!
    end

    assert_equal 3, @recorder.overlaps(SubjectExperiment.experiment_name).sole[:count]
  end

  test "the variant cross tab an overlap builds up" do
    [[:red, :on], [:red, :on], [:red, :off], [:blue, :on]].each do |variant, other|
      SubjectExperiment.set(variant: variant).run(id: 1)
      OtherExperiment.set(variant: other).run(id: 1)
      ActiveExperiment::Executed.reset
    end
    @recorder.flush!

    cross_tab = @recorder.overlaps(SubjectExperiment.experiment_name)
      .to_h { |row| [[row[:variant], row[:other_variant]], row[:count]] }

    assert_equal({
      [:red, :on] => 2,
      [:red, :off] => 1,
      [:blue, :on] => 1
    }, cross_tab)
  end

  test "writing to tables that don't exist says which" do
    ActiveRecord::Base.connection.drop_table("active_experiment_rollups", if_exists: true)

    SubjectExperiment.set(variant: :red).run(id: 1)

    error = assert_raises(ActiveExperiment::ExecutionError) { @recorder.flush! }

    assert_match(/active_experiment_rollups/, error.message)
    assert_match(/generate active_experiment:install/, error.message)
  end

  test "writing to a table with no unique index to conflict against says so" do
    connection = ActiveRecord::Base.connection
    connection.remove_index("active_experiment_rollups", name: "index_ae_rollups_uniqueness")

    SubjectExperiment.set(variant: :red).run(id: 1)

    error = assert_raises(ActiveExperiment::ExecutionError) { @recorder.flush! }

    assert_match(/needs a unique index/, error.message)
    assert_match(/experiment, variant, and date/, error.message)
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }

    use_rollout :percent, rules: { red: 25, blue: 75 }
    use_default_variant :red
  end

  class OtherExperiment < ActiveExperiment::Base
    variant(:on) { "on" }
    variant(:off) { "off" }
  end
end

class ActiveRecordRecorderSqliteTest < ActiveRecordRecorderTestCase
  def connection_config
    { adapter: "sqlite3", database: ":memory:" }
  end
end

# The adapter that has a conflict target but numbers its bind placeholders, and
# the one that's strictest about the derived types an upsert produces.
class ActiveRecordRecorderPostgresTest < ActiveRecordRecorderTestCase
  POSTGRES_URL = ENV.fetch("AE_POSTGRES_URL", "postgres://postgres@localhost:5432/activeexperiment_test")

  def connection_config
    { url: POSTGRES_URL }
  end

  def before_setup
    require "pg"
    super
  rescue LoadError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError
    skip("Skipping because postgres isn't available. Point AE_POSTGRES_URL at one to run these (default: #{POSTGRES_URL}).")
  end
end

# The adapter the increment is really written for: no conflict target and no
# `excluded`, so adding a delta to the stored row spells itself
# `count = count + VALUES(count)` instead.
class ActiveRecordRecorderMysqlTest < ActiveRecordRecorderTestCase
  MYSQL_URL = ENV.fetch("AE_MYSQL_URL", "trilogy://root@127.0.0.1:3306/activeexperiment_test")

  def connection_config
    { url: MYSQL_URL }
  end

  def before_setup
    require "trilogy"
    super
  rescue LoadError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError
    skip("Skipping because mysql isn't available. Point AE_MYSQL_URL at one to run these (default: #{MYSQL_URL}).")
  end
end
