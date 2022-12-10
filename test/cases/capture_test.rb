# frozen_string_literal: true

require "helper"

class CaptureTest < ActiveSupport::TestCase
  include ViewHelpers

  test "capturing the experiment run" do
    result = SubjectExperiment.set(capture: self).run do |experiment|
      "<div>" +
        experiment.on(:red) { "<span>red</span>" } +
        experiment.on(:blue) { "<span>blue</span>" } +
      "</div>"
    end

    assert_equal "<div><span>red</span></div>", result
  end

  test "trying to capture when not capturable" do
    UncapturableExperiment = Class.new(SubjectExperiment) do
      def capturable?
        false
      end
    end

    result = UncapturableExperiment.set(capture: self).run do |experiment|
      "<div>" +
        experiment.on(:red) { "<span>red</span>" } +
        experiment.on(:blue) { "<span>blue</span>" } +
      "</div>"
    end

    assert_equal "<span>red</span>", result
  end

  class SubjectExperiment < ActiveExperiment::Base
    include ActiveExperiment::Capturable

    variant(:red) { "red" }
    variant(:blue) { "blue" }
  end
end
