# frozen_string_literal: true

require "helper"
require "active_record"
require "tmpdir"

# Behaviour every adapter has to satisfy. Subclassed once per adapter below --
# inheritance rather than a module so the nested SubjectExperiment still
# resolves from the shared tests.
class ActiveRecordCacheStoreTestCase < ActiveSupport::TestCase
  TABLE_NAME = "active_experiment_cache_entries"

  # Abstract: only the adapter specific subclasses run.
  def self.runnable_methods
    self == ActiveRecordCacheStoreTestCase ? [] : super
  end

  def before_setup
    establish_connection
  end

  # Overridden per adapter.
  def connection_config
    raise NotImplementedError
  end

  def establish_connection(value_type: :string, **overrides)
    ActiveRecord::Base.establish_connection(connection_config.merge(overrides))
    ActiveRecord::Base.connection.drop_table(TABLE_NAME, if_exists: true)
    ActiveRecord::Base.connection.create_table(TABLE_NAME, id: false) do |t|
      t.string :key
      t.send(value_type, :value)
    end
  end

  def setup
    SubjectExperiment.use_cache_store :active_record
    SubjectExperiment.cache_store.clear
    super
  end

  test "clearing the entire cache for all experiments" do
    experiment = SubjectExperiment.new
    experiment.run

    assert_equal 1, experiment.cache_store.length

    experiment.cache_store.clear

    assert_equal 0, experiment.cache_store.length
  end

  test "clearing the cache for a specific experiment" do
    experiment = SubjectExperiment.new
    experiment.run

    assert_equal 1, experiment.cache_store.length

    experiment.cache_store.delete_matched(experiment.name)

    assert_equal 0, experiment.cache_store.length
  end

  test "clearing the cache for a specific experiment that has a namespace" do
    namespaced = Class.new(SubjectExperiment) do
      def self.name = "NamespacedCacheStoreExperiment"

      use_cache_store ActiveExperiment::Cache::ActiveRecordCacheStore.new(
        namespace: "_exp_"
      )
    end

    experiment = namespaced.new
    experiment.run
    experiment.cache_store.delete_matched(experiment.name)

    assert_equal 0, experiment.cache_store.length
  end

  test "caching resolved variants" do
    experiment = SubjectExperiment.new

    assert_equal "red", experiment.run
    assert_equal :red, experiment.cache_store.read(experiment.cache_key)
    assert_equal 1, experiment.cache_store.length
  end

  test "caching assigned variants" do
    experiment = SubjectExperiment.new
    experiment.set(variant: :blue)

    assert_equal "blue", experiment.run
    assert_equal :blue, experiment.cache_store.read(experiment.cache_key)
    assert_equal 1, experiment.cache_store.length
  end

  test "caching variants when segmented" do
    experiment = SubjectExperiment.new(segment_into_green: true)

    assert_equal "green", experiment.run
    assert_equal :green, experiment.cache_store.read(experiment.cache_key)
    assert_equal 1, experiment.cache_store.length
  end

  test "skipped experiments" do
    experiment = SubjectExperiment.new
    experiment.skip

    assert_nil experiment.run
    assert_nil experiment.cache_store.read(experiment.cache_key)
    assert_equal 0, experiment.cache_store.length
  end

  test "skipped experiments (through inactive rollout)" do
    inactive = Class.new(SubjectExperiment) do
      def self.name = "InactiveExperiment"

      use_rollout :inactive
      use_cache_store :active_record
    end

    experiment = inactive.new
    experiment.set(variant: :blue)

    assert_equal "blue", experiment.run
    assert_nil experiment.cache_store.read(experiment.cache_key)
    assert_equal 0, experiment.cache_store.length
  end

  test "skipped experiments with an assigned variant" do
    experiment = SubjectExperiment.new
    experiment.set(variant: :blue)
    experiment.skip

    assert_equal "blue", experiment.run
    assert_nil experiment.cache_store.read(experiment.cache_key)
    assert_equal 0, experiment.cache_store.length
  end

  test "deleting a single entry" do
    experiment = SubjectExperiment.new(id: 1)
    experiment.run

    assert_equal 1, experiment.cache_store.length

    experiment.cache_store.delete(experiment.cache_key)

    assert_equal 0, experiment.cache_store.length
  end

  test "when a cache key already exists" do
    SubjectExperiment.set(variant: :green).run(id: 1)

    assert_equal 1, SubjectExperiment.cache_store.length

    experiment = SubjectExperiment.new(id: 1)

    assert_equal "green", experiment.run
    assert_equal 1, experiment.cache_store.length
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:red) { "red" }
    variant(:blue) { "blue" }
    variant(:green) { "green" }

    segment(into: :green) { context[:segment_into_green] }

    def self.use_cache_store(*)
      super
    end
  end
end

class ActiveRecordCacheStoreTest < ActiveRecordCacheStoreTestCase
  def connection_config
    { adapter: "sqlite3", database: ":memory:" }
  end

  test "round tripping entries through a binary value column" do
    Dir.mktmpdir do |dir|
      establish_connection(database: File.join(dir, "binary.sqlite3"), value_type: :binary)
      store = ActiveExperiment::Cache::ActiveRecordCacheStore.new

      store.write("key", :red)

      assert_equal :red, store.read("key")
      assert_equal 1, store.length
    end
  end

  test "reading entries stored as text before values were quoted as binary" do
    store = ActiveExperiment::Cache::ActiveRecordCacheStore.new
    payload = store.send(:serialize_entry, ActiveSupport::Cache::Entry.new(:blue))

    # Written the way the store used to, as a bind rather than a binary
    # literal. Existing rows have to stay readable.
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.exec_query(
        "INSERT INTO #{TABLE_NAME} (key, value) VALUES (?, ?)", "SQL", ["legacy", payload]
      )
    end

    assert_equal :blue, store.read("legacy")
  end

  test "following the current connection after the app reconnects" do
    Dir.mktmpdir do |dir|
      establish_connection(database: File.join(dir, "a.sqlite3"))
      store = ActiveExperiment::Cache::ActiveRecordCacheStore.new

      # Rails re-establishes connections on fork, on role and shard switches,
      # and whenever the app reconnects. A store holding the connection it was
      # built with goes on writing to the database it captured.
      establish_connection(database: File.join(dir, "b.sqlite3"))
      store.write("key", :red)

      # Asserted through the app's current connection rather than through the
      # store: a store reading back through its own stale connection sees its
      # own writes just fine, in the wrong database.
      written = ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.exec_query("SELECT COUNT(*) AS count FROM #{TABLE_NAME}").first["count"]
      end

      assert_equal 1, written
      assert_equal :red, store.read("key")
    end
  end

  test "reading and writing from many threads at once" do
    # A file backed database: an in-memory sqlite database is scoped to a single
    # connection, and the point of this test is that each thread checks out its
    # own from the pool.
    Dir.mktmpdir do |dir|
      establish_connection(database: File.join(dir, "cache.sqlite3"), pool: 10, timeout: 5000)

      store = ActiveExperiment::Cache::ActiveRecordCacheStore.new
      threads = 10.times.map do |i|
        Thread.new { store.write("key-#{i}", :"variant-#{i}") && store.read("key-#{i}") }
      end

      assert_equal (0...10).map { |i| :"variant-#{i}" }, threads.map(&:value)
    end
  end
end

# The same behaviour against a real postgres, which is the adapter the store's
# portability actually turns on: it can't hold the serialized entry in a text
# column, and it numbers bind placeholders rather than using `?`.
class ActiveRecordCacheStorePostgresTest < ActiveRecordCacheStoreTestCase
  POSTGRES_URL = ENV.fetch("AE_POSTGRES_URL", "postgres://postgres@localhost:5432/activeexperiment_test")

  def connection_config
    { url: POSTGRES_URL }
  end

  def before_setup
    require "pg"
    super
  rescue LoadError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError
    skip("Skipping because postgres is not available")
  end

  # A binary column is what the store documents for anything but sqlite, and
  # postgres is the adapter that enforces it.
  def establish_connection(value_type: :binary, **overrides)
    super
  end
end
