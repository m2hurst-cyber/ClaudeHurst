module Capture
  # Finds which skills people do one after another, end to end, and stores those
  # transitions as observed SkillLinks with a traffic count (the route map's roads).
  #
  # For each person, their events (lookback window) are collapsed into one timeline.
  # Every published skill and open candidate is matched where its steps occur
  # contiguously. Consecutive matches (by start time) that are different skills and
  # no more than CHAIN_GAP apart count as one transition A → B.
  class ChainDetector
    def self.call(**opts) = new(**opts).call

    def initialize(since: Config.lookback.ago, gap: Config.chain_gap, min_traffic: Config.min_chain_traffic)
      @since = since
      @gap = gap
      @min_traffic = min_traffic
    end

    def call
      transitions = detect
      SkillLink.transaction do
        SkillLink.observed.delete_all
        rows = transitions.select { |_, n| n >= @min_traffic }.map do |(a, b), n|
          { from_node: a, to_node: b, origin: "observed", traffic: n, created_at: Time.current, updated_at: Time.current }
        end
        SkillLink.insert_all(rows) if rows.any?
      end
      transitions
    end

    # => { [from_node, to_node] => count }
    def detect
      routes = Skill.published.pluck(:name, :source).map { |n, s| [n, Array(s["workflow"])] } +
               SkillCandidate.open.where(origin: "detected").map { |c| [SkillLink.candidate_key(c), c.steps] }
      routes.reject! { |_, steps| steps.size < 2 }
      return {} if routes.empty?

      counts = Hash.new(0)
      timelines.each do |events|
        keys = events.map(&:action_key)
        matches = routes.flat_map do |key, steps|
          occurrences(keys, steps).map { |i| [i, i + steps.size - 1, key] }
        end
        matches = non_overlapping(matches)
        matches.each_cons(2) do |(_, end_a, a), (start_b, _, b)|
          next if a == b
          next if events[start_b].occurred_at - events[end_a].occurred_at > @gap
          counts[[a, b]] += 1
        end
      end
      counts
    end

    private

    def timelines
      UsageEvent.where("occurred_at >= ?", @since).order(:actor_key, :occurred_at, :id)
                .select(:id, :actor_key, :action_key, :occurred_at).to_a
                .chunk_while { |a, b| a.actor_key == b.actor_key }
                .map { |evs| evs.chunk_while { |a, b| a.action_key == b.action_key }.map(&:first) }
    end

    def occurrences(keys, steps)
      (0..keys.size - steps.size).select { |i| keys[i, steps.size] == steps }
    end

    # Prefer the longest match at each position; drop matches overlapping an earlier one.
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
