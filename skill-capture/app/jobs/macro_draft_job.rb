# After the AI does a scriptable task for the first time, write the macro for next time.
class MacroDraftJob < ApplicationJob
  queue_as :default

  def perform(kind, key, title, app:, instructions: nil, skill_name: nil, note: nil, usage: nil, run_id: nil)
    review = MacroReview.for_subject(kind, key)
    return if review&.approved? || review&.status == "rejected"
    skill = skill_name.present? ? Skill.current(skill_name) : nil
    review ||= Capture::MacroScreen.review!(kind: kind, key: key, title: title, instructions: instructions, app: app, skill: skill)
    return if review.verdict == "ai" && review.score.negative?
    suggestion = Capture::MacroWriter.call(title: title, instructions: instructions, app: app, skill: skill, note: note, usage: usage)
    return if suggestion.nil?
    review.update!(suggestion: review.suggestion.merge(suggestion), written_by: "ai", source_run_id: run_id,
                   app: app, status: "proposed",
                   reason: "#{review.reason} The AI wrote this script from the first run; approve it and later runs skip the AI.")
    AuditLog.record("macro_review.written_by_ai", subject: review, key: key, confidence: suggestion["confidence"])
    review.notify_reviewers!
  end
end
