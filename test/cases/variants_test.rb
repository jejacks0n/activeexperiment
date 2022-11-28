# frozen_string_literal: true

require "helper"

class VariantsTest < ActiveSupport::TestCase
  test "adding variants when inheriting" do
    AddVariantExperiment = Class.new(SubjectExperiment) do
      variant(:green) { "green added" }
    end

    assert_equal "control", AddVariantExperiment.run
    assert_equal "red", AddVariantExperiment.set(variant: :red).run
    assert_equal "blue", AddVariantExperiment.set(variant: :blue).run
    assert_equal "green added", AddVariantExperiment.set(variant: :green).run
  end

  test "overriding variants when inheriting" do
    OverrideVariantExperiment = Class.new(SubjectExperiment) do
      control(override: true) { "control override" }
      variant(:red, override: true) { "red override" }
    end

    assert_equal "control override", OverrideVariantExperiment.run
    assert_equal "red override", OverrideVariantExperiment.set(variant: :red).run
    assert_equal "blue", OverrideVariantExperiment.set(variant: :blue).run
  end

  test "trying to register an already registered variant" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.variant(:red) {}
    end

    assert_equal "The :red variant is already registered. "\
      "Provide `override: true` or `add: true` to make changes to it.",
      error.message
  end

  test "trying to override an unknown variant" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.variant(:green, override: true) {}
    end

    assert_equal "Unable to override or add to unknown :green variant", error.message
  end

  test "trying to add and override at the same time" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.variant(:red, override: true, add: true) {}
    end

    assert_equal "Provide either `override: true` or `add: true` but not both", error.message
  end

  test "registering variants with multiple steps" do
    MultipleStepExperiment = Class.new(SubjectExperiment) do
      variant(:steps, -> { context << "block"; "block" }, :step1, :step2)

      private
        def step1
          context << "step1"
          "step1"
        end

        def step2
          context << "step2"
          "step2"
        end
    end

    assert_equal "step2", MultipleStepExperiment.set(variant: :steps).run(collector = [])
    assert_equal ["block", "step1", "step2"], collector
  end

  test "registering additional steps for an existing variant" do
    AdditionalStepsExperiment = Class.new(SubjectExperiment) do
      variant(:blue, :new_step, add: true, prepend: true)

      def new_step
        context << "new_step"
        "new_step"
      end
    end

    assert_equal "blue", AdditionalStepsExperiment.set(variant: :blue).run(collector = [])
    assert_equal ["new_step", "blue"], collector
  end

  test "specifying a default variant" do
    DefaultVariantExperiment = Class.new(SubjectExperiment) do
      use_default_variant :blue

      def skipped?
        true
      end
    end

    assert_equal "blue", DefaultVariantExperiment.run
  end

  test "trying to specify a default variant that isn't registered" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.use_default_variant(:purple)
    end

    assert_equal "Unknown :purple variant", error.message
  end

  SubjectExperiment = Class.new(ActiveExperiment::Base) do
    control { "control" }
    variant(:red) { "red" }
    variant(:blue, :blue)

    def self.variant(...)
      super
    end

    def self.use_default_variant(...)
      super
    end

    def blue
      context << "blue" if context.respond_to?(:<<)
      "blue"
    end
  end
end
