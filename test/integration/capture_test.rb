# frozen_string_literal: true

require "integration_helper"

class CapturedExperiment < ActiveExperiment::Base
  include ActiveExperiment::Capturable

  variant(:red) { "red" }
  variant(:blue) { "blue" }
end

# The unit tests cover capturing against a stand in that just yields, which
# can't say anything about the part that actually matters: what Action View's
# capture hands back, and what's left of it once the placeholders are swapped.
class CaptureIntegrationTest < ActiveSupport::TestCase
  def render_template(template)
    ApplicationController.renderer.render(inline: template)
  end

  def view_context
    @view_context ||= ApplicationController.new.view_context
  end

  test "rendering the shared markup once, around only the assigned variant" do
    output = render_template(<<~ERB)
      <%= CapturedExperiment.set(capture: self, variant: :red).run(id: 1) do |experiment| %>
        <div class="container">
          <%= experiment.on(:red) do %>
            <button class="red-pill">Red</button>
          <% end %>
          <%= experiment.on(:blue) do %>
            <button class="blue-pill">Blue</button>
          <% end %>
        </div>
      <% end %>
    ERB

    assert_includes output, "red-pill"
    assert_not_includes output, "blue-pill"
    assert_equal 1, output.scan("container").length
  end

  test "leaving no placeholder behind for the variants that weren't assigned" do
    output = render_template(<<~ERB)
      <%= CapturedExperiment.set(capture: self, variant: :blue).run(id: 1) do |experiment| %>
        <div>
          <%= experiment.on(:red) do %>red<% end %>
          <%= experiment.on(:blue) do %>blue<% end %>
        </div>
      <% end %>
    ERB

    assert_no_match(/\{\{.*\}\}/, output)
    assert_includes output, "blue"
    assert_not_includes output, "red"
  end

  test "keeping content interpolated inside a variant escaped" do
    output = render_template(<<~ERB)
      <%= CapturedExperiment.set(capture: self, variant: :red).run(id: 1) do |experiment| %>
        <div>
          <%= experiment.on(:red) do %>
            <span><%= "<script>alert(1)</script>" %></span>
          <% end %>
        </div>
      <% end %>
    ERB

    assert_includes output, "&lt;script&gt;"
    assert_not_includes output, "<script>"
  end

  test "a capturable experiment run without a run block" do
    # There's no surrounding markup to substitute into, so this should render
    # the variant the same way a non capturable experiment would.
    output = render_template(<<~ERB)
      <%= CapturedExperiment.set(capture: self, variant: :red).run(id: 1) %>
    ERB

    assert_equal "red", output.strip
  end

  test "a run block that renders nothing" do
    result = CapturedExperiment.set(capture: view_context, variant: :red).run(id: 1) { }

    assert_equal "red", result
  end

  test "the captured result is html safe" do
    result = CapturedExperiment.set(capture: view_context, variant: :red).run(id: 1) do |experiment|
      experiment.on(:red) { "red" }
    end

    assert_predicate result, :html_safe?
  end

  test "a raw tag still renders it the way earlier versions required" do
    safe = render_template(<<~ERB)
      <%= CapturedExperiment.set(capture: self, variant: :red).run(id: 1) do |experiment| %>
        <div class="container"><%= experiment.on(:red) do %>red<% end %></div>
      <% end %>
    ERB

    raw = render_template(<<~ERB)
      <%== CapturedExperiment.set(capture: self, variant: :red).run(id: 2) do |experiment| %>
        <div class="container"><%= experiment.on(:red) do %>red<% end %></div>
      <% end %>
    ERB

    assert_includes safe, "<div class=\"container\">"
    assert_equal safe, raw
  end

  test "running a second time returns the first result" do
    experiment = CapturedExperiment.new(id: 1).set(capture: view_context, variant: :red)
    first = experiment.run { |ex| ex.on(:red) { "red" } }

    assert_equal first, experiment.run
  end

  test "the placeholders don't survive into the output" do
    result = CapturedExperiment.set(capture: view_context, variant: :red).run(id: 1) do |experiment|
      experiment.on(:red) { "red" }
      experiment.on(:blue) { "blue" }
    end

    assert_no_match(/\{\{/, result)
  end
end
