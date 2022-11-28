# frozen_string_literal: true

module ActiveExperiment
  # == Segmentation
  #
  # Segment rules are used to assign a specific variant in certain cases, and
  # allows customized logic when resolving variants. Rules are evaluated in the
  # order they're defined, and if a rule returns +true+, subsequent rules will
  # be skipped.
  #
  # Segment rules are callbacks behind the scenes, so they accept the same set
  # of options as other common Rails callbacks, including +if:+ and +unless:+
  # which allows creating more complex rules.
  #
  # In the following example, any context with the name "Richard" will be
  # assigned the red variant, and any context created more than 7 days ago will
  # be assigned the blue variant.
  #
  #   class MyExperiment < ActiveExperiment::Base
  #     variant(:red) { "red" }
  #     variant(:blue) { "blue" }
  #
  #     segment :old_accounts, into: :red
  #     segment(into: :blue) { context.name == "Richard" }
  #     segment into: :red, if: :opted_in?
  #
  #     private
  #
  #     def old_accounts
  #       context.created_at < 1.week.ago
  #     end
  #
  #     def opted_in?
  #       context.opted_in?
  #     end
  #   end
  #
  # This experiment now depends on something like a +User+ record being
  # provided as context, since the context is now used to determine the variant
  # through segment rules.
  #
  # Since rules are evaluated in the order they're defined, and the variant of
  # the first rule to return true will be assigned. In the above example, this
  # means that all old accounts will be put into the red variant regardless of
  # being named Richard, and Richard can never "opt in" for the red variant.
  module Segments
    extend ActiveSupport::Concern
    include ActiveSupport::Callbacks

    included do
      define_callbacks :segment
      private :_segment_callbacks, :_run_segment_callbacks
    end

    # These methods will be included into any Active Experiment object, adding
    # the segment method.
    module ClassMethods
      private
        def segment(*filters, into:, **options, &block)
          raise ArgumentError, "Unknown #{into} variant" unless variants[into.to_sym]

          filters = filters.unshift(block)
          set_callback_with_target(:segment, *filters, default: -> { true }, **options) do |target, callback|
            target.set(variant: into) && throw(:abort) if true == callback.call(target, nil)
          end
        end
    end
  end
end
