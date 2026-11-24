module Capture
  # What kind of task is this, and how hard? The two together choose the model tier, so a linear,
  # programmatic step doesn't run on a deep model (and a judgment call doesn't run on a small one).
  #
  # The hierarchy, cheapest first:
  #   programmatic  the same keystrokes every time on known data        → macro (no tokens)
  #   linear        a fixed sequence, light judgment                    → small
  #   lookup        find, extract, reformat from a known source         → small
  #   analytic      compute, compare, summarize against rules           → standard
  #   critical      judgment, trade-offs, writing that must persuade    → deep
  #   opaque        unclear, novel or exploratory: no settled method    → deep
  module TaskProfile
    NATURES = {
      "programmatic" => { label: "Programmatic", tier: "macro", about: "The same steps every time on known data: copy, format, sort, refresh, rename." },
      "linear" => { label: "Linear", tier: "small", about: "A fixed sequence with light judgment." },
      "lookup" => { label: "Lookup / extract", tier: "small", about: "Find, pull out or reformat from a known source." },
      "analytic" => { label: "Analytic", tier: "standard", about: "Compute, compare or summarize against rules." },
      "critical" => { label: "Critical thinking", tier: "deep", about: "Judgment, trade-offs, writing that has to persuade." },
      "opaque" => { label: "Opaque", tier: "deep", about: "Unclear, novel or exploratory: no settled method yet." }
    }.freeze
    COMPLEXITY = %w[low medium high].freeze
    ORDER = NATURES.keys.freeze

    # Words that give a task away. Checked against the title, instructions and the skill's steps.
    HINTS = {
      "programmatic" => /\b(copy|paste|format|reformat|refresh|rename|sort|filter|dedup\w*|remove duplicates|clean(\s+(up|the)?\s*data)?|convert|export|import|append|paginate|number the|apply the template|fill down|autofit|pivot|save as|batch|transpose|unmerge)\b/i,
      "lookup" => /\b(collect|gather|pull|fetch|look ?up|extract|retrieve|download|read the|find the)\b/i,
      "linear" => /\b(check|verify|tie out|reconcile|validate|confirm|label|tag|build the|assemble)\b/i,
      "analytic" => /\b(analy[sz]e|compute|calculate|regress\w*|model|forecast|compare|summari[sz]e|statistics|variance|ratio|trend)\b/i,
      "critical" => /\b(recommend|advise|decide|judge|assess|interpret|argue|persuade|write the (white ?paper|memo|narrative)|conclusion|implication|thesis|strategy)\b/i,
      "opaque" => /\b(investigate|explore|figure out|work out why|diagnose|root cause|unclear|ambiguous|open[- ]ended|research whether)\b/i
    }.freeze

    module_function

    def label(n) = NATURES.dig(n.to_s, :label) || n.to_s.humanize
    def tier(n) = NATURES.dig(n.to_s, :tier) || "standard"
    def about(n) = NATURES.dig(n.to_s, :about)

    # Rules first: the most demanding nature whose words appear wins, so "analyze, then recommend" is
    # critical, not analytic.
    def infer(text)
      t = text.to_s
      ORDER.reverse.find { |n| HINTS[n].match?(t) } || "linear"
    end

    def infer_complexity(text, nature)
      t = text.to_s
      long = t.length > 400 || t.scan(/[.;\n]/).size > 6
      return "high" if %w[opaque critical].include?(nature) && long
      return "high" if t.match?(/\b(multi[- ]?step|several sources|cross[- ]check|edge cases|exceptions|first time|novel)\b/i)
      return "low" if %w[programmatic lookup].include?(nature) && !long
      long ? "high" : "medium"
    end

    # The tier a task of this nature and complexity should run on (macro only when a reviewed macro exists).
    def tier_for(nature:, complexity: "medium", macro_ready: false)
      base = tier(nature)
      return "macro" if base == "macro" && macro_ready
      base = "small" if base == "macro"
      order = %w[small standard deep]
      i = order.index(base) || 1
      i += 1 if complexity == "high"
      i -= 1 if complexity == "low" && nature != "critical" && nature != "opaque"
      order[i.clamp(0, order.size - 1)]
    end

    # A whole profile for one task: nature, complexity, the tier and the model to use.
    def for_step(step, macro_ready: false)
      text = [step["title"], step["instructions"], step["skill_name"]].compact.join(". ")
      nature = step["nature"].presence_in(NATURES.keys) || infer(text)
      complexity = step["complexity"].presence_in(COMPLEXITY) || infer_complexity(text, nature)
      tier = tier_for(nature: nature, complexity: complexity, macro_ready: macro_ready)
      model = step["model"].presence || Models.for_tier(tier)&.key
      { "nature" => nature, "complexity" => complexity, "tier" => tier, "model" => model, "inferred" => step["nature"].blank? }
    end
  end
end
