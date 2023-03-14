# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gemspec

gem "rails", "~> 6.0.0"
gem "puma"

gem "minitest"
gem "simplecov"
gem "rdoc"

gem "rubocop", ">= 1.25.1", require: false
gem "rubocop-minitest", require: false
gem "rubocop-packaging", require: false
gem "rubocop-performance", require: false
gem "rubocop-rails", require: false

group :test do
  # for integration test dummy app
  gem "redis"
  gem "sqlite3", "~> 1.4"
  gem "bootsnap"
  gem "sprockets-rails"
end
