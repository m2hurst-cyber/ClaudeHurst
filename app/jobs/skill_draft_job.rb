class SkillDraftJob < ApplicationJob
  queue_as :default

  def perform(candidate_id)
    candidate = SkillCandidate.find_by(id: candidate_id)
    return unless candidate&.open?
    SkillCapture::DraftGenerator.call(candidate)
  end
end
