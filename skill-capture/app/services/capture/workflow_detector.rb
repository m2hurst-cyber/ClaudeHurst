module Capture
  # Mines the event stream for repeated multi-step workflows.
  #
  #   1. Split each actor's events into work sessions (new session key or idle gap).
  #   2. Collapse consecutive duplicate steps.
  #   3. Enumerate contiguous sequences of min..max steps that never repeat a step,
  #      counting occurrences without overlap.
  #   4. Keep sequences seen >= min_occurrences times by >= min_actors people.
  #   5. Keep only maximal sequences (drop A>B when A>B>C occurs as often).
  class WorkflowDetector
    Pattern = Struct.new(:steps, :occurrences, :actors, :domains, :first_seen_at, :last_seen_at, :examples, keyword_init: true) do
      def signature = SkillCandidate.signature_for(steps)
    end
    Result = Struct.new(:patterns, :created, :updated, keyword_init: true)

    def self.call(**opts) = new(**opts).call

    def initialize(since: Config.lookback.ago, min_occurrences: Config.min_occurrences, min_actors: Config.min_actors,
                   min_steps: Config.min_steps, max_steps: Config.max_steps, session_gap: Config.session_gap)
      @since = since
      @min_occurrences = min_occurrences
      @min_actors = min_actors
      @min_steps = min_steps
      @max_steps = max_steps
      @session_gap = session_gap
    end

    def call
      patterns = detect
      created = []
      updated = []
      patterns.each do |p|
        candidate, was_new = upsert(p)
        next unless candidate
        (was_new ? created : updated) << candidate
      end
      Result.new(patterns: patterns, created: created, updated: updated)
    end

    def detect
      tallies = {}
      sessions.each do |session|
        each_sequence(collapse(session)) do |seq|
          keys = seq.map(&:action_key)
          t = (tallies[keys] ||= Pattern.new(steps: keys, occurrences: 0, actors: {}, domains: Hash.new(0), examples: []))
          t.occurrences += 1
          t.actors[seq.first.actor_key] ||= seq.first.actor_name
          seq.each { |e| t.domains[e.domain] += 1 if e.domain }
          t.first_seen_at = [t.first_seen_at, seq.first.occurred_at].compact.min
          t.last_seen_at = [t.last_seen_at, seq.last.occurred_at].compact.max
          if t.examples.size < 3
            t.examples << seq.map { |e| { step: e.action_key, resource: [e.resource_type, e.resource_ref].compact.join(":"), at: e.occurred_at.iso8601 } }
          end
        end
      end
      frequent = tallies.values.select { |t| t.occurrences >= @min_occurrences && t.actors.size >= @min_actors }
      stitch(maximal(frequent))
    end

    private

    def sessions
      UsageEvent.where("occurred_at >= ?", @since).order(:actor_key, :occurred_at, :id).to_a.chunk_while do |a, b|
        a.actor_key == b.actor_key && a.session_key == b.session_key && b.occurred_at - a.occurred_at <= @session_gap
      end.to_a
    end

    def collapse(events) = events.chunk_while { |a, b| a.action_key == b.action_key }.map(&:first)

    def each_sequence(steps)
      last_end = {}
      (0...steps.size).each do |i|
        seen = Set.new
        (i...[steps.size, i + @max_steps].min).each do |j|
          break unless seen.add?(steps[j].action_key)
          next if j - i + 1 < @min_steps
          keys = steps[i..j].map(&:action_key)
          next if last_end[keys] && i <= last_end[keys]
          last_end[keys] = j
          yield steps[i..j]
        end
      end
    end

    def maximal(patterns)
      patterns.reject do |p|
        patterns.any? { |q| q.steps.size > p.steps.size && q.occurrences >= p.occurrences && q.steps.each_cons(p.steps.size).include?(p.steps) }
      end.sort_by { |p| [-p.occurrences, -p.steps.size] }
    end

    # A workflow longer than max_steps shows up as overlapping windows (A..F and B..G)
    # seen equally often. Join them back into one workflow.
    def stitch(patterns)
      patterns = patterns.dup
      loop do
        # Only windows that hit the max length can be fragments, and consecutive
        # fragments share at least max_steps - 1 steps.
        overlap = lambda do |a, b|
          (([a.steps.size, b.steps.size].min - 1).downto(@max_steps - 1)).find { |k| a.steps.last(k) == b.steps.first(k) }
        end
        a = b = k = nil
        found = patterns.product(patterns).any? do |x, y|
          next false if x.equal?(y) || x.occurrences != y.occurrences
          next false unless x.steps.size >= @max_steps && y.steps.size >= @max_steps
          k = overlap.(x, y)
          next false unless k && (x.steps + y.steps.drop(k)).uniq.size == x.steps.size + y.steps.size - k
          a, b = x, y
          true
        end
        break unless found
        joined = Pattern.new(steps: a.steps + b.steps.drop(k), occurrences: a.occurrences,
                             actors: a.actors.merge(b.actors) { |_, x, y| x || y },
                             domains: a.domains.merge(b.domains) { |_, x, y| [x, y].max },
                             first_seen_at: [a.first_seen_at, b.first_seen_at].min,
                             last_seen_at: [a.last_seen_at, b.last_seen_at].max, examples: a.examples)
        patterns.delete_if { |p| p.equal?(a) || p.equal?(b) }
        patterns << joined
      end
      patterns.sort_by { |p| [-p.occurrences, -p.steps.size] }
    end

    def domain_for(pattern)
      return pattern.domains.max_by { |_, n| n }.first if pattern.domains.any?
      pattern.steps.filter_map { |s| ActionDefinition.domain_for(s) }.tally.max_by { |_, n| n }&.first
    end

    def upsert(pattern)
      candidate = SkillCandidate.find_by(signature: pattern.signature)
      if candidate.nil?
        return [nil, false] if SkillCandidate.covering(pattern.steps).exists?
        candidate = SkillCandidate.new(signature: pattern.signature, steps: pattern.steps, origin: "detected")
      end
      was_new = candidate.new_record?
      candidate.assign_attributes(
        domain: candidate.domain.presence || domain_for(pattern),
        occurrence_count: pattern.occurrences,
        distinct_actor_count: pattern.actors.size,
        contributors: pattern.actors.sort.map { |k, n| { "key" => k, "name" => n }.compact },
        first_seen_at: [candidate.first_seen_at, pattern.first_seen_at].compact.min,
        last_seen_at: pattern.last_seen_at,
        example_traces: pattern.examples
      )
      candidate.save!
      if was_new
        AuditLog.record("skill_candidate.detected", subject: candidate, signature: candidate.signature, occurrences: candidate.occurrence_count)
        candidate.notify_reviewers!("New repeated workflow: #{candidate.display_title}")
      end
      [candidate, was_new]
    end
  end
end
