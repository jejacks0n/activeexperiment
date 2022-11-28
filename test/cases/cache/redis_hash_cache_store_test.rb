# frozen_string_literal: true

require "helper"
require "redis"

REDIS = Redis.new(
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
) rescue nil

class RedisHashCacheStoreTest < ActiveSupport::TestCase
  def setup
    REDIS.flushall
  rescue Redis::CannotConnectError
    skip("Skipping because redis is not available")
  end

  test "this cache store" do
    skip("implement me")
  end
end
