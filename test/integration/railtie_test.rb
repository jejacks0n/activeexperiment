# frozen_string_literal: true

require "integration_helper"

describe "the railtie" do
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
