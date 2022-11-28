# frozen_string_literal: true

require "rails/generators/named_base"

module Rails # :nodoc:
  module Generators # :nodoc:
    class ExperimentGenerator < Rails::Generators::NamedBase # :nodoc:
      class_option :parent, type: :string, default: "ApplicationExperiment", desc: "The parent class for the generated experiment"
      class_option :skip_comments, type: :boolean, default: false, desc: "Omit helpful comments from generated files"

      argument :variants, type: :array, default: %w[control treatment], banner: "variant variant"

      check_class_collision suffix: "Experiment"

      hook_for :test_framework

      def self.default_generator_root
        __dir__
      end

      def create_experiment_file
        template "experiment.rb", File.join("app/experiments", class_path, "#{file_name}_experiment.rb")

        in_root do
          if behavior == :invoke && !File.exist?(application_experiment_file_name)
            template "application_experiment.rb", application_experiment_file_name
          end
        end
      end

      private
        def parent_class_name
          options[:parent]
        end

        def variant_names
          @variant_names ||= variants.map { |variant| variant.to_s.underscore }
        end

        def file_name
          @_file_name ||= super.sub(/_experiment\z/i, "")
        end

        def application_experiment_file_name
          @application_experiment_file_name ||= if mountable_engine?
            "app/experiments/#{namespaced_path}/application_experiment.rb"
          else
            "app/experiments/application_experiment.rb"
          end
        end
    end
  end
end
