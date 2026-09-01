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

    # Matches the migration in the store's documentation. Writes upsert on this
    # index, so leaving it out of the fixture would hide the case it exists for.
    ActiveRecord::Base.connection.add_index(TABLE_NAME, :key, unique: true)
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

  test "overwriting an entry that's already been written" do
    store = SubjectExperiment.cache_store

    store.write("overwritten", :red)
    store.write("overwritten", :blue)

    assert_equal :blue, store.read("overwritten")
    assert_equal 1, store.length
  end

  test "writing the same entry from two stores, as two requests would" do
    first = ActiveExperiment::Cache::ActiveRecordCacheStore.new
    second = ActiveExperiment::Cache::ActiveRecordCacheStore.new

    # Neither sees the other's write when they read, which is what a pair of
    # concurrent requests resolving the same context looks like.
    assert_nil first.read("concurrent")
    assert_nil second.read("concurrent")

    first.write("concurrent", :red)
    second.write("concurrent", :red)

    assert_equal :red, first.read("concurrent")
    assert_equal 1, first.length
  end

  test "pre-caching the same collection more than once" do
    contexts = [{ id: 1 }, { id: 2 }]

    SubjectExperiment.set(variant: :blue).cache_each(contexts)
    SubjectExperiment.set(variant: :blue).cache_each(contexts)

    assert_equal 2, SubjectExperiment.cache_store.length
    assert_equal "blue", SubjectExperiment.run(id: 1)
  end

  test "writing to a table that's missing the unique index" do
    ActiveRecord::Base.connection.remove_index(TABLE_NAME, :key)
    store = ActiveExperiment::Cache::ActiveRecordCacheStore.new

    error = assert_raises(ActiveExperiment::ExecutionError) do
      store.write("unindexed", :red)
    end

    assert_match(/needs a unique index on `key`/, error.message)
    assert_match(/add_index :#{TABLE_NAME}, :key, unique: true/, error.message)
  end

  test "writing with unless_exist leaves the existing entry alone" do
    store = SubjectExperiment.cache_store

    assert_equal true, store.write("guarded", :red, unless_exist: true)
    assert_equal false, store.write("guarded", :blue, unless_exist: true)

    assert_equal :red, store.read("guarded")
    assert_equal 1, store.length
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

# The statements the store builds for each adapter shape, without needing that
# database to be running. The real suites below cover behaviour; this covers the
# SQL itself, so the MySQL branches stay honest for anyone who doesn't have a
# server handy -- `key` is reserved there, and it has no conflict target.
class ActiveRecordCacheStoreStatementTest < ActiveSupport::TestCase
  # Stands in for an adapter with the given traits. Only the parts of the
  # connection the store actually reaches for.
  Index = Struct.new(:unique, :columns)

  class FakeConnection
    attr_reader :statements

    def initialize(conflict_target:, raw_alias: false, quote: '"', indexed: true)
      @conflict_target = conflict_target
      @raw_alias = raw_alias
      @quote = quote
      @indexed = indexed
      @statements = []
    end

    def supports_insert_conflict_target? = @conflict_target
    def supports_insert_raw_alias_syntax? = @raw_alias
    def quote_column_name(name) = "#{@quote}#{name}#{@quote}"
    def quote_table_name(name) = "#{@quote}#{name}#{@quote}"
    def indexes(_table) = @indexed ? [Index.new(true, ["key"])] : []

    def exec_update(sql, _name = nil)
      @statements << sql
      1
    end

    def exec_query(sql, _name = nil)
      @statements << sql
      []
    end
  end

  def setup
    # sanitize_sql_array quotes binds through the current connection.
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    super
  end

  def write_sql(unless_exist: false, **traits)
    write(unless_exist: unless_exist, **traits).last.statements.sole
  end

  # Returns [result, connection] so callers can assert on either.
  def write(unless_exist: false, **traits)
    connection = FakeConnection.new(**traits)
    store = ActiveExperiment::Cache::ActiveRecordCacheStore.new

    # The key is deliberately free of the substring "key", so the identifier
    # assertions below aren't looking at the bind value.
    result = store.stub(:with_connection, ->(&block) { block.call(connection) }) do
      store.write("subject-42", :red, unless_exist: unless_exist)
    end

    [result, connection]
  end

  test "upserting against an adapter with a conflict target" do
    sql = write_sql(conflict_target: true)

    assert_includes sql, %(INSERT INTO "active_experiment_cache_entries" ("key", "value"))
    assert_includes sql, %(ON CONFLICT ("key") DO UPDATE SET "value" = excluded."value")
  end

  test "upserting against MySQL, which has no conflict target" do
    sql = write_sql(conflict_target: false, raw_alias: false, quote: "`")

    assert_includes sql, "INSERT INTO `active_experiment_cache_entries` (`key`, `value`)"
    assert_includes sql, "ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)"
  end

  test "upserting against MySQL new enough for the row alias syntax" do
    sql = write_sql(conflict_target: false, raw_alias: true, quote: "`")

    assert_includes sql, "AS new ON DUPLICATE KEY UPDATE `value` = new.`value`"
    assert_not_includes sql, "VALUES(`value`)"
  end

  test "skipping duplicates against an adapter with a conflict target" do
    sql = write_sql(conflict_target: true, unless_exist: true)

    assert_includes sql, %(ON CONFLICT ("key") DO NOTHING)
  end

  test "skipping duplicates against MySQL leaves the conflict clause off" do
    # Assigning a column to itself would be the usual spelling, but the affected
    # row count can't be read back through CLIENT_FOUND_ROWS -- so the duplicate
    # is left to raise instead, and write_entry reads the answer off that.
    sql = write_sql(conflict_target: false, raw_alias: true, quote: "`", unless_exist: true)

    assert_not_includes sql, "ON DUPLICATE KEY UPDATE"
    assert_not_includes sql, "ON CONFLICT"
    assert_match(/\AINSERT INTO `active_experiment_cache_entries`.*\)\s*\z/m, sql)
  end

  test "a duplicate on the MySQL skip path is reported as not written" do
    connection = FakeConnection.new(conflict_target: false, quote: "`")
    store = ActiveExperiment::Cache::ActiveRecordCacheStore.new

    def connection.exec_update(*)
      raise ActiveRecord::RecordNotUnique, "Duplicate entry"
    end

    written = store.stub(:with_connection, ->(&block) { block.call(connection) }) do
      store.write("subject-42", :red, unless_exist: true)
    end

    assert_equal false, written
  end

  test "a duplicate on a plain MySQL write still raises" do
    connection = FakeConnection.new(conflict_target: false, quote: "`")
    store = ActiveExperiment::Cache::ActiveRecordCacheStore.new

    def connection.exec_update(*)
      raise ActiveRecord::RecordNotUnique, "Duplicate entry"
    end

    store.stub(:with_connection, ->(&block) { block.call(connection) }) do
      assert_raises(ActiveRecord::RecordNotUnique) { store.write("subject-42", :red) }
    end
  end

  test "MySQL checks for the unique index up front, since it can't fail on it" do
    _, connection = nil
    error = assert_raises(ActiveExperiment::ExecutionError) do
      _, connection = write(conflict_target: false, quote: "`", indexed: false)
    end

    assert_match(/needs a unique index on `key`/, error.message)
    assert_nil connection, "no statement should have been issued"
  end

  test "adapters with a conflict target don't pay for the index lookup" do
    # They fail loudly on the write itself, so there's nothing to check up front.
    connection = FakeConnection.new(conflict_target: true, indexed: false)
    store = ActiveExperiment::Cache::ActiveRecordCacheStore.new

    store.stub(:with_connection, ->(&block) { block.call(connection) }) do
      assert store.write("subject-42", :red)
    end

    assert_equal 1, connection.statements.length
  end

  test "identifiers are always quoted, since `key` is reserved in MySQL" do
    [{ conflict_target: true },
     { conflict_target: false, quote: "`" },
     { conflict_target: false, raw_alias: true, quote: "`" }].each do |traits|
      sql = write_sql(**traits)

      assert_no_match(/(?<![`"\w])key(?![`"\w])/, sql, "unquoted `key` in: #{sql}")
    end
  end
end

# The same behaviour against a real MySQL, which is the other shape the store
# has to write for: `key` is a reserved word there so identifiers have to be
# quoted, and there's no conflict target, so the upsert spells itself
# ON DUPLICATE KEY UPDATE instead.
#
# Trilogy rather than mysql2 so that running these doesn't need libmysqlclient.
class ActiveRecordCacheStoreMysqlTest < ActiveRecordCacheStoreTestCase
  MYSQL_URL = ENV.fetch("AE_MYSQL_URL", "trilogy://root@127.0.0.1:3306/activeexperiment_test")

  def connection_config
    { url: MYSQL_URL }
  end

  def before_setup
    require "trilogy"
    super
  rescue LoadError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError
    skip("Skipping because mysql is not available")
  end

  def establish_connection(value_type: :binary, **overrides)
    super
  end
end
