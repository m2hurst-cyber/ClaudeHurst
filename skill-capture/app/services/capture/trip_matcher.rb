module Capture
  # Finds "trips": each time someone did a whole skill, in order.
  #
  # Each person's events are lined up in time and consecutive repeats of one step are
  # merged (keeping when the run started and ended). A trip is a contiguous run of a
  # route's steps. Where several routes match at once, the longest wins and overlaps
  # are dropped. Each trip knows the trip before it by the same person, so we can
  # measure the *wait* between finishing one skill and starting the next.
  class TripMatcher
    # received_at: when the server got the trip's last event (events can arrive late, e.g. offline Office clients)
    Trip = Struct.new(:key, :actor, :started_at, :ended_at, :received_at, :prev, keyword_init: true) do
      def duration = ended_at - started_at
      # Wait since the previous (different) skill ended, if it was within the gap.
      def wait(gap) = prev && prev.key != key && (started_at - prev.ended_at) <= gap ? [started_at - prev.ended_at, 0].max : 0
    end
    Step = Struct.new(:key, :started_at, :ended_at, :received_at)

    # routes: [[key, [action_key, ...]], ...]
    def self.call(routes, since:) = new(routes, since).call

    def initialize(routes, since)
      @routes = routes.reject { |_, steps| steps.size < 2 }
      @since = since
    end

    # => array of Trip, in time order per person
    def call
      return [] if @routes.empty?
      timelines.flat_map do |actor, steps|
        keys = steps.map(&:key)
        matches = @routes.flat_map do |key, route|
          (0..keys.size - route.size).select { |i| keys[i, route.size] == route }.map { |i| [i, i + route.size - 1, key] }
        end
        prev = nil
        non_overlapping(matches).map do |s, e, key|
          prev = Trip.new(key: key, actor: actor, started_at: steps[s].started_at, ended_at: steps[e].ended_at,
                          received_at: steps[s..e].map(&:received_at).max, prev: prev)
        end
      end
    end

    private

    def timelines
      UsageEvent.where("occurred_at >= ?", @since).order(:actor_key, :occurred_at, :id)
                .pluck(:actor_key, :action_key, :occurred_at, :created_at)
                .chunk_while { |a, b| a[0] == b[0] }
                .map do |evs|
                  steps = evs.chunk_while { |a, b| a[1] == b[1] }.map { |run| Step.new(run.first[1], run.first[2], run.last[2], run.map(&:last).max) }
                  [evs.first[0], steps]
                end
    end

    def non_overlapping(matches)
      taken_until = -1
      matches.sort_by { |s, e, _| [s, -(e - s)] }.each_with_object([]) do |m, out|
        next if m[0] <= taken_until
        out << m
        taken_until = m[1]
      end
    end
  end
end
