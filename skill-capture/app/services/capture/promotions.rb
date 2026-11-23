module Capture
  # Moving a skill up a stage: request → gates → approval (or rejection), with an optional
  # incumbent retired when a better alternative is promoted.
  #
  #   local → firm    approved by a reviewer of the skill's area who didn't publish it or ask for it
  #   firm  → market  approved by an admin who didn't ask for it
  # Approval needs every gate to pass. Only admins may waive failed gates, with a written reason.
  class Promotions
    class Error < StandardError; end

    def initialize(user) = @user = user

    def request!(skill, pitch: nil, replaces: nil)
      to = skill.next_stage or raise Error, "#{skill.title} is already at the top stage"
      raise Error, "You can't see this skill" unless skill.visible_to?(@user)
      raise Error, "There's already an open promotion request for this skill" if Promotion.open.exists?(skill_name: skill.name)
      if replaces.present?
        incumbent = Skill.current(replaces) or raise Error, "No published skill #{replaces}"
        raise Error, "#{incumbent.title} isn't an alternative to #{skill.title}" unless incumbent.root_name == skill.root_name
      end
      p = Promotion.create!(skill_name: skill.name, skill_version: skill.version, from_stage: skill.stage, to_stage: to,
                            replaces_name: replaces.presence, pitch: pitch, requested_by: @user,
                            checks: Gates.for(skill, to).map(&:to_h))
      AuditLog.record("promotion.requested", user: @user, subject: p, skill: skill.name, to: to)
      approvers(p).each do |u|
        Notification.create!(user: u, subject: p, kind: "promotion", title: "Promote “#{skill.title}” to #{Skill::STAGE_LABELS[to]}?",
                             url: Rails.application.routes.url_helpers.promotions_path)
      end
      p
    end

    def approve!(promotion, notes: nil, waive: false)
      skill = promotion.skill or raise Error, "The skill is no longer published"
      raise Error, "This request is #{promotion.status}" unless promotion.status == "open"
      raise Error, "You can't approve your own request" if promotion.requested_by_id == @user.id
      raise Error, "You published this skill; another reviewer must approve it" if skill.published_by_id == @user.id && !@user.admin?
      raise Error, "Only #{approver_label(promotion)} can approve this" unless can_decide?(promotion)
      raise Error, "The skill moved since this was requested" unless skill.stage == promotion.from_stage

      checks = Gates.for(skill, promotion.to_stage)
      unless Gates.passed?(checks)
        raise Error, "Not every gate passes: #{checks.reject(&:passed).map(&:label).join(', ')}" unless waive
        raise Error, "Only admins can waive gates" unless @user.admin?
        raise Error, "Explain why the failed gates are waived" if notes.blank?
      end

      Skill.transaction do
        skill.update!(stage: promotion.to_stage, stage_changed_at: Time.current)
        promotion.update!(status: "approved", decided_by: @user, decided_at: Time.current, decision_notes: notes,
                          waived: !Gates.passed?(checks), checks: checks.map(&:to_h))
        retire!(promotion, skill) if promotion.replaces_name.present?
      end
      SkillFile.export(skill) if skill.shared?
      RestStops.capture!(skill, reason: "promoted", user: @user, label: "Promoted to #{skill.stage_label}")
      AuditLog.record("promotion.approved", user: @user, subject: promotion, skill: skill.name, to: promotion.to_stage, waived: promotion.waived)
      notify_people(skill, "“#{skill.title}” is now #{skill.stage_label}#{skill.stage == 'firm' ? ': available to the whole firm' : ': promoted to market'}")
      promotion
    end

    def reject!(promotion, notes:)
      raise Error, "This request is #{promotion.status}" unless promotion.status == "open"
      raise Error, "Only #{approver_label(promotion)} can decide this" unless can_decide?(promotion)
      raise Error, "Say why it's not ready" if notes.blank?
      promotion.update!(status: "rejected", decided_by: @user, decided_at: Time.current, decision_notes: notes)
      AuditLog.record("promotion.rejected", user: @user, subject: promotion, notes: notes)
      if promotion.requested_by
        Notification.create!(user: promotion.requested_by, subject: promotion, kind: "promotion",
                             title: "Promotion of “#{promotion.skill&.title}” not approved: #{notes.truncate(80)}",
                             url: Rails.application.routes.url_helpers.promotions_path)
      end
      promotion
    end

    def withdraw!(promotion)
      raise Error, "Only the requester can withdraw" unless promotion.requested_by_id == @user.id || @user.admin?
      promotion.update!(status: "withdrawn", decided_by: @user, decided_at: Time.current)
      promotion
    end

    def can_decide?(promotion)
      skill = promotion.skill
      return false unless skill && @user
      promotion.to_stage == "market" ? @user.admin? : @user.reviews?(skill.domain)
    end

    def self.can_request?(user, skill)
      user.present? && skill.next_stage.present? && skill.visible_to?(user) && !Promotion.open.exists?(skill_name: skill.name)
    end

    private

    def approver_label(p) = p.to_stage == "market" ? "an admin" : "a reviewer for this area"

    def approvers(p)
      skill = p.skill
      User.active.select { |u| u.id != @user.id && (p.to_stage == "market" ? u.admin? : u.reviews?(skill&.domain)) }
    end

    # The promoted alternative replaces the incumbent: the incumbent is deprecated (history kept).
    def retire!(promotion, winner)
      incumbent = Skill.current(promotion.replaces_name)
      return unless incumbent && incumbent.name != winner.name
      incumbent.update!(status: "deprecated")
      AuditLog.record("skill.deprecated", user: @user, subject: incumbent, replaced_by: winner.name, via: "promotion")
      notify_people(incumbent, "“#{incumbent.title}” was replaced by “#{winner.title}”")
    end

    def notify_people(skill, title)
      ids = Array(skill.source["contributor_keys"]).filter_map { |k| k[/\Auser:(\d+)\z/, 1]&.to_i } + [skill.published_by_id]
      User.active.where(id: ids.compact.uniq).where.not(id: @user.id).find_each do |u|
        Notification.create!(user: u, subject: skill, kind: "stage", title: title, url: Rails.application.routes.url_helpers.skill_path(skill))
      end
    end
  end
end
