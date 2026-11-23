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
      counts = Hash.new(0)
      TripMatcher.call(self.class.routes, since: @since).each do |trip|
        prev = trip.prev
        next unless prev && prev.key != trip.key && trip.started_at - prev.ended_at <= @gap
        counts[[prev.key, trip.key]] += 1
      end
      counts
    end

    # Every published skill and open detected workflow, as [key, steps].
    def self.routes
      Skill.published.pluck(:name, :source).map { |n, s| [n, Array(s["workflow"])] } +
        SkillCandidate.open.where(origin: "detected").map { |c| [SkillLink.candidate_key(c), c.steps] }
    end
  end
end
