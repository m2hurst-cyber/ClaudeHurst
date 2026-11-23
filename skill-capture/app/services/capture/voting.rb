module Capture
  # The internal vote: one +1/-1 per person per skill (by name), with an optional reason.
  # You can't vote for a skill you published or contributed to.
  module Voting
    class Error < StandardError; end

    module_function

    def own?(user, skill)
      skill.published_by_id == user.id || Array(skill.source["contributor_keys"]).include?(user.actor_key)
    end

    def cast!(user, skill, value, comment: nil)
      raise Error, "You can't see this skill" unless skill.visible_to?(user)
      raise Error, "You can't vote on a skill you published or contributed to" if own?(user, skill)
      v = value.to_i
      if v.zero?
        SkillVote.where(user: user, skill_name: skill.name).delete_all
        return nil
      end
      vote = SkillVote.find_or_initialize_by(user: user, skill_name: skill.name)
      vote.update!(value: v.positive? ? 1 : -1, comment: comment.presence || (vote.value == (v.positive? ? 1 : -1) ? vote.comment : nil))
      AuditLog.record("skill.voted", user: user, subject: skill, value: vote.value)
      vote
    end

    # Evidence for "which process is better": votes plus how each alternative actually runs.
    def comparison(skills)
      tallies = SkillVote.tallies(skills.map(&:name))
      metrics = SkillMetric.where(name: skills.map(&:name)).index_by(&:name)
      versions = Skill.where(name: skills.map(&:name)).group(:name).count
      rows = skills.map do |s|
        m = metrics[s.name]
        { skill: s, votes: tallies[s.name], metric: m, improvements: versions[s.name].to_i - 1,
          comments: SkillVote.where(skill_name: s.name).where.not(comment: [nil, ""]).includes(:user).order(updated_at: :desc).limit(3) }
      end
      # Preferred: highest net vote; ties go to the faster road (lower travel time), then the more used.
      leader = rows.max_by { |r| [r[:votes][:score], -(r[:metric]&.median_minutes || Float::INFINITY), r[:metric]&.trips.to_i] }
      rows.each { |r| r[:preferred] = rows.size > 1 && r.equal?(leader) && r[:votes][:score].positive? }
      rows
    end
  end
end
