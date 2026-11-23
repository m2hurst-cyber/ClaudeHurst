module SkillCapture
  # Turns an approved candidate into a published Skill, and handles later
  # revisions (new version of the same skill) and forks (new skill, parent link).
  class Publisher
    class Error < StandardError; end

    def self.publish!(candidate, reviewer:, attrs: {}) = new(reviewer).publish!(candidate, attrs)
    def self.revise!(skill, editor:, attrs:) = new(editor).revise!(skill, attrs)

    def initialize(user)
      @user = user
    end

    def publish!(candidate, attrs)
      raise Error, "Only #{candidate.reviewer_roles.join('/')} users can publish this workflow" unless candidate.reviewable_by?(@user)
      raise Error, "Candidate is already #{candidate.status}" unless candidate.open?

      candidate.assign_attributes(attrs.slice(*draft_keys)) if attrs.present?
      raise Error, "Generate or write a draft first" unless candidate.drafted?

      skill = nil
      Skill.transaction do
        previous = Skill.published.where(name: candidate.draft_name).order(version: :desc).first
        skill = Skill.create!(
          name: candidate.draft_name,
          version: next_version(candidate.draft_name),
          title: candidate.draft_title,
          description: candidate.draft_description,
          body: candidate.draft_body,
          domain: candidate.domain,
          tags: candidate.draft_tags,
          inputs: candidate.draft_inputs,
          outputs: candidate.draft_outputs,
          parent_skill: previous,
          published_by: @user,
          published_at: Time.current,
          source: source_for(candidate)
        )
        previous&.update!(status: "superseded")
        candidate.update!(status: "approved", skill: skill, reviewer: @user, reviewed_at: Time.current)
      end

      after_publish(skill, "skill.published", candidate: candidate)
      candidate.contributors.where.not(id: @user.id).find_each do |u|
        Notification.create!(user: u, subject: skill, kind: "skill_published",
                             title: "Your workflow is now a skill: #{skill.title}",
                             url: Rails.application.routes.url_helpers.skill_path(skill))
      end
      skill
    end

    # Same name → next version (old one superseded). New name → fork (old one stays published).
    def revise!(skill, attrs)
      raise Error, "Not allowed to revise this skill" unless SkillPolicy.new(@user, skill).update?

      name = attrs[:name].presence || skill.name
      fork = name != skill.name
      new_skill = nil
      Skill.transaction do
        new_skill = Skill.create!(
          name: name,
          version: next_version(name),
          title: attrs[:title].presence || skill.title,
          description: attrs[:description].presence || skill.description,
          body: attrs[:body].presence || skill.body,
          domain: attrs[:domain].presence || skill.domain,
          tags: attrs.key?(:tags) ? Array(attrs[:tags]) : skill.tags,
          inputs: skill.inputs,
          outputs: skill.outputs,
          license: skill.license,
          parent_skill: skill,
          published_by: @user,
          published_at: Time.current,
          source: skill.source.merge("revised_from" => "#{skill.name}@#{skill.version}",
                                     "change_note" => attrs[:change_note].presence).compact
        )
        skill.update!(status: "superseded") unless fork
      end
      after_publish(new_skill, fork ? "skill.forked" : "skill.revised", from: "#{skill.name}@#{skill.version}")
      new_skill
    end

    private

    def draft_keys
      %i[draft_name draft_title draft_description draft_body draft_tags draft_inputs draft_outputs review_notes]
    end

    def next_version(name)
      (Skill.where(name: name).maximum(:version) || 0) + 1
    end

    def source_for(candidate)
      {
        "candidate_id" => candidate.id,
        "origin" => candidate.origin,
        "workflow" => candidate.steps,
        "application" => "great-southern-copacker-crm-erp",
        "occurrences" => candidate.occurrence_count,
        "distinct_users" => candidate.distinct_user_count,
        "contributor_ids" => candidate.contributor_ids,
        "contributors" => candidate.contributors.map(&:display_name),
        "first_seen_at" => candidate.first_seen_at&.iso8601,
        "last_seen_at" => candidate.last_seen_at&.iso8601,
        "draft_generator" => candidate.draft_generator
      }.compact
    end

    def after_publish(skill, action, metadata = {})
      AuditLogger.record(user: @user, action: action, subject: skill,
                         metadata: metadata.transform_values { |v| v.is_a?(ActiveRecord::Base) ? v.id : v }
                                           .merge(name: skill.name, version: skill.version))
      SkillFile.export(skill)
      check_publish_rate!
    end

    # Misuse alert: unusually many publishes by one person in an hour.
    def check_publish_rate!
      recent = AuditLog.where(user: @user, action: %w[skill.published skill.revised skill.forked])
                       .where("created_at > ?", 1.hour.ago).count
      return if recent <= Config.publish_alert_threshold

      AuditLogger.record(user: @user, action: "skill_capture.alert", metadata: { reason: "publish_rate", count_last_hour: recent })
      User.active.where(role: "admin").find_each do |admin|
        Notification.create!(user: admin, kind: "skill_capture_alert",
                             title: "Unusual skill publishing: #{@user.display_name} published #{recent} skills in the last hour")
      end
    end
  end
end
