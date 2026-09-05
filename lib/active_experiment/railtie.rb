# frozen_string_literal: true

require "global_id/railtie"
require "active_experiment"

module ActiveExperiment
  # == Railtie
  #
  # Sets Active Experiment up inside a Rails application, and provides the
  # +config.active_experiment+ options below. They can be set anywhere the rest
  # of the application config is -- +config/application.rb+, or a per
  # environment file.
  #
  # === Configuration Options
  #
  # [+custom_rollouts+]
  #   A hash of rollouts to register on boot.
  #   Defaults to +{}+
  #
  #     config.active_experiment.custom_rollouts = { feature_flag: "FeatureFlagRollout" }
  #
  # [+default_rollout+]
  #   The rollout experiments use when they don't specify one, by name or as an
  #   instance.
  #   Defaults to +:percent+
  #
  # [+default_cache_store+]
  #   The default cache store experiments use when they don't specify one.
  #   Defaults to +:null_store+
  #
  #     config.active_experiment.default_cache_store = :redis_cache
  #
  # [+default_recorder+]
  #   The recorder experiments use when they don't specify one.
  #   Defaults to +:null_recorder+
  #
  #     config.active_experiment.default_recorder = :active_record
  #
  # [+default_variant+]
  #   The variant name treated as the default when a rollout doesn't assign
  #   one.
  #   Defaults to +:control+.
  #
  # [+digest_secret_key+]
  #   Salts the run key digest.
  #   Defaults to the application's +secret_key_base+, +nil+ if there isn't one
  #   (changing this will invalidate all run/cache keys)
  #
  # [+digest_bit_length+]
  #   The SHA2 bit length used for run keys -- 256, 384, or 512.
  #   Defaults to +256+
  #   (changing this will invalidate all run/cache keys)
  #
  # [+unsafe_context_digest+]
  #   Allows contexts with objects that can't be identified stably by their
  #   +inspect+ output instead of raising.
  #   Defaults to +false+.
  #   See +ActiveExperiment::RunKey+ for why that's unsafe.
  #
  # [+log_context+]
  #   Whether the log subscriber includes experiment contexts in its output.
  #   Defaults to +false+
  #
  # [+log_query_tags_around_run+]
  #   Register the +:experiment+ query log tag, which attributes queries made
  #   during an experiment run to the experiment.
  #   Defaults to +true+
  #   (requires +config.active_record.query_log_tags_enabled+ to be on as well)
  #
  # [+logger+]
  #   The logger Active Experiment writes to. Setting it to +nil+ turns off
  #   logging.
  #   Defaults to +Rails.logger+
  #
  # Options are applied by sending each one to +ActiveExperiment+ or to
  # +ActiveExperiment::Base+, so an option that isn't listed here is ignored
  # rather than raising.
  class Railtie < Rails::Railtie # :nodoc:
    def self.default_digest_secret_key(app)
      app.secret_key_base
    rescue ArgumentError
      nil
    end

    config.active_experiment = ActiveSupport::OrderedOptions.new
    config.active_experiment.custom_rollouts = {}
    config.active_experiment.log_query_tags_around_run = true

    rake_tasks do
      load "active_experiment/tasks.rake"
    end

    initializer "active_experiment.logger" do
      ActiveSupport.on_load(:active_experiment) { ActiveExperiment.logger = ::Rails.logger }
    end

    initializer "active_experiment.custom_rollouts" do |app|
      config.after_initialize do
        app.config.active_experiment.custom_rollouts.each do |name, rollout|
          ActiveExperiment::Rollouts.register(name, rollout)
        end
      end
    end

    initializer "active_experiment.set_configs" do |app|
      options = app.config.active_experiment
      config.after_initialize do
        options.digest_secret_key ||= Railtie.default_digest_secret_key(app)

        ActiveSupport.on_load(:active_experiment) do
          options.each do |k, v|
            setter = "#{k}="
            if ActiveExperiment.respond_to?(setter)
              ActiveExperiment.send(setter, v)
            elsif respond_to?(setter)
              send(setter, v)
            end
          end
        end
      end

      ActiveSupport.on_load(:action_dispatch_integration_test) do
        include ActiveExperiment::TestHelper
      end
    end

    initializer "active_experiment.query_log_tags" do |app|
      query_logs_tags_enabled = app.config.respond_to?(:active_record) &&
        app.config.active_record.query_log_tags_enabled &&
        app.config.active_experiment.log_query_tags_around_run

      if query_logs_tags_enabled
        app.config.active_record.query_log_tags |= [:experiment]

        ActiveSupport.on_load(:active_record) do
          # Assigned rather than mutated: the taggings hash is frozen, both as
          # its default and again on every assignment, so +[]=+ raises. Merging
          # either way around leaves both this tagging and Active Record's own
          # in place, so it doesn't matter which of us registers first.
          ActiveRecord::QueryLogs.taggings = ActiveRecord::QueryLogs.taggings.merge(
            experiment: ->(context) { context[:experiment]&.class&.name }
          )
        end
      end
    end
  end
end
