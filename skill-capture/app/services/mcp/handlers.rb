module Mcp
  # What each tool actually does. Every handler returns a plain Hash; the controller wraps it as MCP
  # content. `ctx` carries who is calling: a person (user) or an agent (source), and the URL helpers.
  module Handlers
    extend ActionView::Helpers::TextHelper
    module_function

    def h = Rails.application.routes.url_helpers
    def viewer(ctx) = ctx[:user]
    def person!(ctx, what) = ctx[:user] || raise(Registry::Error.new(-32_000, "#{what} needs a person's add-in token; this is an agent token"))

    # ---------- the library ----------
    def search_skills(a, ctx)
      scope = Skill.published.visible_to(viewer(ctx)).search(a["query"]).recent
      scope = scope.where(domain: a["area"]) if a["area"].present?
      scope = scope.classified_as(app: a["app"].presence_in(SkillClassification::APPS), field: nil) if a["app"].present?
      scope = scope.at_level(a["level"], viewer(ctx)) if viewer(ctx) && Skill::LEVELS.include?(a["level"])
      skills = scope.limit([[a["limit"].to_i, 1].max, 100].min.nonzero? || 20).to_a
      { count: skills.size,
        skills: skills.map { |s| summary(s) },
        note: skills.empty? ? "Nothing matched. Try fewer words, or search without an area." : nil }.compact
    end

    def get_skill(a, ctx)
      s = Skill.current(a["name"].to_s)
      raise Registry::Error.new(-32_000, "No skill named #{a['name']}") unless s && (viewer(ctx) ? s.visible_to?(viewer(ctx)) : s.shared?)
      return { name: s.name, markdown: Capture::LlmMarkdown.skill(s, viewer: viewer(ctx)) } if a["markdown"]
      b = Capture::Bundle.for(s, viewer: viewer(ctx), url_for: ->(r) { h.api_v1_resource_url(r.key.delete_prefix("resource:"), host: ctx[:host]) })
      b.merge(estimate: Capture::Estimator.for_step({ "title" => s.title, "instructions" => s.description, "skill_name" => s.name }),
              url: h.skill_url(s, host: ctx[:host]))
    end

    def find_route(a, ctx)
      from = a["from"].to_s
      raise Registry::Error.new(-32_000, "No skill named #{from}") unless Skill.current(from)
      if a["to"].present?
        map = Capture::RouteMap.call(user: viewer(ctx))
        map[:nodes].select! { |n| n[:kind] == "skill" }
        ids = map[:nodes].map { |n| n[:id] }.to_set
        map[:edges].select! { |e| ids.include?(e[:from]) && ids.include?(e[:to]) }
        r = Capture::RoutePlanner.new(map).route(from, a["to"].to_s)
        raise Registry::Error.new(-32_000, "No known road from #{from} to #{a['to']}") unless r
        { from: from, to: a["to"], skills: r.keys,
          legs: r.legs.map { |l| l.slice(:from, :to, :traffic, :manual) },
          directions: Capture::Directions.for_route(r.keys, viewer: viewer(ctx)).map(&:to_h) }
      else
        nxt = SkillLink.neighbours(from, direction: :next).filter_map do |l|
          s = Skill.current(l[:name])
          next unless s && (viewer(ctx) ? s.visible_to?(viewer(ctx)) : s.shared?)
          { name: s.name, title: s.title, traffic: l[:traffic], on_the_route: l[:manual] }
        end
        junction = place("junction:#{from}", viewer(ctx))
        { from: from, next_up: nxt, junction: junction,
          note: nxt.empty? ? "Nothing follows this skill yet." : nil }.compact
      end
    end

    # ---------- playbooks and jobs ----------
    def list_playbooks(a, ctx)
      pbs = Capture::Playbook.all.select(&:runnable?)
      pbs = pbs.select { |p| p.key == a["key"] } if a["key"].present?
      raise Registry::Error.new(-32_000, "No playbook with key #{a['key']}") if pbs.empty?
      detail = a["key"].present?
      { playbooks: pbs.map { |p|
        base = { key: p.key, title: p.title, area: p.area, installed: p.installed?,
                 calls_a_run: p.wording["run"], steps: p.mainline_names,
                 branches: p.situation_specs.map { |s| { key: s["key"], question: s["question"], adds: s["branch"] } } }
        next base unless detail
        base.merge(description: p.description, disclaimer: p.disclaimer,
                   documents: p.catalog.map { |k, d| { kind: k, name: d["name"], fields: Array(d["fields"]).map { |f| f["key"] } } },
                   legs: p.leg_specs.fetch("legs", {}).transform_values { |l| { documents: l["documents"], checks: Array(l["checks"]).map { |c| c["label"] || c["text"] || c["type"] } } })
      } }
    end

    def start_job(a, ctx)
      user = person!(ctx, "Starting a job")
      pb = Capture::Playbook.find(a["playbook"].to_s)
      raise Registry::Error.new(-32_000, "Install #{pb.title} first") unless pb.installed?
      raise Registry::Error.new(-32_000, "#{pb.title} is a library of worksheet skills, not something you run") unless pb.runnable?
      run = user.playbook_runs.new(playbook_key: pb.key, reference: a["reference"].to_s.squish,
                                   answers: (a["answers"] || {}).transform_values { |v| v.to_s.downcase })
      raise Registry::Error.new(-32_000, run.errors.full_messages.to_sentence) unless run.save
      AuditLog.record("playbook_run.started", user: user, subject: run, playbook: pb.key, via: "mcp")
      Capture::Legs.new(run).verify_all! if pb.prepares_legs?
      job_state(run.reload, ctx)
    rescue Capture::Playbook::Error => e
      raise Registry::Error.new(-32_000, e.message)
    end

    def get_job(a, ctx)
      job_state(find_run(a, ctx), ctx)
    end

    def add_job_document(a, ctx)
      user = person!(ctx, "Adding a document")
      run = find_run(a, ctx)
      raise Registry::Error.new(-32_000, "Only #{run.user.name} or their reviewer can add to this job") unless run.visible_to?(user)
      kind = a["kind"].to_s
      spec = run.playbook.catalog[kind] or raise Registry::Error.new(-32_000, "#{run.playbook.title} has no document kind #{kind}. Kinds: #{run.playbook.catalog.keys.join(', ')}")
      data = a["content_base64"].present? ? Base64.decode64(a["content_base64"]) : "document recorded over MCP"
      doc = run.documents.new(kind: kind, filename: a["filename"].presence || "#{kind}.pdf", content_type: "application/pdf",
                              byte_size: data.bytesize, checksum: Digest::SHA256.hexdigest(data),
                              content: Base64.strict_encode64(data), uploaded_by: user,
                              status: a["status"].presence_in(%w[read confirmed]) || "read", read_by: "mcp")
      doc.assign_fields(a["fields"] || {}, run.playbook.catalog)
      doc.label = spec["name"]
      raise Registry::Error.new(-32_000, doc.errors.full_messages.to_sentence) unless doc.save
      AuditLog.record("return_document.added", user: user, subject: run, kind: kind, via: "mcp")
      Capture::Legs.new(run.reload).verify_all!
      { added: { kind: kind, label: doc.label, status: doc.status, fields: doc.fields } }.merge(job_state(run.reload, ctx))
    end

    # ---------- work assigned to me ----------
    def list_tasks(a, ctx)
      limit = [[a["limit"].to_i, 1].max, 50].min.nonzero? || 10
      scope = AddinCommand.pending.where(kind: "flow_task").order(:created_at)
      scope = ctx[:source] ? scope.where(target_source: ctx[:source]) : scope.where(target_user: ctx[:user])
      tasks = scope.limit(limit * 3).filter_map do |c|
        p = c.payload
        run = FlowRun.find_by(id: p["flow_run_id"])
        next unless run&.running? && run.current_index == p["step_index"].to_i
        next if p["part_id"].present? && Flow.parts(run.current).find { |x| x["id"] == p["part_id"] }&.dig("state") == "done"
        { flow: p["flow"], flow_run_id: p["flow_run_id"], step: p["step_index"], part: p["part_id"],
          title: p["title"], app: p["app"], instructions: p["instructions"], skill: Array(p["skills"]).first,
          engine: p["engine"], suggested_model: p["model"], nature: p["nature"],
          anticipated: p["estimate"], handed_over: p["previous"], macro: p.dig("macro", "code"),
          finish_with: "complete_task" }
      end.first(limit)
      { count: tasks.size, tasks: tasks,
        note: tasks.empty? ? "Nothing is waiting for you. Tasks arrive when a flow hands one to you." : nil }.compact
    end

    def complete_task(a, ctx)
      run = FlowRun.find_by(id: a["flow_run_id"]) or raise Registry::Error.new(-32_000, "No flow run #{a['flow_run_id']}")
      usage = { "model" => a["model"], "input_tokens" => a["input_tokens"], "output_tokens" => a["output_tokens"], "duration_ms" => a["duration_ms"] }.compact_blank
      args = { index: a["step"].to_i, note: a["note"], usage: usage }.merge(ctx[:source] ? { source: ctx[:source] } : { user: ctx[:user] })
      a["part"].present? ? run.complete_part!(**args, part_id: a["part"]) : run.complete!(**args)
      cur = run.reload.current
      { status: run.status, now: run.running? && cur && { step: run.current_index, title: cur["title"], app: cur["app"], state: cur["state"] },
        spent_so_far: run.tally["spent"], anticipated_total: run.tally.dig("estimate", "tokens"),
        url: h.flow_run_url(run, host: ctx[:host]) }.compact
    rescue FlowRun::Error => e
      raise Registry::Error.new(-32_000, e.message)
    end

    def report_usage(a, ctx)
      skill = Skill.current(a["skill"].to_s) or raise Registry::Error.new(-32_000, "No skill named #{a['skill']}")
      run = SkillRun.from_report(skill, a.slice("model", "input_tokens", "output_tokens", "duration_ms", "status", "trial_of"),
                                 agent: ctx[:source]&.name || "#{ctx[:user]&.name} (MCP)", source: ctx[:source], user: ctx[:user])
      run.nature = Capture::TaskProfile.infer([skill.title, skill.description].join(". "))
      run.cost = Capture::Models.cost(run.model, run.input_tokens, run.output_tokens)
      raise Registry::Error.new(-32_000, run.errors.full_messages.to_sentence) unless run.save
      out = { recorded: { skill: skill.name, tokens: run.total_tokens, cost: run.cost.to_f, model: run.model },
              usage: Capture::Intensity.for(skill.name) }
      if a["macro_code"].to_s.strip.length > 20
        r = MacroReview.approved_for("skill", skill.name) ||
            Capture::MacroScreen.review!(kind: "skill", key: skill.name, title: skill.title, instructions: skill.description, skill: skill)
        unless r.approved?
          r.update!(suggestion: r.suggestion.merge("language" => a["macro_language"].presence_in(MacroReview::LANGUAGES) || "addin_js",
                                                   "code" => a["macro_code"].to_s, "confidence" => "medium"),
                    written_by: "ai", source_run_id: run.id, status: "proposed",
                    reason: "#{r.reason} Written over MCP from the run it just finished; approve it and later runs skip the AI.")
          r.notify_reviewers!
        end
        out[:macro_review] = { id: r.id, status: r.status, url: h.macro_review_url(r, host: ctx[:host]) }
      end
      out
    end

    # ---------- shared ----------
    def summary(s)
      c = SkillClassification.for(s.name)
      { name: s.name, title: s.title, description: s.description, area: s.domain, stage: s.stage, version: s.version,
        apps: c&.apps || [], fields: c ? c.ordered_fields.map(&:label) : [],
        usage: Capture::Intensity.for(s.name)&.slice(:runs, :avg_tokens, :intensity),
        macro: Capture::MacroScreen.approved_for_skill(s.name).present? }
    end

    def place(key, viewer)
      p = Capture::Directions.find(key, viewer: viewer)
      p.written ? { title: p.title, markdown: p.body } : nil
    rescue Capture::Directions::NotFound
      nil
    end

    def find_run(a, ctx)
      user = person!(ctx, "Reading a job")
      run = a["id"].present? ? PlaybookRun.find_by(id: a["id"]) : PlaybookRun.where(reference: a["reference"].to_s).order(created_at: :desc).first
      raise Registry::Error.new(-32_000, "No job with that reference") unless run
      raise Registry::Error.new(-32_000, "That job belongs to someone else") unless run.visible_to?(user)
      run
    end

    def job_state(run, ctx)
      legs = Capture::Legs.new(run)
      route = run.route.map do |step|
        name = step[:name]
        state = run.legs[name] || {}
        checks = Array(state["checks"])
        { leg: name, title: Skill.current(name)&.title || name, kind: step[:kind], status: state["status"] || "not_started",
          figures: state["figures"], blocking: checks.reject { |c| c["ok"] }.map { |c| c["label"] },
          documents_needed: Array(run.playbook.leg_spec(name)&.dig("documents")) }
      end
      { job: { reference: run.reference, playbook: run.playbook_key, called: run.playbook.wording["run"],
               status: run.status, verified: route.count { |l| l[:status] == "verified" }, of: route.size,
               url: h.playbook_run_url(run, host: ctx[:host]) },
        answers: run.answers, inputs: run.inputs,
        documents: run.documents.map { |d| { kind: d.kind, label: d.label, status: d.status, fields: d.fields } },
        road: route,
        next: route.find { |l| l[:status] != "verified" }&.slice(:leg, :title, :blocking, :documents_needed) }
    end
  end
end
