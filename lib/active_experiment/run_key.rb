# frozen_string_literal: true

require "digest/sha2"

module ActiveExperiment
  # == Run Keys
  #
  # SHA2 is used to generate a hexdigest from an experiment context. This
  # is generally referred to as the run key and can be used as the cache key
  # and for variant assignment.
  #
  # You can configure the details used in generating the digest by specifying a
  # secret key and a bit length. The secret key is used to salt the digest, and
  # the bit length is used to determine the length of the digest.
  #
  # The secret key will default to +Rails.application.secrets.secret_key_base+
  # when possible, and can be configured by:
  #
  #   ActiveExperiment::Base.digest_secret_key = ENV["AE_SECRET_KEY"]
  #
  # The bit length can be set to 256, 384, or 512. The default is 256, and this
  # can be configured by:
  #
  #   ActiveExperiment::Base.digest_bit_length = 256
  module RunKey
    extend ActiveSupport::Concern

    included do
      class_attribute :digest_secret_key, instance_writer: false, instance_predicate: false
      class_attribute :digest_bit_length, instance_writer: false, instance_predicate: false, default: 256
      private :digest_secret_key, :digest_bit_length
    end

    private
      def run_key_hexdigest(source)
        source = source.keys + source.values if source.is_a?(Hash)
        ingredients = Array(source).map { |value| identify_object(value).inspect }
        ingredients.unshift(name, digest_secret_key)

        ::Digest::SHA2.new(digest_bit_length).hexdigest(ingredients.join('|'))
      end

      def identify_object(arg)
        case arg
        when GlobalID::Identification
          arg.to_global_id.to_s rescue arg
        else
          # TODO: maybe we should strip things out that might cause issues?
          #   e.g. `#<User:0x00007f9b0a0b0e60>` is going to change every run,
          #   and we don't want that to happen by accident.
          arg
        end
      end
  end
end
