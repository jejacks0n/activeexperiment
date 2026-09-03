# frozen_string_literal: true

require "integration_helper"

describe "the railtie" do
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
