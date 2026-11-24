module Capture
  # What a task (and a whole run) should cost before it runs, and how the real figures compare.
  #
  # Estimates come from measurement where there is any: runs agents have reported for that skill, on
  # that model. Where there is none, a prior by nature and complexity stands in, and is replaced the
  # first time the task actually runs. A macro step estimates zero tokens.
  module Estimator
    # [input, output] tokens by nature × complexity.
    PRIORS = {
      "programmatic" => { "low" => [1_500, 300], "medium" => [3_000, 600], "high" => [6_000, 1_200] },
      "linear" => { "low" => [2_000, 400], "medium" => [5_000, 900], "high" => [9_000, 1_800] },
      "lookup" => { "low" => [3_000, 500], "medium" => [6_000, 1_200], "high" => [12_000, 2_000] },
      "analytic" => { "low" => [6_000, 1_200], "medium" => [12_000, 2_500], "high" => [25_000, 5_000] },
      "critical" => { "low" => [10_000, 2_500], "medium" => [20_000, 5_000], "high" => [40_000, 9_000] },
      "opaque" => { "low" => [12_000, 3_000], "medium" => [25_000, 6_000], "high" => [50_000, 12_000] }
    }.freeze
    OVERHEAD_SECONDS = 4

    module_function

    # One task (or one part of a split task).
    def for_step(step, flow_id: nil, measured: nil)
      macro = step["engine"] == "macro" || (step["engine"].blank? && flow_id && MacroScreen.approved_for_step(flow_id, step).present?)
      profile = TaskProfile.for_step(step, macro_ready: macro)
      return macro_estimate(step, profile) if macro
      model = step["model"].presence || profile["model"]
      m = measured || measured_for(step["skill_name"], model)
      inp, out = if m && m[:runs].to_i >= 2 then [m[:input], m[:output]]
                 else PRIORS.dig(profile["nature"], profile["complexity"]) || PRIORS["linear"]["medium"]
                 end
      seconds = m && m[:seconds].to_f.positive? ? m[:seconds] : Models.seconds(model, out) + OVERHEAD_SECONDS
      profile.merge("engine" => "ai", "model" => model, "input_tokens" => inp.round, "output_tokens" => out.round,
                    "tokens" => (inp + out).round, "seconds" => seconds.round(1),
                    "cost" => Models.cost(model, inp, out).to_f,
                    "basis" => m && m[:runs].to_i >= 2 ? "measured (#{m[:runs]} runs)" : "estimated from #{TaskProfile.label(profile['nature']).downcase}, #{profile['complexity']} complexity")
    end

    def macro_estimate(step, profile)
      profile.merge("engine" => "macro", "model" => "macro", "input_tokens" => 0, "output_tokens" => 0, "tokens" => 0,
                    "seconds" => (step["macro_seconds"].presence || 8).to_f, "cost" => 0.0, "tier" => "macro",
                    "basis" => "reviewed macro: no tokens")
    end

    # Averages from the runs agents reported for this skill (on this model where there are enough).
    def measured_for(skill_name, model = nil)
      return nil if skill_name.blank?
      scope = SkillRun.where(skill_name: skill_name, status: "succeeded", engine: "ai").where(occurred_at: Intensity::WINDOW.ago..)
      on_model = model.present? ? scope.where(model: model) : scope.none
      use = on_model.count >= 2 ? on_model : scope
      n = use.count
      return nil if n.zero?
      { runs: n, input: use.average(:input_tokens).to_f, output: use.average(:output_tokens).to_f,
        seconds: use.where.not(duration_ms: nil).average(:duration_ms).to_f / 1000 }
    end

    # Every task in a flow (a split task contributes each of its parts), plus the totals.
    def for_steps(steps, flow_id: nil)
      rows = Array(steps).each_with_index.map do |s, i|
        next { "index" => i, "skipped" => true, "title" => s["title"], "tokens" => 0, "cost" => 0.0, "seconds" => 0.0 } if s["state"] == "skipped"
        next { "index" => i, "pause" => true, "title" => s["title"], "tokens" => 0, "cost" => 0.0, "seconds" => pause_seconds(s) } if Flow.pause?(s)
        parts = Array(s["parts"])
        if parts.any?
          pe = parts.map { |p| for_step(s.merge(p.except("id", "title")).merge("title" => p["title"].presence || s["title"]), flow_id: flow_id) }
          base = TaskProfile.for_step(s)
          { "index" => i, "title" => s["title"], "split" => true, "parts" => pe,
            "nature" => base["nature"], "complexity" => base["complexity"], "engine" => "split",
            "basis" => "#{pe.size} parts side by side: #{pe.map { |e| e['engine'] == 'macro' ? 'macro' : Models.label(e['model']) }.join(' + ')}",
            "tokens" => pe.sum { |e| e["tokens"] }, "cost" => pe.sum { |e| e["cost"] }.round(4),
            "seconds" => pe.map { |e| e["seconds"] }.max.to_f.round(1), # parts run side by side
            "models" => pe.map { |e| e["model"] }.uniq }
        else
          for_step(s, flow_id: flow_id).merge("index" => i, "title" => s["title"])
        end
      end
      { "steps" => rows, "tokens" => rows.sum { |r| r["tokens"].to_i }, "cost" => rows.sum { |r| r["cost"].to_f }.round(4),
        "seconds" => rows.sum { |r| r["seconds"].to_f }.round(1),
        "ai_steps" => rows.count { |r| !r["pause"] && !r["skipped"] && (r["split"] ? r["parts"].any? { |p| p["engine"] == "ai" } : r["engine"] == "ai") },
        "macro_steps" => rows.count { |r| !r["pause"] && !r["skipped"] && (r["split"] ? r["parts"].all? { |p| p["engine"] == "macro" } : r["engine"] == "macro") },
        "models" => rows.flat_map { |r| r["split"] ? r["models"] : [r["model"]] }.compact.tally }
    end

    def pause_seconds(s) = s["pause_mode"] == "timer" ? s["pause_minutes"].to_i * 60 : 0

    # What a run has actually used so far, against what was anticipated.
    def tally(run)
      est = run.estimate.presence || for_steps(run.steps, flow_id: run.flow_id)
      done = run.steps.each_with_index.select { |s, _| s["state"] == "done" }
      spent_tokens = 0
      spent_cost = 0.to_d
      spent_seconds = 0.0
      done.each do |s, _|
        (s["parts"].presence ? Array(s["parts"]) : [s]).each do |u|
          usage = u["usage"] || {}
          t = usage["input_tokens"].to_i + usage["output_tokens"].to_i
          spent_tokens += t
          spent_cost += (usage["cost"].presence || Models.cost(usage["model"], usage["input_tokens"], usage["output_tokens"])).to_d
          spent_seconds += usage["duration_ms"].to_i / 1000.0
        end
      end
      done_idx = done.map { |_, i| i }
      planned = est["steps"].select { |r| done_idx.include?(r["index"]) }
      remaining = est["steps"].reject { |r| done_idx.include?(r["index"]) || r["pause"] || r["skipped"] || run.steps.dig(r["index"], "state") == "skipped" }
      { "estimate" => est,
        "spent" => { "tokens" => spent_tokens, "cost" => spent_cost.round(4).to_f, "seconds" => spent_seconds.round(1), "steps" => done.size },
        "planned_so_far" => { "tokens" => planned.sum { |r| r["tokens"].to_i }, "cost" => planned.sum { |r| r["cost"].to_f }.round(4) },
        "remaining" => { "tokens" => remaining.sum { |r| r["tokens"].to_i }, "cost" => remaining.sum { |r| r["cost"].to_f }.round(4), "seconds" => remaining.sum { |r| r["seconds"].to_f }.round(1) },
        "projected" => { "tokens" => spent_tokens + remaining.sum { |r| r["tokens"].to_i },
                         "cost" => (spent_cost + remaining.sum { |r| r["cost"].to_f }.to_d).round(4).to_f } }
    end

    # The same task priced on every live model, so it can be tried where it's cheapest that still works.
    def trial_plan(step, flow_id: nil)
      Models.catalogue.reject(&:macro?).map do |m|
        e = for_step(step.merge("model" => m.key, "engine" => "ai"), flow_id: flow_id)
        { "model" => m.key, "name" => m.name, "tier" => m.tier, "tokens" => e["tokens"], "seconds" => e["seconds"], "cost" => e["cost"], "basis" => e["basis"] }
      end
    end

    # What actually happened when a task was tried on several models (SkillRun#trial_of groups them).
    def trial_results(trial_id)
      SkillRun.where(trial_of: trial_id).group(:model).pluck(:model, Arel.sql("COUNT(*)"), Arel.sql("AVG(input_tokens)"), Arel.sql("AVG(output_tokens)"), Arel.sql("AVG(duration_ms)"), Arel.sql("COUNT(*) FILTER (WHERE status = 'succeeded')"))
               .map { |m, n, i, o, d, ok| { "model" => m, "runs" => n, "input_tokens" => i.to_f.round, "output_tokens" => o.to_f.round,
                                            "seconds" => d && (d.to_f / 1000).round(1), "succeeded" => ok,
                                            "cost" => Models.cost(m, i.to_f, o.to_f).to_f } }
               .sort_by { |r| r["cost"] }
    end
  end
end
