# frozen_string_literal: true

require "integration_helper"

# An experiment that moved and kept the record name it started with, which is
# the case the forget task has to consult the class to get right.
class RenamedExperiment < ActiveExperiment::Base
  variant(:red) { "red" }

  def self.experiment_name
    "original_experiment"
  end
end

# Loaded once here rather than per test. `load_tasks` isn't guarded, so calling
# it repeatedly re-loads the rake file, and each load resets the coverage
# counters for it.
Rails.application.load_tasks

describe "the railtie" do
  # Shared with the dummy app's other integration tests, so whichever of them
  # touches the schema puts it back.
  RECORDER_TABLES = %w[
    active_experiment_experiments active_experiment_rollups active_experiment_overlaps
    active_experiment_cache_entries
  ].freeze

  # Swaps in a recorder backed by real tables for the duration of the block, and
  # puts everything back afterwards.
  def with_recorder(&block)
    recorder = ActiveExperiment::Recorders::ActiveRecordRecorder.new
    original, ActiveExperiment::Base.recorder = ActiveExperiment::Base.recorder, recorder
    create_recorder_tables
    RenamedExperiment.refresh_lifecycle!

    block.call(recorder)
  ensure
    ActiveExperiment::Base.recorder = original
    RenamedExperiment.refresh_lifecycle!
    drop_recorder_tables
  end

  def capture_stdout(&block)
    original, $stdout = $stdout, StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = original
  end

  def create_recorder_tables
    recorder = ActiveExperiment::Recorders::ActiveRecordRecorder
    connection = ActiveRecord::Base.connection
    return if connection.table_exists?("active_experiment_experiments")

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

    connection.create_table("active_experiment_rollups") do |t|
      t.string :experiment, null: false, limit: 191
      t.string :variant, null: false, limit: 64
      t.date :date, null: false
      recorder::COUNTERS.each { |counter| t.integer counter, null: false, default: 0 }
    end
    connection.add_index("active_experiment_rollups", [:experiment, :variant, :date],
      unique: true, name: "index_ae_rollups_uniqueness")

    connection.create_table("active_experiment_overlaps") do |t|
      t.string :experiment_a, null: false, limit: 191
      t.string :variant_a, null: false, limit: 64
      t.string :experiment_b, null: false, limit: 191
      t.string :variant_b, null: false, limit: 64
      t.integer :depth, null: false, default: 0
      t.integer :count, null: false, default: 0
      t.datetime :last_seen_at
    end
    connection.add_index("active_experiment_overlaps",
      [:experiment_a, :variant_a, :experiment_b, :variant_b, :depth],
      unique: true, name: "index_ae_overlaps_uniqueness")

    connection.create_table("active_experiment_cache_entries", id: false) do |t|
      t.string :key, null: false
      t.binary :value, null: false
    end
    connection.add_index("active_experiment_cache_entries", :key, unique: true)
  end

  def drop_recorder_tables
    connection = ActiveRecord::Base.connection

    RECORDER_TABLES.each { |table| connection.drop_table(table, if_exists: true) }
  end

  def capture_sql(&block)
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql]
    end

    block.call
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "sets the logger to the rails logger" do
    assert_equal Rails.logger, ActiveExperiment.logger
  end

  it "registers the rake tasks" do
    assert_includes Rake::Task.tasks.map(&:name), "active_experiment:forget"
    assert_includes Rake::Task.tasks.map(&:name), "active_experiment:conclude"
    assert_includes Rake::Task.tasks.map(&:name), "active_experiment:archive"
    assert_includes Rake::Task.tasks.map(&:name), "active_experiment:reopen"
    assert_includes Rake::Task.tasks.map(&:name), "active_experiment:clear_cache"
  end

  it "concludes an experiment through the rake task" do
    recorder = ActiveExperiment::Recorders::ActiveRecordRecorder.new
    original, ActiveExperiment::Base.recorder = ActiveExperiment::Base.recorder, recorder
    create_recorder_tables
    RenamedExperiment.refresh_lifecycle!

    output = capture_stdout do
      Rake::Task["active_experiment:conclude"].tap(&:reenable).invoke("RenamedExperiment", "red", "red won")
    end

    assert_match(/concluded on red/, output)
    assert_equal :concluded, RenamedExperiment.state
    assert_equal :red, RenamedExperiment.winning_variant
    # And it went to the record the class writes to, rather than the class name.
    assert_equal :concluded, recorder.experiment("original_experiment")[:state]
  ensure
    ActiveExperiment::Base.recorder = original
    RenamedExperiment.refresh_lifecycle!
    drop_recorder_tables
  end

  it "forgets an experiment through the rake task" do
    recorder = ActiveExperiment::Recorders::ActiveRecordRecorder.new
    original, ActiveExperiment::Base.recorder = ActiveExperiment::Base.recorder, recorder
    create_recorder_tables

    recorder.update_experiment("task_experiment", class_name: "TaskExperiment")
    assert recorder.experiment("task_experiment")

    output = capture_stdout do
      # Named the way somebody would type it, which is the class rather than
      # the record -- the task underscores it to find the row.
      Rake::Task["active_experiment:forget"].tap(&:reenable).invoke("TaskExperiment")
    end

    assert_match(/Forgot task_experiment/, output)
    assert_nil recorder.experiment("task_experiment")
  ensure
    ActiveExperiment::Base.recorder = original
    drop_recorder_tables
  end

  it "forgets the record a renamed experiment actually writes to" do
    recorder = ActiveExperiment::Recorders::ActiveRecordRecorder.new
    original, ActiveExperiment::Base.recorder = ActiveExperiment::Base.recorder, recorder
    create_recorder_tables

    recorder.update_experiment("original_experiment", class_name: "RenamedExperiment")

    output = capture_stdout do
      Rake::Task["active_experiment:forget"].tap(&:reenable).invoke("RenamedExperiment")
    end

    # Going by the name alone would have looked for `renamed_experiment`,
    # deleted nothing, and said so as though that were the answer.
    assert_match(/RenamedExperiment records as original_experiment/, output)
    assert_match(/Forgot original_experiment/, output)
    assert_nil recorder.experiment("original_experiment")
  ensure
    ActiveExperiment::Base.recorder = original
    drop_recorder_tables
  end

  it "clears an orphaned cache by name through the rake task" do
    original = ActiveExperiment::Base.cache_store
    ActiveExperiment::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
    def (ActiveExperiment::Base.cache_store).count_matched(matcher, options = nil)
      @data.count { |key, _| key.to_s.start_with?(matcher.to_s) }
    end
    def (ActiveExperiment::Base.cache_store).delete_matched_in_batches(matcher, batch_size: nil, options: nil)
      deleted = count_matched(matcher)
      delete_matched(/\A#{Regexp.escape(matcher.to_s)}/)
      deleted
    end
    ActiveExperiment::Base.cache_store.write("deleted_experiment:abc", :red)

    output = capture_stdout do
      Rake::Task["active_experiment:clear_cache"].tap(&:reenable).invoke("DeletedExperiment")
    end

    # No class to ask, so it goes by name against the default store.
    assert_match(/so clearing deleted_experiment by name/, output)
    assert_match(/Cleared 1 entries for deleted_experiment/, output)
  ensure
    ActiveExperiment::Base.cache_store = original
  end

  it "reopens an experiment through the rake task" do
    with_recorder do
      Rake::Task["active_experiment:conclude"].tap(&:reenable).invoke("RenamedExperiment", "red")

      output = capture_stdout do
        Rake::Task["active_experiment:reopen"].tap(&:reenable).invoke("RenamedExperiment")
      end

      assert_match(/is running again/, output)
      assert_equal :running, RenamedExperiment.state
    end
  end

  it "archives an experiment through the rake task" do
    with_recorder do
      output = capture_stdout do
        Rake::Task["active_experiment:archive"].tap(&:reenable).invoke("RenamedExperiment", "superseded")
      end

      assert_match(/archived/, output)
      assert_equal :archived, RenamedExperiment.state
    end
  end

  it "won't conclude an experiment that has no class left" do
    with_recorder do
      error = assert_raises(RuntimeError) do
        Rake::Task["active_experiment:conclude"].tap(&:reenable).invoke("LongGoneExperiment", "red")
      end

      # Concluding writes state the class reads back, so there's nothing
      # sensible to do without one.
      assert_match(/No experiment class named LongGoneExperiment/, error.message)
    end
  end

  it "says so when there's nothing recorded to forget" do
    with_recorder do
      output = capture_stdout do
        Rake::Task["active_experiment:forget"].tap(&:reenable).invoke("RenamedExperiment")
      end

      assert_match(/Nothing recorded for original_experiment/, output)
    end
  end

  it "won't forget anything when nothing is being recorded" do
    error = assert_raises(RuntimeError) do
      Rake::Task["active_experiment:forget"].tap(&:reenable).invoke("RenamedExperiment")
    end

    assert_match(/Nothing is recorded/, error.message)
  end

  it "mentions cached assignments left behind after forgetting" do
    with_recorder do |recorder|
      original, RenamedExperiment.cache_store = RenamedExperiment.cache_store,
        ActiveExperiment::Cache::ActiveRecordCacheStore.new

      recorder.update_experiment("original_experiment", class_name: "RenamedExperiment")
      3.times { |i| RenamedExperiment.cache_store.write("original_experiment:#{i}", :red) }

      output = capture_stdout do
        Rake::Task["active_experiment:forget"].tap(&:reenable).invoke("RenamedExperiment")
      end

      assert_match(/3 cached assignments are still there/, output)
      assert_match(/active_experiment:clear_cache\[RenamedExperiment\]/, output)
    ensure
      RenamedExperiment.cache_store = original
    end
  end

  it "reports progress while clearing a cache in batches" do
    with_recorder do
      original, RenamedExperiment.cache_store = RenamedExperiment.cache_store,
        ActiveExperiment::Cache::ActiveRecordCacheStore.new
      25.times { |i| RenamedExperiment.cache_store.write("original_experiment:#{i}", :red) }

      output = capture_stdout do
        Rake::Task["active_experiment:clear_cache"].tap(&:reenable).invoke("RenamedExperiment", "10")
      end

      # Three chunks of ten, ten and five, each one printed as it goes.
      assert_match(/Clearing original_experiment\.\.\. 10/, output)
      assert_match(/Clearing original_experiment\.\.\. 20/, output)
      assert_match(/Cleared 25 entries for original_experiment/, output)
    ensure
      RenamedExperiment.cache_store = original
    end
  end

  it "forgets by name when no class is left to ask" do
    recorder = ActiveExperiment::Recorders::ActiveRecordRecorder.new
    original, ActiveExperiment::Base.recorder = ActiveExperiment::Base.recorder, recorder
    create_recorder_tables

    recorder.update_experiment("deleted_experiment", class_name: "DeletedExperiment")

    output = capture_stdout do
      Rake::Task["active_experiment:forget"].tap(&:reenable).invoke("DeletedExperiment")
    end

    assert_match(/No experiment class named DeletedExperiment/, output)
    assert_nil recorder.experiment("deleted_experiment")
  ensure
    ActiveExperiment::Base.recorder = original
    drop_recorder_tables
  end

  it "forgets an experiment named the way it's recorded" do
    recorder = ActiveExperiment::Recorders::ActiveRecordRecorder.new
    original, ActiveExperiment::Base.recorder = ActiveExperiment::Base.recorder, recorder
    create_recorder_tables

    recorder.update_experiment("original_experiment", class_name: "RenamedExperiment")

    capture_stdout do
      # The underscored spelling finds the same class, and so the same record.
      Rake::Task["active_experiment:forget"].tap(&:reenable).invoke("renamed_experiment")
    end

    assert_nil recorder.experiment("original_experiment")
  ensure
    ActiveExperiment::Base.recorder = original
    drop_recorder_tables
  end

  it "registers each of the custom rollouts" do
    assert_equal RedRollout, ActiveExperiment::Rollouts.lookup(:red)
    assert_operator ActiveExperiment::Rollouts.lookup(:blue), :<,
      ActiveExperiment::Rollouts::BaseRollout
  end

  it "assigns variants through a rollout registered by path" do
    experiment = Class.new(ActiveExperiment::Base) do
      def self.name = "RedByPathExperiment"

      variant(:red) { "red" }
      variant(:blue) { "blue" }

      use_rollout :red
    end

    assert_equal "red", experiment.run
  end

  it "assigns variants through a rollout registered by class" do
    experiment = Class.new(ActiveExperiment::Base) do
      def self.name = "BlueByClassExperiment"

      variant(:red) { "red" }
      variant(:blue) { "blue" }

      use_rollout :blue
    end

    assert_equal "blue", experiment.run
  end

  it "registers the experiment query log tag" do
    assert_includes Rails.application.config.active_record.query_log_tags, :experiment
    assert_includes ActiveRecord::QueryLogs.taggings.keys, :experiment
  end

  it "tags queries with the experiment that caused them" do
    experiment = Class.new(ActiveExperiment::Base) do
      def self.name = "QueryTaggedExperiment"

      variant(:red) { ActiveRecord::Base.lease_connection.select_value("SELECT 1") }
    end

    statements = capture_sql { experiment.run }

    assert statements.any? { |sql| sql.include?("QueryTaggedExperiment") },
      "expected a tagged statement, got: #{statements.inspect}"
  end

  it "doesn't tag queries run outside of an experiment" do
    statements = capture_sql { ActiveRecord::Base.lease_connection.select_value("SELECT 1") }

    assert statements.none? { |sql| sql.include?("experiment") },
      "expected no experiment tag, got: #{statements.inspect}"
  end

  it "resolves a rollout that lives in app/, registered by name" do
    # Never referenced before now: registering by name is what lets it be
    # looked up at all, since nothing loads the class on the way in.
    assert_equal ReloadableRollout, ActiveExperiment::Rollouts.lookup(:reloadable)
  end

  it "registers a rollout named in the application config" do
    assert_equal ConfiguredRollout, ActiveExperiment::Rollouts.lookup(:configured)
  end

  it "assigns variants through a rollout named in the application config" do
    experiment = Class.new(ActiveExperiment::Base) do
      def self.name = "ConfiguredByNameExperiment"

      variant(:red) { "red" }
      variant(:blue) { "blue" }

      use_rollout :configured
    end

    assert_equal "blue", experiment.run
  end

  it "resolves the reloaded class rather than the one it was registered with" do
    before = ActiveExperiment::Rollouts.lookup(:reloadable)

    Rails.application.reloader.reload!
    after = ActiveExperiment::Rollouts.lookup(:reloadable)

    assert_equal false, before.equal?(after), "expected a new class object after reloading"
    assert_equal ReloadableRollout, after
  end

  it "resolves a cache store named in the application config" do
    assert_instance_of ActiveSupport::Cache::MemoryStore, ActiveExperiment::Base.cache_store
  end

  it "sets the configuration options" do
    assert_equal Rails.application.secret_key_base,
      ActiveExperiment::Base.send(:digest_secret_key)
  end

  it "resolves the digest secret key from the app" do
    app = Object.new
    def app.secret_key_base = "a secret"

    assert_equal "a secret", ActiveExperiment::Railtie.default_digest_secret_key(app)
  end

  it "falls back to a nil digest secret key when the app has no secret" do
    app = Object.new
    def app.secret_key_base
      raise ArgumentError, "Missing `secret_key_base` for 'production' environment"
    end

    assert_nil ActiveExperiment::Railtie.default_digest_secret_key(app)
  end

  it "lets a broken credentials key propagate rather than masking it" do
    app = Object.new
    def app.secret_key_base
      raise ActiveSupport::MessageEncryptor::InvalidMessage
    end

    assert_raises(ActiveSupport::MessageEncryptor::InvalidMessage) do
      ActiveExperiment::Railtie.default_digest_secret_key(app)
    end
  end
end
