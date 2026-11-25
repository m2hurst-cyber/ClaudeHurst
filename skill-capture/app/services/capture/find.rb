module Capture
  # The front door's engine: one question, searched across everything the company knows — skills, the
  # playbooks a job runs through, jobs in flight, flows, resources, formula commands and approved
  # macros — ranked together, with the action each answer offers.
  #
  # The same service answers the console's search box, the add-in's, and anything else that needs to
  # turn a sentence into "here is the thing, here is where it sits, here is what you can do with it".
  module Find
    GROUPS = %w[skills playbooks jobs flows resources formulas macros].freeze
    FLOOR = 12 # a real answer
    LOOSE = 4  # only worth showing when nothing answered properly
    # Words that mean "I want to do this", not "I want to read about it".
    VERBS = /\A(start|open|run|build|make|create|bill|invoice|price|quote|estimate|chart|send|find|show|where)\b/i

    Hit = Struct.new(:group, :title, :subtitle, :url, :score, :badge, :action, :action_url, :key, keyword_init: true) do
      def to_h = { group: group, title: title, subtitle: subtitle, url: url, badge: badge, action: action, action_url: action_url, key: key }
    end

    module_function

    def h = Rails.application.routes.url_helpers

    def call(query, viewer:, limit: 8)
      q = query.to_s.strip
      return { query: q, empty: true, groups: {}, total: 0, intent: nil } if q.length < 2
      intent = q[VERBS, 1]&.downcase
      terms = q.sub(VERBS, "").strip.presence || q
      both = ->(m, *args) { send(m, q, *args).concat(terms == q ? [] : send(m, terms, *args)).uniq { |x| [x.group, x.key] }.sort_by { |x| [-x.score, x.key.to_s] }.first(args.last) }
      groups = {
        "skills" => both.(:skills, viewer, limit),
        "playbooks" => both.(:playbooks, limit).each { |x| x.score += 20 if intent },
        "jobs" => both.(:jobs, viewer, limit),
        "flows" => both.(:flows, viewer, limit),
        "resources" => both.(:resources, viewer, limit),
        "formulas" => both.(:formulas, limit),
        "macros" => both.(:macros, viewer, limit)
      }.transform_values { |hits| strong = hits.select { |x| x.score >= FLOOR }; strong.presence || hits.select { |x| x.score >= LOOSE }.first(3) }
                 .reject { |_, v| v.empty? }
      loose = groups.values.flatten.none? { |x| x.score >= FLOOR }
      { query: q, terms: terms, intent: intent, groups: groups, total: groups.values.sum(&:size),
        best: best(groups, intent), loose: loose, empty: false }
    end

    # The one answer to put at the top: an action beats a document when the question starts with a verb.
    def best(groups, intent)
      all = groups.values.flatten
      return nil if all.empty?
      all.min_by { |x| [-(x.score + (intent && x.action ? 25 : 0)), x.key.to_s] }
    end

    def like(term) = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"

    # The question as a phrase, plus each word in it that carries meaning. A long question has to be
    # matched word by word or the database finds nothing at all.
    def patterns(q)
      ([q.to_s] + significant(q)).uniq.map { |t| like(t) }
    end

    # scope.where(any of these columns ILIKE any of those patterns)
    def matching(scope, columns, q)
      sql = columns.map { |c| "#{c} ILIKE ANY (ARRAY[:p])" }.join(" OR ")
      scope.where(sql, p: patterns(q))
    end

    # How well a phrase matches: the whole phrase beats most of the words, which beats one of them.
    # Earlier fields (a name, a title) count for more than later ones (a description).
    def score_text(q, *fields)
      q = q.to_s.downcase.strip
      words = significant(q)
      fields.compact.each_with_index.sum do |f, i|
        f = f.to_s.downcase
        matched = words.select { |w| f.match?(/\b#{Regexp.escape(w)}/) }  # a word, or the start of one: "bill" finds "billing"
        weight = words.sum(&:length).to_f
        share = weight.zero? ? 0 : matched.sum(&:length) / weight        # long words count for more: they are the specific ones
        base = if f == q then 100
               elsif f.include?(q) then f.start_with?(q) ? 60 : 45
               elsif share >= 0.99 then 40
               elsif share >= 0.4 then (45 * share).round
               else (6 * share).round
               end
        (base * (FIELD_WEIGHT[i] || 0.5)).round
      end
    end

    FIELD_WEIGHT = [1.0, 0.9, 0.75, 0.55].freeze # a name, then a title, then a description, then the body

    STOP = %w[the a an and or of for to in on at it is do does how what when who why me my our your this that with from
              i we they them need want should].freeze

    # The words worth matching on. Short ones are kept but count for little, because a match on
    # "rot" means less than a match on "retainage".
    def significant(q)
      q.to_s.downcase.split(/\W+/).reject { |w| STOP.include?(w) || w.length < 3 }
    end

    def skills(q, viewer, limit)
      scope = matching(Skill.published.visible_to(viewer), %w[name title description body], q).limit(limit * 4)
      traffic = SkillMetric.where(name: scope.map(&:name)).index_by(&:name)
      scope.map do |s|
        est = Estimator.for_step({ "title" => s.title, "instructions" => s.description, "skill_name" => s.name })
        macro = MacroScreen.approved_for_skill(s.name)
        Hit.new(group: "skills", key: s.name, title: s.title, url: h.skill_path(s),
                subtitle: s.description.to_s.truncate(150),
                badge: [area_label(s.domain), s.stage == "local" ? "sandbox" : s.stage,
                        (macro ? "⚙ macro, no tokens" : "#{number_with_delimiter(est['tokens'])} tokens")].compact.join(" · "),
                action: s.source["worksheet"] ? "Build the worksheet" : nil,
                action_url: s.source["worksheet"] ? h.skill_path(s, anchor: "worksheet") : nil,
                score: score_text(q, s.name, s.title, s.description, s.body) + [Math.log10([traffic[s.name]&.trips.to_i, 1].max) * 10, 20].min)
      end.select { |x| x.score.positive? }.sort_by { |x| [-x.score, x.key.to_s] }.first(limit)
    end

    def playbooks(q, limit, intent: nil)
      Playbook.all.select(&:runnable?).filter_map do |p|
        sc = score_text(q, p.key, p.title, p.description) +
             (p.mainline_names.any? { |n| n.include?(q.downcase.tr(" ", "-")) } ? 25 : 0) +
             (p.situation_specs.any? { |s| s["question"].to_s.downcase.include?(q.downcase) } ? 15 : 0)
        next if sc.zero?
        Hit.new(group: "playbooks", key: p.key, title: p.title, url: h.playbook_path(p.key),
                subtitle: p.description.to_s.truncate(150),
                badge: "#{p.mainline_names.size} legs · #{p.situation_specs.size} branches#{p.installed? ? '' : ' · not installed'}",
                action: p.installed? ? "Start a #{p.wording['run']}" : "Install it",
                action_url: h.playbook_path(p.key), score: sc)
      end.sort_by { |x| [-x.score, x.key.to_s] }.first(limit)
    end

    def jobs(q, viewer, limit)
      return [] unless viewer
      runs = matching(PlaybookRun.where(user: viewer).or(PlaybookRun.where(reviewer: viewer)),
                      %w[reference playbook_key], q).order(created_at: :desc).limit(limit)
      runs.map do |r|
        nxt = r.route.map { |s| s[:name] }.find { |n| r.legs.dig(n, "status") != "verified" }
        Hit.new(group: "jobs", key: r.reference, title: "#{r.playbook.wording['run'].capitalize} #{r.reference}",
                url: h.playbook_run_path(r), subtitle: nxt ? "Next: #{Skill.current(nxt)&.title || nxt}" : "Every leg verified",
                badge: "#{r.playbook.title} · #{r.legs.count { |_, v| v['status'] == 'verified' }} of #{r.legs.size} verified · #{r.status}",
                action: "Open the #{r.playbook.wording['run']}", action_url: h.playbook_run_path(r),
                score: score_text(q, r.reference, r.playbook.title) + 20)
      end
    end

    def flows(q, viewer, limit)
      return [] unless viewer
      matching(Flow.where(user: viewer), %w[name description], q).limit(limit).map do |f|
        live = f.runs.where(status: %w[running on_hold]).order(created_at: :desc).first
        Hit.new(group: "flows", key: f.id.to_s, title: f.name, url: h.flow_path(f),
                subtitle: live ? "Running: task #{live.current_index + 1}, #{live.current['title']}" : f.description.to_s.truncate(140),
                badge: "#{f.steps.size} tasks · about #{number_with_delimiter(f.estimate['tokens'])} tokens",
                action: live ? "Open the run" : "Run it", action_url: live ? h.flow_run_path(live) : h.flow_path(f),
                score: score_text(q, f.name, f.description) + (live ? 15 : 0))
      end.select { |x| x.score.positive? }.sort_by { |x| [-x.score, x.key.to_s] }
    end

    def resources(q, viewer, limit)
      folders = ResourceFolder.includes(:parent).select { |f| f.visible_to?(viewer) }.map(&:id)
      matching(Resource.where(folder_id: folders), %w[name description], q).limit(limit).map do |r|
        Hit.new(group: "resources", key: r.key, title: r.name, url: h.resources_path(folder: r.folder_id),
                subtitle: r.description.to_s.truncate(140), badge: [r.folder&.name, r.kind].compact.join(" · "),
                action: "Download", action_url: h.download_resource_path(r), score: score_text(q, r.name, r.description))
      end.select { |x| x.score.positive? }.sort_by { |x| [-x.score, x.key.to_s] }
    end

    def formulas(q, limit)
      matching(FormulaCommand.live, %w[key name description syntax], q).limit(limit * 2).map do |c|
        Hit.new(group: "formulas", key: c.key, title: c.name, url: h.formulas_path(provider: c.provider, q: c.key),
                subtitle: c.description.to_s.truncate(140), badge: "#{FormulaCommand.provider_name(c.provider)} · #{c.category} · #{c.status}",
                score: score_text(q, c.key, c.name, c.description))
      end.select { |x| x.score > 3 }.sort_by { |x| [-x.score, x.key.to_s] }.first(limit)
    end

    def macros(q, viewer, limit)
      matching(MacroReview.approved, %w[title], q).limit(limit).select { |m| m.visible_to?(viewer) }.map do |m|
        Hit.new(group: "macros", key: m.subject_key, title: m.title, url: h.macro_review_path(m),
                subtitle: m.reason.to_s.truncate(140), badge: "#{m.language_label} · saved #{number_with_delimiter(m.tokens_saved)} tokens",
                score: score_text(q, m.title) + 5)
      end.sort_by { |x| [-x.score, x.key.to_s] }
    end

    # The road around one skill: what comes before, what comes after, and the branches hanging off it.
    def neighbourhood(name, viewer)
      s = Skill.current(name) or return nil
      visible = ->(n) { (x = Skill.current(n)) && (viewer ? x.visible_to?(viewer) : x.shared?) ? x : nil }
      { centre: { name: s.name, title: s.title, url: h.skill_path(s) },
        before: SkillLink.neighbours(s.name, direction: :previous).filter_map { |l| (x = visible.(l[:name])) && { name: x.name, title: x.title, traffic: l[:traffic], url: h.skill_path(x) } }.first(3),
        after: SkillLink.neighbours(s.name, direction: :next).filter_map { |l| (x = visible.(l[:name])) && { name: x.name, title: x.title, traffic: l[:traffic], url: h.skill_path(x) } }.first(3),
        junction: Directions.find("junction:#{s.name}", viewer: viewer).then { |p| p.written ? p.body : nil } }
    rescue Directions::NotFound
      nil
    end

    def area_label(d) = d.presence && (Field.find_by(path: d)&.name || d.titleize)
    def number_with_delimiter(n) = ActiveSupport::NumberHelper.number_to_delimited(n.to_i)
  end
end
