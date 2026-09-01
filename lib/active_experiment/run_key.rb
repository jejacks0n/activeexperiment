# frozen_string_literal: true

require "date"
require "digest/sha2"

module ActiveExperiment
  # == Run Keys
  #
  # SHA2 is used to generate a hexdigest from an experiment context. This
  # is generally referred to as the run key and can be used as the cache key
  # and for variant assignment.
  #
  # For this to be meaningful, the digest has to be stable, meaning that the
  # same context must produce the same run key in every process, forever. Two
  # rules follow from that:
  #
  # - Hashes are digested in a sorted order, so the order the keys happen to be
  #   written in at a given call site can't change the result, so these would
  #   produce the same run key:
  #
  #   MyExperiment.run(account: account, user: user)
  #   MyExperiment.run(user: user, account: account)
  #
  # - And objects that can't be identified stably are rejected rather than
  #   silently digested by their +inspect+ output, which embeds a memory
  #   address that changes every process. Contexts should be built from
  #   +GlobalID::Identification+ objects (any Active Record model) and
  #   primitives. You can disable this by configuring:
  #
  #   ActiveExperiment::Base.unsafe_context_digest = true
  #
  # You can configure the details used in generating the digest by specifying a
  # secret key and a bit length. The secret key is used to salt the digest, and
  # the bit length is used to determine the length of the digest.
  #
  # The secret key will default to +Rails.application.secret_key_base+ when
  # possible, and can be configured by:
  #
  #   ActiveExperiment::Base.digest_secret_key = ENV["AE_SECRET_KEY"]
  #
  # The bit length can be set to 256, 384, or 512. The default is 256, and this
  # can be configured by:
  #
  #   ActiveExperiment::Base.digest_bit_length = 256
  module RunKey
    extend ActiveSupport::Concern

    # Included in every digest, and bumped whenever the way run keys are
    # generated changes. Without it a change to the algorithm would silently
    # reassign variants with no way to tell old keys from new ones.
    DIGEST_VERSION = "2"
    private_constant :DIGEST_VERSION

    # Types that inspect to the same string in every process, and so can be
    # digested directly.
    STABLE_TYPES = [
      NilClass, TrueClass, FalseClass, String, Symbol, Numeric, Time, Date
    ].freeze
    private_constant :STABLE_TYPES

    included do
      class_attribute :digest_secret_key, instance_writer: false, instance_predicate: false
      class_attribute :digest_bit_length, instance_writer: false, instance_predicate: false, default: 256
      class_attribute :unsafe_context_digest, instance_writer: false, instance_predicate: false, default: false
      private :digest_secret_key, :digest_bit_length, :unsafe_context_digest
    end

    private
      def run_key_hexdigest(source)
        ingredients = [DIGEST_VERSION, name, digest_secret_key, digest_ingredient(source)]

        ::Digest::SHA2.new(digest_bit_length).hexdigest(ingredients.join("|"))
      end

      # Renders a value as a string that's identical for equivalent contexts.
      def digest_ingredient(value)
        case value
        when Hash
          # Sorted, so key order at the call site can't change the digest.
          pairs = value.map { |k, v| "#{digest_ingredient(k)}=>#{digest_ingredient(v)}" }
          "{#{pairs.sort.join(",")}}"
        when Array
          # Not sorted: order is meaningful in an array.
          "[#{value.map { |v| digest_ingredient(v) }.join(",")}]"
        when GlobalID::Identification
          global_id_ingredient(value)
        when *STABLE_TYPES
          value.inspect
        else
          unstable_ingredient(value)
        end
      end

      def global_id_ingredient(value)
        value.to_global_id.to_s
      rescue StandardError => error
        # Most often a record that hasn't been saved yet, and so has no id to
        # identify it by. Whatever the reason, there's no stable identity here.
        unstable_ingredient(value, because: "#{error.class}: #{error.message}")
      end

      def unstable_ingredient(value, because: nil)
        return value.inspect if unsafe_context_digest

        raise ArgumentError, <<~MESSAGE.squish
          Unable to generate a stable run key from the #{value.class} in the
          #{name} context#{because ? " (#{because})" : ""}. Experiment contexts
          should be built from GlobalID::Identification objects and primitives.
          Set `ActiveExperiment::Base.unsafe_context_digest = true` to fall back
          to the object's inspect output instead, accepting that the run key
          can change every process and variant assignment won't be consistent.
        MESSAGE
      end
  end
end
