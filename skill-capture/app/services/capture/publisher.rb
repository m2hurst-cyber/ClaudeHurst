module Capture
  # Approved candidate → published Skill; later edits → new version (same name)
  # or fork (new name). Nothing published is ever overwritten.
  class Publisher
    class Error < StandardError; end

    DRAFT_KEYS = %i[draft_name draft_title draft_description draft_body draft_tags draft_inputs draft_outputs review_notes].freeze

    def self.publish!(candidate, reviewer:, attrs: {}, source_extra: {}) = new(reviewer).publish!(candidate, attrs, source_extra)
    def self.revise!(skill, editor:, attrs:) = new(editor).revise!(skill, attrs)

    def initialize(user)
      @user = user
    end

    def publish!(candidate, attrs = {}, source_extra = {})
      raise Error, "You don't review the #{candidate.domain.presence || 'unassigned'} area" unless candidate.reviewable_by?(@user)
      raise Error, "Candidate is already #{candidate.status}" unless candidate.open?
      candidate.assign_attributes(attrs.slice(*DRAFT_KEYS)) if attrs.present?
      raise Error, "Generate or write a draft first" unless candidate.drafted?
      enforce_standard!(SkillStandard.check(name: candidate.draft_name, description: candidate.draft_description, body: candidate.draft_body))

      previous = Skill.current(candidate.draft_name)
      branch_of = candidate.proposal_kind == "branch" && !previous ? candidate.base_skill : nil
      RestStops.capture!(previous, reason: "before_update", user: @user) if previous
      skill = nil
      Skill.transaction do
        skill = Skill.create!(
          name: candidate.draft_name, version: next_version(candidate.draft_name),
          title: candidate.draft_title.presence || candidate.display_title,
          description: candidate.draft_description, body: candidate.draft_body,
          domain: candidate.domain, tags: candidate.draft_tags,
          inputs: candidate.draft_inputs, outputs: candidate.draft_outputs,
          parent_skill: previous || branch_of, published_by: @user, published_at: Time.current,
          source: provenance(candidate).merge(candidate.worksheet.present? ? { "worksheet" => candidate.worksheet } : {}).merge(source_extra.to_h.stringify_keys),
          stage: previous&.stage || PromotionPolicy.current.initial_stage, stage_changed_at: previous&.stage_changed_at || Time.current
        )
        previous&.update!(status: "superseded")
        candidate.update!(status: "approved", skill: skill, reviewer: @user, reviewed_at: Time.current)
      end
      after_publish(skill, "skill.published", candidate_id: candidate.id)
      notify_contributors(candidate, skill)
      Bounties.new.register_fix(skill, solver: candidate.requested_by || @user) if skill.version > 1
      Bounties.new.register_fix(skill, solver: candidate.requested_by || @user, branch_of: branch_of.name) if branch_of
      rest_stops_after(skill, branch_of: branch_of, reason: previous ? "revised" : "published")
      # A proposed playbook situation goes live when its branch is published.
      Situation.where(candidate_id: candidate.id, status: "proposed").find_each do |sit|
        sit.update!(status: "active", branch_skill: skill.name)
        Situations.activated!(sit, user: @user)
      end
      skill
    end

    def revise!(skill, attrs)
      # authorized: the caller already checked (a rest stop revert by a sandbox skill's own publisher)
      unless attrs[:authorized] || SkillPolicy.new(@user, skill).update?
        raise Error, "You can't revise skills in the #{skill.domain.presence || 'unassigned'} area"
      end
      raise Error, "Only the current version can be revised" unless skill.status == "published"

      name = attrs[:name].presence || skill.name
      fork = name != skill.name
      # A revert restores what was published before, as it was; everything else must meet the format.
      unless attrs[:restoring]
        enforce_standard!(SkillStandard.check(name: name, description: attrs[:description].presence || skill.description,
                                              body: attrs[:body].presence || skill.body))
      end
      RestStops.capture!(skill, reason: "before_update", user: @user) unless fork
      new_skill = nil
      Skill.transaction do
        new_skill = Skill.create!(
          name: name, version: next_version(name),
          title: attrs[:title].presence || skill.title,
          description: attrs[:description].presence || skill.description,
          body: attrs[:body].presence || skill.body,
          domain: skill.domain,
          tags: attrs.key?(:tags) ? Array(attrs[:tags]) : skill.tags,
          inputs: attrs.key?(:inputs) ? Array(attrs[:inputs]) : skill.inputs,
          outputs: attrs.key?(:outputs) ? Array(attrs[:outputs]) : skill.outputs, license: skill.license,
          parent_skill: skill, published_by: @user, published_at: Time.current,
          # A new version keeps its stage (fixes go live); a branch starts in the sandbox.
          stage: fork ? PromotionPolicy.current.initial_stage : skill.stage,
          stage_changed_at: fork ? Time.current : skill.stage_changed_at,
          source: skill.source.merge("revised_from" => "#{skill.name}@#{skill.version}",
                                     "change_note" => attrs[:change_note].presence,
                                     "workflow" => attrs[:workflow].presence || skill.source["workflow"])
                                .merge(attrs[:source_extra].to_h.stringify_keys).compact
        )
        skill.update!(status: "superseded") unless fork
      end
      after_publish(new_skill, fork ? "skill.forked" : "skill.revised", from: "#{skill.name}@#{skill.version}")
      Bounties.new.register_fix(new_skill, solver: @user, branch_of: fork ? skill.name : nil)
      rest_stops_after(new_skill, branch_of: fork ? skill : nil, reason: "revised")
      new_skill
    end

    private

    def enforce_standard!(report)
      return if report.ok?
      raise Error, "Doesn't meet the Agent Skills format: #{report.errors.map(&:message).join('; ')}"
    end

    def rest_stops_after(skill, branch_of:, reason:)
      if branch_of
        RestStops.branch_point!(skill, branch_of, user: @user)
        RestStops.capture!(skill, reason: "branched", user: @user)
      else
        RestStops.capture!(skill, reason: reason, user: @user)
      end
    end

    # Contributors who are people in this system (captured through the Office add-in) hear about it.
    def notify_contributors(candidate, skill)
      ids = candidate.contributors.filter_map { |c| c["key"].to_s[/\Auser:(\d+)\z/, 1]&.to_i }
      User.active.where(id: ids).where.not(id: @user.id).find_each do |u|
        Notification.create!(user: u, subject: skill, kind: "skill_published",
                             title: "Your workflow is now a skill: #{skill.title}",
                             url: Rails.application.routes.url_helpers.skill_path(skill))
      end
    end

    def next_version(name) = (Skill.where(name: name).maximum(:version) || 0) + 1

    def provenance(c)
      {
        "candidate_id" => c.id,
        "origin" => c.origin,
        "workflow" => c.steps,
        "sources" => UsageEvent.where(action_key: c.steps).distinct.joins(:source).pluck("sources.name").sort.presence,
        "occurrences" => c.occurrence_count,
        "distinct_people" => c.distinct_actor_count,
        "contributors" => c.contributor_names.presence,
        "contributor_keys" => c.contributors.map { |x| x["key"] }.presence,
        "requested_by" => c.requested_by&.name,
        "first_seen_at" => c.first_seen_at&.iso8601,
        "last_seen_at" => c.last_seen_at&.iso8601,
        "draft_generator" => c.draft_generator
      }.compact
    end

    # Rules are instant; a Claude classification runs in the background.
    def classify(skill)
      Config.llm_enabled? ? ClassifySkillJob.perform_later(skill.name) : Classifier.apply!(skill)
    rescue => e
      Rails.logger.warn("Classification skipped for #{skill.name}: #{e.class}: #{e.message}")
    end

    def after_publish(skill, action, **meta)
      classify(skill)
      AuditLog.record(action, user: @user, subject: skill, name: skill.name, version: skill.version, **meta)
      SkillFile.export(skill) if skill.shared? # sandbox skills stay out of the skill repository
      check_publish_rate!
    end

    # Misuse signal: unusually many publishes by one person in an hour.
    def check_publish_rate!
      recent = AuditLog.where(user: @user, action: %w[skill.published skill.revised skill.forked])
                       .where("created_at > ?", 1.hour.ago).count
      return if recent <= Config.publish_alert_threshold

      AuditLog.record("capture.alert", user: @user, reason: "publish_rate", count_last_hour: recent)
      User.active.where(role: "admin").find_each do |admin|
        Notification.create!(user: admin, kind: "alert",
                             title: "Unusual publishing: #{@user.name} published #{recent} skills in the last hour")
      end
    end
  end
end
