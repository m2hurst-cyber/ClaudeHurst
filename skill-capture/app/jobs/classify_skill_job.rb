class ClassifySkillJob < ApplicationJob
  queue_as :default

  def perform(name)
    skill = Skill.current(name)
    Capture::Classifier.apply!(skill) if skill
  end
end
