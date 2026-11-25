module Capture
  # How finely the system cuts work into skills.
  #
  # Granularity is not one threshold, so this is not one number with a multiplier on it.
  # Moving the slider changes five things together, because they only make sense together:
  #
  #   how long a skill may be        2–3 steps at the fine end, up to 14 at the coarse end
  #   which of two nested patterns wins   the smallest reusable unit, or the longest whole story
  #   how much evidence is needed    short sequences recur by chance, so they need more of it
  #   how varied the surroundings must be  a building block appears in many different contexts;
  #                                  a fragment only ever appears inside one bigger thing
  #   what the AI is told to prefer  the same taste, applied to its judgement of each pattern
  #
  # Set once for the firm, overridden per area and per person: tax wants whole returns,
  # equity research wants reusable blocks, and one person may simply want fewer prompts.
  module Granularity
    # Level 3 is deliberately identical to the thresholds the system ran on before the slider
    # existed, so turning the dial is the only thing that ever changes behaviour.
    DEFAULT = 3
    RANGE = (1..5).freeze

    LEVELS = {
      1 => { key: "atomic", label: "Atomic", summary: "Building blocks",
             blurb: "The smallest thing worth naming. Many small skills that compose; the map does the joining.",
             min_steps: 2, max_steps: 3, evidence: 2.0, min_contexts: 3, prefer: :shortest, stitch: false,
             guidance: "Prefer the smallest reusable unit. A pattern is worth saving only if it is a building " \
                       "block used in several different situations, not one stretch of a single larger task." },
      2 => { key: "small", label: "Small", summary: "Reusable steps",
             blurb: "Short, nameable procedures that show up inside several larger jobs.",
             min_steps: 2, max_steps: 4, evidence: 1.5, min_contexts: 2, prefer: :shortest, stitch: false,
             guidance: "Lean small. Prefer a short procedure that recurs in more than one context over the " \
                       "longer task that contains it." },
      3 => { key: "balanced", label: "Balanced", summary: "A task someone would name",
             blurb: "What a person would call a task: a recognisable job with an outcome.",
             min_steps: 2, max_steps: 6, evidence: 1.0, min_contexts: 1, prefer: :maximal, stitch: true,
             guidance: "Aim for what a person would call a task: a coherent job with a recognisable outcome." },
      4 => { key: "broad", label: "Broad", summary: "A whole deliverable",
             blurb: "Larger procedures that carry a piece of work from input to deliverable.",
             min_steps: 3, max_steps: 9, evidence: 0.8, min_contexts: 1, prefer: :longest, stitch: true,
             guidance: "Prefer the fuller procedure. Keep steps together when they serve one deliverable, " \
                       "even where part of it could stand alone." },
      5 => { key: "end_to_end", label: "End to end", summary: "The whole run",
             blurb: "Few, long skills: a whole engagement or close, start to finish.",
             min_steps: 4, max_steps: 14, evidence: 0.6, min_contexts: 1, prefer: :longest, stitch: true,
             guidance: "Capture the whole run end to end. Only split where the work genuinely stops and " \
                       "a different person or system takes over." }
    }.freeze

    # The agent directions for each level: how to write a skill at this size, what to do
    # with steps that belong to a neighbour, and when to save, extend or branch. Files
    # rather than constants, because these are prose that wants editing and reviewing —
    # and because agents and people read the same text.
    DIR = Rails.root.join("granularity")

    module_function

    def directions(level)
      key = settings(level)[:key]
      @directions = nil if !Rails.env.production? && directions_stale?
      @directions ||= {}
      @directions[key] ||= begin
        file = DIR.join("#{key}.md")
        @directions_loaded_at = Time.current
        file.exist? ? file.read.strip : settings(level)[:guidance]
      end
    end

    def directions_stale?
      return true if @directions_loaded_at.nil?
      Dir.glob(DIR.join("*.md")).any? { |f| File.mtime(f) > @directions_loaded_at }
    end

    def all_directions = LEVELS.keys.index_with { |l| directions(l) }

    def valid?(level) = RANGE.cover?(level.to_i)
    def clamp(level) = level.to_i.clamp(RANGE.min, RANGE.max)
    def settings(level) = LEVELS.fetch(clamp(level))
    def label(level) = settings(level)[:label]

    # The firm's setting, unless this area or this person says otherwise.
    def firm_level = Protocol.for("granularity")["level"].to_i.then { |l| valid?(l) ? l : DEFAULT }

    def level_for(domain: nil, user: nil)
      GranularityOverride.level_for(domain: domain, user: user) || firm_level
    end

    # Every level in play right now — the firm's and every override's. Detection runs once
    # over the widest window these need, and each pattern is then judged at its own area's level.
    def active_levels = ([firm_level] + GranularityOverride.pluck(:level)).uniq.sort

    def envelope
      levels = active_levels.map { |l| settings(l) }
      { min_steps: levels.map { |s| s[:min_steps] }.min, max_steps: levels.map { |s| s[:max_steps] }.max }
    end

    # Short sequences turn up by chance, so the finer the setting the more often a pattern
    # has to repeat before it counts. Never below two.
    def min_occurrences(level, base: Config.min_occurrences)
      [(base * settings(level)[:evidence]).ceil, 2].max
    end

    # What the slider would have produced from the events already in hand. The point of a
    # dial nobody can see the effect of is nothing, so every level is costed before it is set.
    def preview(since: Config.lookback.ago, levels: RANGE.to_a)
      levels.to_h do |level|
        patterns = WorkflowDetector.new(level: level, since: since).detect
        sizes = patterns.map { |p| p.steps.size }.sort
        [level, {
          level: level, label: label(level), count: patterns.size,
          median_steps: sizes.empty? ? 0 : sizes[sizes.size / 2],
          samples: patterns.first(4).map { |p| { steps: p.steps.size, occurrences: p.occurrences,
                                                 title: ActionDefinition.labels_for(p.steps).values.join(" → ").truncate(70) } }
        }]
      end
    end
  end
end
