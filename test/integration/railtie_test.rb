require "integration_helper"

describe "the railtie" do
  it "sets the logger to the rails logger" do
    assert_equal Rails.logger, ActiveExperiment.logger
  end

  it "registers each of the custom rollouts" do
    skip("implement me")
  end

  it "sets the configuration options" do
    skip("implement me")
  end
end
