module Capture
  # How intense a skill is to run with AI, from the runs agents report: average tokens per run (in and
  # out), average time, tokens per minute, by model. "Light / Moderate / Heavy" is the skill's percentile
  # rank by average tokens among every skill with runs in the last 90 days (thirds).
  module Intensity
    module_function

    WINDOW = 90.days

    def for_names(names)
      names = Array(names).uniq
      return {} if names.empty?
      runs = SkillRun.where(skill_name: names, occurred_at: WINDOW.ago..)
      base = runs.group(:skill_name).pluck(:skill_name, Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE status = 'succeeded')"),
                                           Arel.sql("AVG(input_tokens)"), Arel.sql("AVG(output_tokens)"), Arel.sql("AVG(duration_ms)"),
                                           Arel.sql("SUM(input_tokens + output_tokens)"), Arel.sql("SUM(duration_ms)"), Arel.sql("MAX(occurred_at)"))
      models = runs.group(:skill_name, :model).pluck(:skill_name, :model, Arel.sql("COUNT(*)"), Arel.sql("AVG(input_tokens + output_tokens)"), Arel.sql("AVG(duration_ms)"))
                   .group_by(&:first)
      cuts = thresholds
      base.to_h do |name, n, ok, ain, aout, adur, tok, dur, last|
        avg = ain.to_f + aout.to_f
        [name, {
          runs: n, success_rate: n.positive? ? (ok.to_f / n).round(3) : nil,
          avg_input_tokens: ain.to_f.round, avg_output_tokens: aout.to_f.round, avg_tokens: avg.round,
          avg_seconds: adur && (adur.to_f / 1000).round(1),
          tokens_per_minute: dur.to_i.positive? ? (tok.to_f / (dur.to_f / 60_000)).round : nil,
          intensity: level(avg, cuts), last_run_at: last&.iso8601,
          models: Array(models[name]).sort_by { |r| -r[2] }.map { |_, m, c, t, d| { model: m || "unknown", runs: c, avg_tokens: t.to_f.round, avg_seconds: d && (d.to_f / 1000).round(1) } }
        }]
      end
    end

    def for(name) = for_names([name])[name]

    # Every skill's average tokens per run (sorted), to rank against.
    def thresholds
      avgs = SkillRun.where(occurred_at: WINDOW.ago..).group(:skill_name).pluck(Arel.sql("AVG(input_tokens + output_tokens)")).map(&:to_f).sort
      avgs.size < 3 ? nil : avgs
    end

    # Percentile rank among skills: bottom third light, middle moderate, top third heavy.
    def level(avg, all)
      return nil unless all
      p = all.count { |x| x < avg - 1e-9 }.to_f / all.size
      p < 1.0 / 3 ? "light" : (p < 2.0 / 3 ? "moderate" : "heavy")
    end

    def report_instructions(url)
      { url: url, method: "POST", fields: { model: "the model that ran it", input_tokens: "integer", output_tokens: "integer",
                                             duration_ms: "integer (or started_at and finished_at)", status: "succeeded | failed", version: "skill version (optional)" },
        note: "Report every run, so the skill shows its real token, time and model intensity." }
    end
  end
end
