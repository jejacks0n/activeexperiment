# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gemspec

gem "rails"
gem "puma"

gem "minitest"
gem "minitest-mock"
gem "simplecov"
gem "simplecov-cobertura"
gem "rdoc"

gem "rubocop", ">= 1.25.1", require: false
gem "rubocop-minitest", require: false
gem "rubocop-packaging", require: false
gem "rubocop-performance", require: false
gem "rubocop-rails", require: false

group :test do
  # for integration test dummy app
  gem "redis"
  gem "sqlite3", "~> 2.1"
  gem "bootsnap"

  # Only for the postgres run of the Active Record cache store tests. Building
  # it needs libpq, so it's opt in rather than a requirement for contributing.
  install_if -> { ENV["CI"] || ENV["AE_POSTGRES_URL"] } do
    gem "pg"
  end
end
