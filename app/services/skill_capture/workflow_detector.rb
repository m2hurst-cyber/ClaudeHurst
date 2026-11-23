module SkillCapture
  # Mines the usage-event stream for repeated multi-step workflows and upserts
  # them as SkillCandidates.
  #
  # Algorithm (deliberately simple and explainable to reviewers):
  #   1. Split each user's events into work sessions (idle gap > Config.session_gap).
  #   2. Collapse consecutive duplicate steps (5 lots received in a row = 1 step).
  #   3. Enumerate contiguous step sequences of length min_steps..max_steps that
  #      do not visit the same step twice (cycles are repetitions, not workflows).
  #   4. Keep sequences seen >= min_occurrences times by >= min_users people.
  #   5. Keep only *maximal* sequences: drop A>B if A>B>C occurs just as often.
  class WorkflowDetector
    Pattern = Struct.new(:steps, :occurrences, :user_ids, :first_seen_at, :last_seen_at, :examples, keyword_init: true) do
      def signature = SkillCandidate.signature_for(steps)
    end

    Result = Struct.new(:patterns, :created, :updated, keyword_init: true)

    def self.call(**opts) = new(**opts).call

    def initialize(since: Config.lookback.ago, min_occurrences: Config.min_occurrences, min_users: Config.min_users,
                   min_steps: Config.min_steps, max_steps: Config.max_steps, session_gap: Config.session_gap)
      @since = since
      @min_occurrences = min_occurrences
      @min_users = min_users
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

    # Pure detection, no writes — handy for tests and dry runs.
    def detect
      tallies = {}
      sessions.each do |session|
        steps = collapse(session)
        each_sequence(steps) do |seq|
          keys = seq.map(&:workflow_key)
          t = (tallies[keys] ||= Pattern.new(steps: keys, occurrences: 0, user_ids: Set.new, examples: []))
          t.occurrences += 1
          t.user_ids << seq.first.user_id
          t.first_seen_at = [t.first_seen_at, seq.first.occurred_at].compact.min
          t.last_seen_at = [t.last_seen_at, seq.last.occurred_at].compact.max
          if t.examples.size < 3
            t.examples << seq.map { |e| { step: e.workflow_key, resource: [e.resource_type, e.resource_id].compact.join("#"), at: e.occurred_at.iso8601 } }
          end
        end
      end

      frequent = tallies.values.select { |t| t.occurrences >= @min_occurrences && t.user_ids.size >= @min_users }
      maximal(frequent)
    end

    private

    def sessions
      events = UsageEvent.where("occurred_at >= ?", @since).where.not(user_id: nil)
                         .order(:user_id, :occurred_at, :id).to_a
      events.chunk_while do |prev, e|
        prev.user_id == e.user_id && prev.session_key == e.session_key && e.occurred_at - prev.occurred_at <= @session_gap
      end.to_a
    end

    def collapse(events)
      events.chunk_while { |a, b| a.workflow_key == b.workflow_key }.map(&:first)
    end

    # Non-overlapping counting per sequence: once a sequence is counted ending at
    # index j, the same sequence is not counted again until after j.
    def each_sequence(steps)
      last_end = {}
      (0...steps.size).each do |i|
        seen = Set.new
        (i...[steps.size, i + @max_steps].min).each do |j|
          break unless seen.add?(steps[j].workflow_key) # no step twice in one workflow
          len = j - i + 1
          next if len < @min_steps
          keys = steps[i..j].map(&:workflow_key)
          next if last_end[keys] && i <= last_end[keys]
          last_end[keys] = j
          yield steps[i..j]
        end
      end
    end

    def maximal(patterns)
      patterns.reject do |p|
        patterns.any? do |q|
          q.steps.size > p.steps.size && contains?(q.steps, p.steps) && q.occurrences >= p.occurrences
        end
      end.sort_by { |p| [-p.occurrences, -p.steps.size] }
    end

    def contains?(haystack, needle)
      haystack.each_cons(needle.size).any? { |w| w == needle }
    end

    def upsert(pattern)
      candidate = SkillCandidate.find_by(signature: pattern.signature)
      if candidate.nil?
        # Don't propose a fragment of a workflow that is already captured or was ruled out.
        return [nil, false] if SkillCandidate.covering(pattern.steps).exists?
        candidate = SkillCandidate.new(signature: pattern.signature, steps: pattern.steps, origin: "detected")
      end
      was_new = candidate.new_record?
      candidate.assign_attributes(
        domain: Catalog.domain_for_steps(pattern.steps),
        occurrence_count: pattern.occurrences,
        distinct_user_count: pattern.user_ids.size,
        contributor_ids: pattern.user_ids.to_a.sort,
        first_seen_at: [candidate.first_seen_at, pattern.first_seen_at].compact.min,
        last_seen_at: pattern.last_seen_at,
        example_traces: pattern.examples
      )
      candidate.save!
      if was_new
        AuditLogger.record(user: nil, action: "skill_candidate.detected", subject: candidate,
                           metadata: { signature: candidate.signature, occurrences: candidate.occurrence_count })
        candidate.notify_reviewers!("New workflow detected: #{candidate.display_title}")
      end
      [candidate, was_new]
    end
  end
end
