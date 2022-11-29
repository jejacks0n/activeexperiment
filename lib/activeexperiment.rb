# frozen_string_literal: true

# This file is here to make the gem behave like a Rails core library...
require "active_experiment"

# But we'll also require the railtie if it looks like it's loading in a Rails
# app, to avoid having to require it manually in application.rb.
require "active_experiment/railtie" if defined?(Rails)
