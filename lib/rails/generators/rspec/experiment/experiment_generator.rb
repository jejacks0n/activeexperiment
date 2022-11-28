# require "generators/rspec"

module Rspec # :nodoc:
  module Generators # :nodoc:
    class ExperimentGenerator < Rails::Generators::NamedBase # :nodoc:
      source_root(File.expand_path("templates", __dir__))

      def create_spec_file
        template "experiment_spec.rb", File.join("spec/experiments", class_path, "#{file_name}_experiment_spec.rb")
      end

      private
        def file_name
          @_file_name ||= super.sub(/_experiment\z/i, "")
        end

    end
  end
end
