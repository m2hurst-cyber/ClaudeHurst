module Capture
  # Macro suitability: would a deterministic script do this task, with no tokens spent?
  #
  # The screen scores the signals that make work scriptable (the same keystrokes every time, named
  # ranges and sheets, counts and formats, no judgment words), proposes a macro skeleton, and files a
  # MacroReview. A person approves it before any macro runs in place of the AI — that review is the
  # gate, because a wrong macro is silently wrong on every run.
  module MacroScreen
    DETERMINISTIC = {
      /\b(copy|paste|duplicate)\b/i => ["copies cells, charts or slides", 2],
      /\b(format|reformat|number format|autofit|bold|align|style|template)\b/i => ["applies fixed formatting", 2],
      /\b(sort|filter|dedup\w*|remove duplicates|transpose|unmerge|split|merge)\b/i => ["rearranges data by a fixed rule", 2],
      /\b(refresh|recalculate|update links|re-?run)\b/i => ["refreshes data", 2],
      /\b(rename|number the|label each|paginate|save as|export|import)\b/i => ["renames, numbers or exports", 2],
      /\b(every|each|all)\b.{0,24}\b(chart|sheet|slide|row|column|file|tab)\b/i => ["repeats over every item", 3],
      /\b(one per (slide|row|sheet)|in order|same (order|format)|consistent)\b/i => ["one item at a time, in order", 2],
      /'?[A-Za-z0-9 _]+'?![A-Z]{1,3}\d|\b[A-Z]{1,3}\d{1,5}(:[A-Z]{1,3}\d{1,5})?\b/ => ["names exact cells or ranges", 2]
    }.freeze

    JUDGMENT = {
      /\b(decide|judge|recommend|advise|interpret|assess|argue|persuade|opinion|insight|implication)\b/i => ["calls for judgment", 4],
      /\b(write|draft|narrative|summari[sz]e|explain|describe|comment on)\b/i => ["writes prose", 3],
      /\b(unclear|ambiguous|as (needed|appropriate|noted)|where (relevant|sensible)|use your|if it (looks|seems))\b/i => ["leaves it to the doer", 3],
      /\b(anomal\w+|outlier|unusual|suspicious|key trend|material|significant)\b/i => ["needs a reading of the numbers", 3],
      /\b(choose|select the best|prioriti[sz]e|rank)\b/i => ["chooses between options", 2],
      /\b(regress\w*|forecast|model|statistic)\b/i => ["statistical work, better in code than a macro", 1]
    }.freeze

    module_function

    # score: deterministic signals minus judgment signals. ≥ 5 and nothing weighty against → macro.
    def screen(title:, instructions: nil, nature: nil, app: nil, skill: nil)
      text = [title, instructions, skill&.body].compact.join("\n")
      det = DETERMINISTIC.filter_map { |re, (why, w)| [why, w] if re.match?(text) }
      jud = JUDGMENT.filter_map { |re, (why, w)| [why, w] if re.match?(text) }
      det << ["the task is marked programmatic", 3] if nature == "programmatic"
      jud << ["the task is marked #{TaskProfile.label(nature).downcase}", 4] if %w[critical opaque].include?(nature)
      score = det.sum { |(_, w)| w } - jud.sum { |(_, w)| w }
      verdict = if score >= 5 && jud.none? { |(_, w)| w >= 3 } then "macro"
                elsif score >= 2 then "partial"
                else "ai"
                end
      { "verdict" => verdict, "score" => score,
        "signals" => { "for" => det.map(&:first), "against" => jud.map(&:first) },
        "reason" => reason(verdict, det, jud) }
    end

    def reason(verdict, det, jud)
      f = det.map(&:first).first(3).to_sentence
      a = jud.map(&:first).first(2).to_sentence
      case verdict
      when "macro" then "A macro can do this: it #{f}, with nothing that needs judgment. Running it as a macro costs no tokens."
      when "partial" then "Part of this is scriptable (it #{f.presence || 'has some fixed steps'}), but it also #{a.presence || 'needs some judgment'}. Split the task: a macro for the mechanical part, the AI for the rest."
      else "Leave this to the AI: it #{a.presence || 'has no repeatable, mechanical core'}."
      end
    end

    # A starting Office Script for the reviewer to correct. Deliberately a skeleton: it names the steps
    # it found and leaves the specifics to whoever approves it.
    # A starting script for the reviewer to correct. Deliberately a skeleton: it names the steps the
    # screen found and leaves the specifics to whoever approves it. Excel gets an add-in script, which
    # the add-in itself can run once approved; Word and PowerPoint get VBA to paste in.
    def skeleton(title:, app: "Excel", signals: {})
      steps = Array(signals["for"]).presence || ["the repeated steps"]
      if app == "Excel"
        body = steps.each_with_index.map { |s, i| "  // #{i + 1}. #{s}" }.join("\n")
        { "language" => "addin_js", "steps" => steps, "code" => <<~JS }
          // #{title} — runs in the add-in, no AI
          // Gets Excel's request context. Return a short line saying what it did.
          async function run(context) {
            const sheet = context.workbook.worksheets.getActiveWorksheet();
            const used = sheet.getUsedRange();
            used.load(["rowCount", "columnCount", "address"]);
            await context.sync();
          #{body}
            return `#{title}: ${used.rowCount} rows at ${used.address}`;
          }
        JS
      else
        body = steps.each_with_index.map { |s, i| "  ' #{i + 1}. #{s}" }.join("\n")
        { "language" => "vba", "steps" => steps,
          "code" => "' #{title} — #{app} macro (no AI)\nSub #{title.parameterize(separator: '_').camelize}()\n#{body}\nEnd Sub\n" }
      end
    end

    # Screen a task and file (or refresh) its review. An approved review is never overwritten.
    def review!(kind:, key:, title:, instructions: nil, nature: nil, app: "Excel", skill: nil, user: nil)
      r = MacroReview.for_subject(kind, key)
      return r if r&.approved?
      s = screen(title: title, instructions: instructions, nature: nature, app: app, skill: skill)
      r ||= MacroReview.new(subject_kind: kind, subject_key: key, proposed_by: user)
      r.assign_attributes(title: title, verdict: s["verdict"], score: s["score"], signals: s["signals"], reason: s["reason"],
                          status: r.status.in?(%w[rejected needs_work]) ? r.status : "proposed")
      r.suggestion = skeleton(title: title, app: app, signals: s["signals"]) if r.suggestion.blank? || r.code.blank?
      r.save!
      r
    end

    # The macro engine for a step, if one has been approved for it.
    def approved_for_step(flow_id, step) = MacroReview.approved_for("flow_step", "#{flow_id}:#{step['id']}")
    def approved_for_skill(name) = name.present? ? MacroReview.approved_for("skill", name) : nil
  end
end
