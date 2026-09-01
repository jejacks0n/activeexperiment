# frozen_string_literal: true

require "global_id/railtie"
require "active_experiment"

module ActiveExperiment
  class Railtie < Rails::Railtie # :nodoc:
    def self.default_digest_secret_key(app)
      app.secret_key_base
    rescue ArgumentError
      nil
    end

    config.active_experiment = ActiveSupport::OrderedOptions.new
    config.active_experiment.custom_rollouts = {}
    config.active_experiment.log_query_tags_around_run = true

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
