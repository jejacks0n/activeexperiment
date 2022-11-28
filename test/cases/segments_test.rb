# frozen_string_literal: true

require "helper"

class SegmentsTest < ActiveSupport::TestCase
  test "no segmentation" do
    assert_equal "control", SubjectExperiment.run
  end

  test "segmenting using a block" do
    assert_equal "red", SubjectExperiment.run(segment_into_red: true)
  end

  test "segmenting using a method" do
    assert_equal "blue", SubjectExperiment.run(segment_into_blue: true)
  end

  test "segmenting with conditional callback options" do
    assert_equal "control", SubjectExperiment.run(
      segment_into_green: true,
      really_segment: false
    )

    assert_equal "green", SubjectExperiment.run(
      segment_into_green: true,
      really_segment: true
    )
  end

  test "segmenting with minimal conditional" do
    assert_equal "green", SubjectExperiment.run(segment_by_minimal_if: true)
  end

  test "trying to define a segment rule into an unknown variant" do
    error = assert_raises(ArgumentError) do
      SubjectExperiment.segment(into: :missing) {}
    end

    assert_equal "Unknown missing variant", error.message
  end

  class SubjectExperiment < ActiveExperiment::Base
    control { "control" }
    variant(:red) { "red" }
    variant(:blue) { "blue" }
    variant(:green) { "green" }

    segment :if_blue, into: :blue

    segment(into: :red) do
      context[:segment_into_red]
    end

    segment ->(e) { e.context[:really_segment] },
      if: -> { context[:segment_into_green] },
      into: :green

    segment into: :green, if: -> { context[:segment_by_minimal_if] }

    def self.segment(...)
      super
    end

    private
      def if_blue
        context[:segment_into_blue]
      end
  end
end
