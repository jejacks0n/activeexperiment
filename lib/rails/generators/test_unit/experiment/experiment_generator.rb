# frozen_string_literal: true

require "rails/generators/test_unit"

module TestUnit # :nodoc:
  module Generators # :nodoc:
    class ExperimentGenerator < Base # :nodoc:
      check_class_collision suffix: "ExperimentTest"
      source_root(File.expand_path("templates", __dir__))

      def create_test_file
        template "experiment_test.rb", File.join("test/experiments", class_path, "#{file_name}_experiment_test.rb")
      end

      private
        def file_name
          @_file_name ||= super.sub(/_experiment\z/i, "")
        end
    end
  end
end
