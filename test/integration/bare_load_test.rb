# frozen_string_literal: true

require "open3"
require "minitest/autorun"
require "active_support"

# The gem depends on activesupport and globalid, not on Rails, so a file that
# uses an Active Support core extension has to require it. The rest of the
# suite can't catch a missing one, because loading Active Record drags in most
# of Active Support and hides them.
#
# This runs in a child process with nothing but the gem loaded, so anything
# reaching for an extension it hasn't required fails here.
class BareLoadTest < Minitest::Test
  def test_the_gem_works_without_rails_or_active_record
    stdout, stderr, status = run_script(<<~'RUBY')
      class BareExperiment < ActiveExperiment::Base
        variant(:red) { "red" }
        variant(:blue) { "blue" }

        use_cache_store :memory_store
        use_rollout :percent, rules: { red: 50, blue: 50 }
        segment(into: :blue) { context[:id] == 99 }
      end

      # index_with, in the percent rollout.
      check "describe", BareExperiment.rollout.describe[:distribution] == { red: 50.0, blue: 50.0 }

      BareExperiment.run(id: 1)
      check "segment", BareExperiment.new(id: 99).tap(&:run).variant_source == :segment
      check "cached", BareExperiment.new(id: 1).tap(&:run).variant_source == :cached
      check "explain", BareExperiment.explain(id: 3)[:state] == :running

      # squish, in the messages both of these raise.
      begin
        BareExperiment.cache_store = :redis_hash
      rescue ArgumentError => error
        check "squish", error.message.include?("Assign a cache store")
      end
      begin
        BareExperiment.clear_cache(batch_size: 10)
      rescue ActiveExperiment::ExecutionError => error
        check "squish in caching", error.message.include?("can't delete entries in batches")
      end

      # Date.current, when the recorder buckets a run by day.
      recorder = BufferRecorder.new
      BareExperiment.recorder = recorder
      BareExperiment.run(id: 4)
      recorder.flush!
      check "Date.current", recorder.written&.any?

      # Time.current, when a conclusion is written.
      BareExperiment.conclude!(variant: :red, notes: "done")
      check "Time.current", BareExperiment.new(id: 5).tap(&:run).variant_source == :concluded
    RUBY

    assert_equal 0, status.exitstatus, "bare load failed:\n#{stdout}#{stderr}"
    assert_match(/all checks passed/, stdout)
  end

  private
    def run_script(body)
      script = <<~RUBY
        require "active_experiment"
        require "active_experiment/base"
        require "logger"
        ActiveExperiment.logger = Logger.new(nil)

        def check(what, condition)
          raise "\#{what}" unless condition
        end

        # Enough of a recorder to reach the buffering and the lifecycle writes.
        class BufferRecorder < ActiveExperiment::Recorders::BaseRecorder
          attr_reader :written

          def initialize(**options)
            super
            @written = nil
            @rows = {}
          end

          def experiments = @rows.values

          def update_experiment(name, **attributes)
            row = @rows[name.to_s] ||= { name: name.to_s }
            attributes.each { |key, value| row[key] = key == :state ? value&.to_sym : value }
            row
          end

          private
            def write(registry, runs, overlaps)
              @written = runs
            end
        end

        #{body}
        puts "all checks passed"
      RUBY

      lib = File.expand_path("../../lib", __dir__)
      Open3.capture3({ "RUBYOPT" => "-I#{lib} #{ENV["RUBYOPT"]}".strip }, "ruby", "-e", script)
    end
end
