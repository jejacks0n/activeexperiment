# frozen_string_literal: true

module ActiveExperiment
  # == Capturable Mixin
  #
  # This module adds the capability to capture and render the results of an
  # experiment in the order that would make sense when rendering in a view.
  #
  # Add it to experiments that should capture and render their results.
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     include ActiveExperiment::Capturable
  #   end
  #
  # The order of experiment execution is to call the run block before resolving
  # the variant, and subsequently calling the appropriate variant block. This
  # order allows the run block to set details that can be used in resolving the
  # variant and/or to set the variant directly -- or to skip the experiment
  # altogether even.
  #
  # The order of how code is implemented in the run block shouldn't matter to
  # the experiment (generally speaking) and the two following examples do the
  # same thing:
  #
  #   MyExperiment.run do |experiment|
  #     experiment.skip if current_user.admin?
  #     experiment.on(:red) { "red override" }
  #   end
  #
  #   MyExperiment.run do |experiment|
  #     experiment.on(:red) { "red override" }
  #     experiment.skip if current_user.admin?
  #   end
  #
  # This is desirable most of the time, for important performance reasons, but
  # can also be undesirable when running an experiment in a view and wanting to
  # capture the markup in the expected order.
  #
  # In the following example the container div is shared between the variants,
  # and duplicating it (potentially several times) in each variant block would
  # be undesirable:
  #
  #   <%== MyExperiment.set(capture: self).run do |experiment| %>
  #     <div class="container">
  #       <%= experiment.on(:red) do %>
  #         <button class="red-pill">Red</button>
  #       <% end %>
  #       <%= experiment.on(:blue) do %>
  #         <button class="blue-pill">Blue</button>
  #       <% end %>
  #     </div>
  #   <% end %>
  #
  # There are a couple important things to note about the above example to
  # ensure capturing works as expected:
  #
  # 1. The `ActiveExperiment::Capturable` module has been included in the
  #    experiment class.
  #
  # 2. The use of +==+ in the ERB tag is important because Active Experiment
  #    doesn't try to determine if the experiment results are safe to render,
  #    and it's up to the caller to make them html safe again.
  #
  # 3. The +capture+ option that's passed to the +set+ method tells Active
  #    Experiment to use the view context's +capture+ logic to build the output
  #    in the expected order.
  #
  # 4. Each variant block should use +=+ on the ERB tag to ensure the variant
  #    content ends up where it should be in the output.
  #
  # In HAML, the above example would look like:
  #
  #   != MyExperiment.set(capture: self).run do |experiment|
  #     %div.container
  #       = experiment.on(:red) do
  #         %button.red-pill Red
  #       = experiment.on(:blue) do
  #         %button.blue-pill Blue
  module Capturable
    extend ActiveSupport::Concern

    def on(*variant_names, &block)
      super

      "{{#{variant_names.join("}}{{")}}}"
    end

    def run(&block)
      super

      if capturable?
        @results = @capture.to_s.gsub(/{{([\w]+)}}/) { $1 == variant.to_s ? @results : "" }
      else
        @results
      end
    end

    private
      def resolve_results
        @results = capture { super }
      end

      def call_run_block(&block)
        @capture = capture { super }
      end

      def capture(&block)
        return yield unless capturable?

        @options[:capture].capture(&block)
      end

      def capturable?
        !!@options[:capture]&.respond_to?(:capture)
      end
  end
end
