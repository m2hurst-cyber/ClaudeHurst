class SkillDraftJob < ApplicationJob
  queue_as :default

  def perform(candidate_id)
    candidate = SkillCandidate.find_by(id: candidate_id)
    Capture::DraftGenerator.call(candidate) if candidate&.open?
  end
end
