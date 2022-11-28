source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gemspec

gem "rails"
gem "puma"

gem "minitest"
gem "simplecov"
gem "rdoc"

group :test do
  # for integration test dummy app
  gem "redis"
  gem "sqlite3", "~> 1.4"
  gem "bootsnap"
  gem "sprockets-rails"
end
