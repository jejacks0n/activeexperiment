# frozen_string_literal: true

require "helper"

class CoreTest < ActiveSupport::TestCase
  test "setting multiple options" do
    expect = { foo: :bar, bar: :qux, baz: :foo }
    result = SubjectExperiment.set(variant: :hash, foo: :bar, bar: :baz).run do |experiment|
      experiment.set(bar: :qux, baz: :foo)
    end

    assert_equal expect, result
  end

  class SubjectExperiment < ActiveExperiment::Base
    variant(:hash) { @options }
    variant(:json) { @options.to_json }
  end
end
