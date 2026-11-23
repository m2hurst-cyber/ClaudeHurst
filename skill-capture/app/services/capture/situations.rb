module Capture
  # New situations found while working a return become branches: a proposed Situation plus a
  # branch candidate for the area's reviewers. When the branch is published, the situation goes
  # live for every return (Publisher activates it; the playbook links it and updates directions).
  module Situations
    module_function

    def describe!(run, text, user:, client: nil)
      raise ArgumentError, "Describe the situation" if text.to_s.strip.length < 8
      pb = run.playbook
      r = SituationAdvisor.call(pb, text, client: client)
      if r.match
        run.update!(answers: run.answers.merge(r.match.key => "yes"))
        AuditLog.record("situation.matched", user: user, subject: run, situation: r.match.key, by: r.by)
        return [:matched, r.match, r]
      end

      p = r.proposal
      key = unique_key(pb.key, Naming.skill_name(p[:title]).first(40).sub(/-+\z/, ""))
      base = Skill.current(p[:after]) or raise ArgumentError, "#{p[:after]} isn't published"
      steps = p[:steps].map { |l| ["excel.step:#{l.parameterize}", l] }
      steps.each { |k, l| ActionDefinition.find_or_create_by!(key: k) { |d| d.label = l; d.domain = pb.area } }
      c = SkillCandidate.create!(
        signature: "situation:#{pb.key}:#{key}:#{SecureRandom.hex(4)}", steps: steps.map(&:first), domain: pb.area,
        origin: "manual", proposal_kind: "branch", base_skill: base, requested_by: user,
        draft_title: p[:title], draft_description: p[:description],
        occurrence_count: 1, distinct_actor_count: 1, contributors: [{ "key" => user.actor_key, "name" => user.name }],
        first_seen_at: Time.current, last_seen_at: Time.current,
        review_notes: "New situation for the #{pb.title} playbook, raised on return #{run.reference}: #{SituationAdvisor.redact(text)}. " \
                      "Intake question: #{p[:question]} Forms: #{p[:forms].join(', ').presence || 'to confirm'}. (#{r.by == 'ai' ? 'AI' : 'Rules'}: #{r.rationale})"
      )
      sit = Situation.create!(playbook_key: pb.key, key: key, question: p[:question], after_skill: base.name,
                              forms: p[:forms], keywords: p[:keywords], status: "proposed", candidate: c, proposed_by: user,
                              position: Situation.where(playbook_key: pb.key).maximum(:position).to_i + 1)
      Config.llm_enabled? ? SkillDraftJob.perform_later(c.id) : DraftGenerator.call(c)
      c.notify_reviewers!("New tax situation for review: #{p[:title]}")
      run.update!(answers: run.answers.merge(key => "yes"))
      AuditLog.record("situation.proposed", user: user, subject: sit, playbook: pb.key, after: base.name, by: r.by)
      [:proposed, sit, r]
    end

    # Called when a proposed situation's branch is published: rejoin the mainline and update directions.
    def activated!(situation, user:)
      pb = Playbook.find(situation.playbook_key)
      names = pb.mainline_names
      nxt = names[names.index(situation.after_skill).to_i + 1]
      SkillLink.find_or_create_by!(from_node: situation.branch_skill, to_node: nxt, origin: "manual") { |l| l.created_by = user } if nxt && names.include?(situation.after_skill)
      pb.refresh_junctions!(user)
    rescue Playbook::Error => e
      Rails.logger.warn("Situation #{situation.key}: #{e.message}")
    end

    def unique_key(pb_key, base)
      base = base.presence || "situation"
      key = base
      n = 2
      while Situation.exists?(playbook_key: pb_key, key: key)
        key = "#{base}-#{n}"
        n += 1
      end
      key
    end
  end
end
