module Capture
  # Triggers for the save / extend / branch protocols. Looks at one person's own recent work
  # (their add-in events) against the skills they can see:
  #
  #   extend  they finish a skill and then do the same extra steps, again and again
  #           → propose the skill's workflow + those steps as its next version
  #   branch  they start and finish a skill but do the middle differently, again and again
  #           → propose their way as a variant (a branch, starting in the sandbox)
  #   save    they repeat a workflow that no skill or candidate covers
  #           → propose saving it as a new skill
  #
  # Thresholds live in Protocol rows. A prompt the person dismissed is never raised again;
  # a snoozed one comes back after the protocol's snooze days. Accepting a prompt creates a
  # review candidate, so it goes through the same reviewers as everything else.
  class Prompter
    class Error < StandardError; end
    MAX_OPEN = 5
    MAX_SAVE_STEPS = 6

    def self.call(user, client: nil) = new(user, client: client).call
    def self.respond!(prompt, choice:, user:, title: nil, description: nil) = new(user).respond!(prompt, choice, title, description)

    def initialize(user, client: nil)
      @user = user
      @client = client # an Anthropic client for the evaluator (tests pass a stub)
      @protocols = %w[save extend branch].to_h { |k| [k, Protocol.for(k)] }
    end

    # => newly raised prompts
    def call
      return [] unless @user&.active? && @protocols.values.any?(&:enabled)
      sessions = timelines
      return [] if sessions.empty?

      found = []
      skills = Skill.visible_to(@user).published.filter_map { |s| (wf = Array(s.source["workflow"])).size >= 2 ? [s, wf] : nil }
      covered = sessions.map { |steps| Array.new(steps.size, false) }
      extends = Hash.new(0)
      branches = Hash.new(0)

      sessions.each_with_index do |steps, si|
        matches = exact_matches(steps, skills)
        matches.each { |_, i, e| (i..e).each { |x| covered[si][x] = true } }
        if on?("extend")
          max = @protocols["extend"]["max_added_steps"]
          matches.each_with_index do |(skill, _i, e), mi|
            stop = matches[mi + 1]&.at(1) || steps.size
            tail = steps[(e + 1)...[stop, e + 1 + max].min] || []
            tail = tail.take_while { |k| !Array(skill.source["workflow"]).include?(k) }
            (1..tail.size).each { |n| extends[[skill, tail.first(n)]] += 1 }
          end
        end
        # Variants are always marked covered, so a disabled branch protocol doesn't turn them into "save" prompts.
        branch_variants(steps, skills, covered[si]).each { |skill, variant, range| branches[[skill, variant]] += 1; range.each { |x| covered[si][x] = true } }
      end

      if on?("extend")
        best_per_skill(extends, @protocols["extend"]["min_repeats"], prefer: :longest).each do |(skill, tail), n|
          wf = Array(skill.source["workflow"])
          found << raise!("extend", skill: skill, steps: wf + tail, occurrences: n, evidence: { "added" => tail, "removed" => [] },
                          fingerprint: "extend:#{skill.name}:#{sig(tail)}")
        end
      end
      if on?("branch")
        best_per_skill(branches, @protocols["branch"]["min_repeats"], prefer: :most).each do |(skill, variant), n|
          wf = Array(skill.source["workflow"])
          found << raise!("branch", skill: skill, steps: variant, occurrences: n,
                          evidence: { "added" => variant - wf, "removed" => wf - variant }, fingerprint: "branch:#{skill.name}:#{sig(variant)}")
        end
      end
      if on?("save")
        repeated_unmatched(sessions, covered).each do |steps, n|
          found << raise!("save", skill: nil, steps: steps, occurrences: n, evidence: {}, fingerprint: "save:#{sig(steps)}")
        end
      end
      found.compact
    end

    def respond!(prompt, choice, title, description)
      raise Error, "Not your prompt" unless prompt.user_id == @user.id
      raise Error, "Already answered" if %w[accepted dismissed].include?(prompt.status)
      raise Error, "Not open" unless %w[open snoozed].include?(prompt.status)
      case choice
      when "snooze"
        days = @protocols[prompt.kind]["snooze_days"]
        prompt.update!(status: "snoozed", snoozed_until: days.days.from_now, response: "snooze", responded_at: Time.current)
        return nil
      when "dismiss"
        prompt.update!(status: "dismissed", response: "dismiss", responded_at: Time.current)
        return nil
      end
      raise Error, "Choose one of: #{prompt.choices.join(', ')}" unless prompt.choices.include?(choice)

      base = prompt.skill
      raise Error, "#{prompt.skill_name} is no longer published" if prompt.skill_name && !(base && base.visible_to?(@user))
      candidate = build_candidate(prompt, choice, base, title, description)
      prompt.update!(status: "accepted", response: choice, responded_at: Time.current, candidate: candidate)
      AuditLog.record("prompt.accepted", user: @user, subject: candidate, kind: prompt.kind, choice: choice, skill: prompt.skill_name)
      verb = { "save" => "Save as a skill", "extend" => "Extend", "branch" => "Branch" }[choice]
      candidate.notify_reviewers!("#{verb}#{base ? " “#{base.title}”" : ""}: proposed by #{@user.name}")
      Config.llm_enabled? ? SkillDraftJob.perform_later(candidate.id) : DraftGenerator.call(candidate)
      candidate.reload
    end

    private

    def on?(kind) = @protocols[kind].enabled
    def sig(steps) = SkillCandidate.signature_for(steps)

    def timelines
      days = @protocols.values.select(&:enabled).map { |p| p["lookback_days"] }.max
      UsageEvent.where(actor_key: @user.actor_key).where("occurred_at >= ?", days.days.ago).order(:session_key, :occurred_at, :id)
                .pluck(:session_key, :action_key, :occurred_at)
                .chunk_while { |a, b| a[0] == b[0] && b[2] - a[2] <= Config.session_gap }
                .map { |evs| evs.map { |e| e[1] }.chunk_while { |a, b| a == b }.map(&:first) }
                .select { |steps| steps.size >= 2 }
    end

    # Exact runs of a skill's workflow; where they overlap, the longest wins.
    def exact_matches(steps, skills)
      all = skills.flat_map do |skill, wf|
        (0..steps.size - wf.size).select { |i| steps[i, wf.size] == wf }.map { |i| [skill, i, i + wf.size - 1] }
      end
      taken = -1
      all.sort_by { |_, i, e| [i, -(e - i)] }.each_with_object([]) do |m, out|
        next if m[1] <= taken
        out << m
        taken = m[2]
      end
    end

    # Runs that start with a skill's first step and end with its last, but differ in between.
    # When a run could be a variant of several skills (a skill and its own branch), it belongs
    # to the closest one: most of that skill's steps kept, fewest changes.
    def branch_variants(steps, skills, covered)
      extra = @protocols["branch"]["max_extra_steps"]
      exact = skills.map { |_, wf| wf }
      found = []
      skills.each do |skill, wf|
        (0...steps.size).each do |i|
          next unless steps[i] == wf.first && !covered[i]
          limit = [steps.size - 1, i + wf.size - 1 + extra].min
          j = ((i + 1)..limit).find { |x| steps[x] == wf.last && !covered[x] }
          next unless j
          variant = steps[i..j]
          kept = (variant & wf).size
          next if variant == wf || exact.include?(variant) || kept * 2 < wf.size || variant.uniq.size != variant.size
          found << [skill, variant, (i..j), [kept.to_f / wf.size, -((variant - wf).size + (wf - variant).size)]]
        end
      end
      taken = Set.new
      found.sort_by { |_, _, range, score| [-score[0], -score[1], range.first] }.filter_map do |skill, variant, range, _|
        next if range.any? { |x| taken.include?(x) }
        range.each { |x| taken << x }
        [skill, variant, range]
      end
    end

    def best_per_skill(counts, min, prefer:)
      counts.select { |_, n| n >= min }.group_by { |(skill, _), _| skill.name }.map do |_, rows|
        prefer == :longest ? rows.max_by { |(_, steps), n| [steps.size, n] } : rows.max_by { |(_, steps), n| [n, steps.size] }
      end
    end

    def repeated_unmatched(sessions, covered)
      p = @protocols["save"]
      tallies = Hash.new(0)
      sessions.each_with_index do |steps, si|
        segments = steps.each_index.reject { |x| covered[si][x] }.slice_when { |a, b| b != a + 1 }.map { |idx| steps.values_at(*idx) }
        segments.each do |seg|
          last_end = {}
          seg.each_index do |i|
            seen = Set.new
            (i...[seg.size, i + MAX_SAVE_STEPS].min).each do |j|
              break unless seen.add?(seg[j])
              next if j - i + 1 < p["min_steps"]
              keys = seg[i..j]
              next if last_end[keys] && i <= last_end[keys]
              last_end[keys] = j
              tallies[keys] += 1
            end
          end
        end
      end
      frequent = tallies.select { |_, n| n >= p["min_repeats"] }
      known = Skill.published.pluck(:source).map { |s| Array(s["workflow"]) }.to_set
      decided = SkillCandidate.where(status: %w[approved rejected dismissed]).pluck(:signature).to_set
      frequent.reject do |keys, n|
        known.include?(keys) || decided.include?(sig(keys)) ||
          frequent.any? { |other, m| other.size > keys.size && m >= n && contains?(other, keys) }
      end
    end

    def contains?(big, small) = (0..big.size - small.size).any? { |i| big[i, small.size] == small }

    def raise!(kind, skill:, steps:, occurrences:, evidence:, fingerprint:)
      digest = Digest::SHA256.hexdigest(fingerprint)
      prompt = @user.skill_prompts.find_by(fingerprint: digest)
      if prompt
        prompt.update!(occurrences: occurrences, last_seen_at: Time.current) if %w[open snoozed filtered].include?(prompt.status)
        # A pattern the AI passed over gets another look once it has happened twice as often.
        if prompt.status == "filtered" && occurrences >= 2 * prompt.evidence.fetch("filtered_at", occurrences).to_i
          prompt.update!(status: "evaluating")
          return evaluate!(prompt)
        end
        return nil
      end
      # One open nudge per skill and kind; a dismissed one for the same skill keeps it quiet for a while.
      scope = @user.skill_prompts.where(kind: kind, skill_name: skill&.name)
      return nil if skill && scope.where(status: %w[evaluating open snoozed]).exists?
      return nil if skill && scope.where(status: "dismissed").where("responded_at > ?", @protocols[kind]["lookback_days"].days.ago).exists?
      return nil if @user.skill_prompts.where(status: "open").count >= MAX_OPEN

      prompt = @user.skill_prompts.create!(kind: kind, skill_name: skill&.name, steps: steps, evidence: evidence, status: "evaluating",
                                           occurrences: occurrences, fingerprint: digest, last_seen_at: Time.current)
      evaluate!(prompt)
    end

    # The AI (or rules) decides whether this is worth asking about, and suggests a name and description.
    # Returns the prompt when it was opened, nil when it was filtered out.
    def evaluate!(prompt)
      r = PromptEvaluator.call(prompt, client: @client)
      min = Protocol.for("evaluation")["min_confidence"]
      ai = { "title" => r.title, "description" => r.description, "rationale" => r.rationale, "confidence" => r.confidence,
             "by" => r.by, "kind_found" => prompt.kind, "at" => Time.current.iso8601 }
      if r.worthwhile && r.confidence >= min
        kind = r.kind == "save" || prompt.skill_name ? r.kind : prompt.kind
        prompt.update!(status: "open", kind: kind, evidence: prompt.evidence.merge("ai" => ai))
        Notification.create!(user: @user, subject: prompt, kind: "prompt", title: prompt.headline,
                             url: Rails.application.routes.url_helpers.prompts_path)
        AuditLog.record("prompt.raised", user: @user, subject: prompt, kind: prompt.kind, skill: prompt.skill_name,
                        occurrences: prompt.occurrences, evaluated_by: r.by, confidence: r.confidence)
        prompt
      else
        prompt.update!(status: "filtered", evidence: prompt.evidence.merge("ai" => ai, "filtered_at" => prompt.occurrences))
        AuditLog.record("prompt.filtered", user: @user, subject: prompt, kind: prompt.kind, skill: prompt.skill_name,
                        evaluated_by: r.by, confidence: r.confidence, reason: r.rationale)
        nil
      end
    end

    def build_candidate(prompt, choice, base, title, description)
      steps = prompt.steps
      sig = sig(steps)
      if choice == "save" && (existing = SkillCandidate.open.find_by(signature: sig))
        existing.update!(requested_by: existing.requested_by || @user, origin: "manual", proposal_kind: "save",
                         draft_title: title.presence || prompt.ai["title"].presence || existing.draft_title,
                         draft_description: description.presence || prompt.ai["description"].presence || existing.draft_description)
        return existing
      end
      ai = prompt.ai
      default_title = case choice
                      when "save" then ai["title"].presence || "Untitled workflow"
                      when "extend" then base.title
                      when "branch" then (prompt.kind == "branch" && ai["title"].presence) || "#{base.title} (#{@user.name.split.first}'s way)"
                      end
      default_description = choice == prompt.kind ? ai["description"].presence : nil
      SkillCandidate.create!(
        signature: "prompt:#{choice}:#{SecureRandom.hex(8)}", steps: steps, origin: "manual", proposal_kind: choice,
        base_skill: choice == "save" ? nil : base,
        domain: base&.domain || @user.domains.first,
        draft_title: title.to_s.squish.first(200).presence || default_title,
        draft_description: description.to_s.squish.first(1024).presence || default_description || (choice == "extend" ? base.description : nil),
        requested_by: @user, occurrence_count: prompt.occurrences, distinct_actor_count: 1,
        contributors: [{ "key" => @user.actor_key, "name" => @user.name }],
        first_seen_at: prompt.created_at, last_seen_at: prompt.last_seen_at || Time.current,
        review_notes: proposal_note(prompt, choice, base)
      )
    end

    def proposal_note(prompt, choice, base)
      return "Saved from a repeated workflow (#{prompt.occurrences}×)." if choice == "save"
      parts = []
      parts << "Adds: #{prompt.added_labels.join(', ')}" if prompt.added_labels.any?
      parts << "Drops: #{prompt.removed_labels.join(', ')}" if prompt.removed_labels.any?
      verb = choice == "extend" ? "Extends" : "Branches"
      "#{verb} #{base.name} v#{base.version} (seen #{prompt.occurrences}×). #{parts.join('. ')}".strip
    end
  end
end
