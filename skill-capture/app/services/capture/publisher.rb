module Capture
  # Approved candidate → published Skill; later edits → new version (same name)
  # or fork (new name). Nothing published is ever overwritten.
  class Publisher
    class Error < StandardError; end

    DRAFT_KEYS = %i[draft_name draft_title draft_description draft_body draft_tags draft_inputs draft_outputs review_notes].freeze

    def self.publish!(candidate, reviewer:, attrs: {}) = new(reviewer).publish!(candidate, attrs)
    def self.revise!(skill, editor:, attrs:) = new(editor).revise!(skill, attrs)

    def initialize(user)
      @user = user
    end

    def publish!(candidate, attrs = {})
      raise Error, "You don't review the #{candidate.domain.presence || 'unassigned'} area" unless candidate.reviewable_by?(@user)
      raise Error, "Candidate is already #{candidate.status}" unless candidate.open?
      candidate.assign_attributes(attrs.slice(*DRAFT_KEYS)) if attrs.present?
      raise Error, "Generate or write a draft first" unless candidate.drafted?

      skill = nil
      Skill.transaction do
        previous = Skill.current(candidate.draft_name)
        skill = Skill.create!(
          name: candidate.draft_name, version: next_version(candidate.draft_name),
          title: candidate.draft_title.presence || candidate.display_title,
          description: candidate.draft_description, body: candidate.draft_body,
          domain: candidate.domain, tags: candidate.draft_tags,
          inputs: candidate.draft_inputs, outputs: candidate.draft_outputs,
          parent_skill: previous, published_by: @user, published_at: Time.current,
          source: provenance(candidate)
        )
        previous&.update!(status: "superseded")
        candidate.update!(status: "approved", skill: skill, reviewer: @user, reviewed_at: Time.current)
      end
      after_publish(skill, "skill.published", candidate_id: candidate.id)
      skill
    end

    def revise!(skill, attrs)
      raise Error, "You can't revise skills in the #{skill.domain.presence || 'unassigned'} area" unless SkillPolicy.new(@user, skill).update?
      raise Error, "Only the current version can be revised" unless skill.status == "published"

      name = attrs[:name].presence || skill.name
      fork = name != skill.name
      new_skill = nil
      Skill.transaction do
        new_skill = Skill.create!(
          name: name, version: next_version(name),
          title: attrs[:title].presence || skill.title,
          description: attrs[:description].presence || skill.description,
          body: attrs[:body].presence || skill.body,
          domain: skill.domain,
          tags: attrs.key?(:tags) ? Array(attrs[:tags]) : skill.tags,
          inputs: skill.inputs, outputs: skill.outputs, license: skill.license,
          parent_skill: skill, published_by: @user, published_at: Time.current,
          source: skill.source.merge("revised_from" => "#{skill.name}@#{skill.version}",
                                     "change_note" => attrs[:change_note].presence).compact
        )
        skill.update!(status: "superseded") unless fork
      end
      after_publish(new_skill, fork ? "skill.forked" : "skill.revised", from: "#{skill.name}@#{skill.version}")
      new_skill
    end

    private

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

    def after_publish(skill, action, **meta)
      AuditLog.record(action, user: @user, subject: skill, name: skill.name, version: skill.version, **meta)
      SkillFile.export(skill)
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
