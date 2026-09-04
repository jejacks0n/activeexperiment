# frozen_string_literal: true

require "date"

module ActiveExperiment
  module Recorders
    # == Base Recorder
    #
    # Recorders allow reporting on the recorded data of experiments.
    #
    # This class handles the part every recorder needs, which is not writing on
    # the run path. Runs accumulate into per process counters and are written
    # out in batches.
    #
    # == What Gets Recorded
    #
    # * A registry entry per experiment. This includes the variants it has
    #   defined, the rollout it uses, the cache store, and when it was first
    #   and last seen being run.
    # * Daily rollups per variant. This allows us to see how many runs, how
    #   many were skipped, how many runs raised exceptions, and how the variant
    #   came to be assigned.
    # * Overlaps. Experiments can overlap and be nested, so this allows us to
    #   see how often two experiments were run together, per pair of variants,
    #   and how often one was nested inside the other.
    #
    # == Flushing
    #
    # Counters are written out when enough runs have accumulated or enough time
    # has passed, both of which are configurable:
    #
    #   use_recorder :active_record, flush_interval: 60, flush_threshold: 1_000
    #
    # A process that's killed loses what it's accumulated.
    #
    # +flush!+ writes immediately however, so take advantage of that if you
    # need. For example, in puma, you might want to do the following:
    #
    #    on_worker_shutdown { ActiveExperiment::Base.recorder.flush! }
    #
    # == Writing a Recorder
    #
    # Subclass this and implement +write+ for the write side, and +experiments+,
    # +rollups+ and +overlaps+ for the read side.
    class BaseRecorder
      # Seconds between flushes, when the threshold hasn't been reached first.
      DEFAULT_FLUSH_INTERVAL = 30
      private_constant :DEFAULT_FLUSH_INTERVAL

      # Buffered runs that force a flush, whatever the interval says.
      DEFAULT_FLUSH_THRESHOLD = 500
      private_constant :DEFAULT_FLUSH_THRESHOLD

      # The provenance counters, one per +variant_source+. They sum to the run
      # count, so a variant whose runs don't add up is a variant being assigned
      # some way this doesn't know about.
      SOURCES = [:preset, :skipped, :cached, :segment, :rollout, :default, :concluded].freeze

      attr_reader :flush_interval, :flush_threshold, :options

      def initialize(flush_interval: DEFAULT_FLUSH_INTERVAL, flush_threshold: DEFAULT_FLUSH_THRESHOLD, **options)
        @flush_interval = flush_interval
        @flush_threshold = flush_threshold
        @options = options

        @lock = Mutex.new
        @last_flush = monotonic_now
        clear_buffer
      end

      # Whether this recorder records anything.
      def recording?
        true
      end

      # Counts a single run of an experiment.
      #
      # Called from ActiveExperiment::RecordSubscriber for every run.
      def record_run(experiment, errored: false)
        @lock.synchronize do
          register(experiment)

          counts = @runs[[experiment.name, experiment.variant.to_s, Date.current]]
          counts[:runs] += 1
          counts[:skipped] += experiment.skipped_run? ? 1 : 0
          counts[:errored] += errored ? 1 : 0

          source = experiment.variant_source
          counts[:"from_#{source}"] += 1 if SOURCES.include?(source)

          @pending += 1
        end

        flush_if_due
      end

      # Counts the experiments that were run together.
      #
      # Called with everything ActiveExperiment::Executed collected.
      #
      # Pairs are counted per variant, because that's what makes them readable
      # afterwards: two experiments overlapping is expected and mostly fine,
      # but one experiment's variants being distributed differently inside each
      # of another's is the two of them interfering with each other.
      def record_overlap(experiments)
        pairs = overlap_pairs(experiments)
        return if pairs.empty?

        @lock.synchronize do
          pairs.each do |pair, nested|
            counts = @overlaps[pair]
            counts[:count] += 1
            counts[:nested_count] += nested ? 1 : 0
          end

          @pending += 1
        end

        flush_if_due
      end

      # Writes whatever has accumulated, and returns whether there was anything
      # to write.
      def flush!
        registry, runs, overlaps = @lock.synchronize do
          buffered = [@registry, @runs, @overlaps]
          clear_buffer
          buffered
        end

        @last_flush = monotonic_now
        return false if registry.empty? && runs.empty? && overlaps.empty?

        write(registry, runs, overlaps)
        true
      end

      # === Reading
      #
      # The interface a report reads through. Every one of these returns rows as
      # hashes with symbol keys, rather than whatever the underlying store keeps
      # them in, so that something reading a recorder doesn't have to know which
      # kind it is.
      #
      # Reading is optional. A recorder that forwards runs somewhere else and
      # can't answer questions about them is a reasonable recorder, so these
      # return nothing rather than raising. Writing is the part a recorder has
      # to implement; being able to answer questions afterwards isn't.

      # Every experiment that's been recorded, including ones whose class no
      # longer exists -- an experiment that was deleted while its assignments
      # are still cached is exactly the thing worth noticing.
      def experiments
        []
      end

      # One recorded experiment, or +nil+ if it's never been recorded.
      def experiment(experiment_name)
        nil
      end

      # Changes what's recorded about an experiment, creating the row if it
      # doesn't exist yet. Unlike counts these aren't deltas, and somebody is
      # waiting to see them take effect, so they aren't buffered.
      #
      # Unlike the reads above this one raises: a recorder that can't be told
      # anything isn't much of a recorder.
      def update_experiment(experiment_name, **attributes)
        raise NotImplementedError
      end

      # Daily variant rollups for one experiment, oldest first.
      def rollups(experiment_name, since: nil)
        []
      end

      # Every other experiment this one has been run alongside.
      def overlaps(experiment_name)
        []
      end

      private
        # Persists a flushed buffer. Counts are deltas and have to be added to
        # whatever is already stored, not written over it, since every process
        # is flushing its own.
        def write(registry, runs, overlaps)
          raise NotImplementedError
        end

        # Describing an experiment means asking its rollout to describe itself,
        # so it's done once per flush window rather than once per run.
        def register(experiment)
          @registry[experiment.name] ||= describe(experiment.class)
        end

        def describe(experiment_class)
          {
            class_name: experiment_class.name,
            variant_names: experiment_class.variants.keys,
            default_variant: experiment_class.default_variant,
            # Rollouts aren't required to describe themselves. An experiment can
            # use anything that responds to +skipped_for+ and +variant_for+,
            # including itself.
            rollout: experiment_class.rollout.try(:describe),
            cache_store: experiment_class.cache_store.class.name
          }
        end

        # The distinct pairs of experiments in a set that was run together, as
        # `[[name_a, variant_a, name_b, variant_b], nested]`.
        #
        # Ordered so that a pair is the same key whichever order the two were
        # run in, and deduplicated so that an experiment run several times in
        # one request with different contexts counts once per variant it landed
        # on rather than once per run.
        def overlap_pairs(experiments)
          return {} unless experiments && experiments.length > 1

          nested = nested_pairs(experiments)
          identities = experiments.map { |e| [e.name, e.variant.to_s] }.uniq

          identities.combination(2).each_with_object({}) do |(a, b), pairs|
            # The same experiment twice, on different contexts, isn't an
            # overlap with itself.
            next if a.first == b.first

            key = pair_key(a, b)
            pairs[key] = nested.include?(key)
          end
        end

        def nested_pairs(experiments)
          experiments.filter_map do |experiment|
            parent = experiment.nested_within
            next unless parent

            pair_key([experiment.name, experiment.variant.to_s], [parent.name, parent.variant.to_s])
          end
        end

        def pair_key(a, b)
          (a <=> b) <= 0 ? [*a, *b] : [*b, *a]
        end

        def flush_if_due
          flush! if @pending >= flush_threshold || monotonic_now - @last_flush >= flush_interval
        end

        def clear_buffer
          @registry = {}
          @runs = Hash.new { |hash, key| hash[key] = Hash.new(0) }
          @overlaps = Hash.new { |hash, key| hash[key] = Hash.new(0) }
          @pending = 0
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
    end
  end
end
