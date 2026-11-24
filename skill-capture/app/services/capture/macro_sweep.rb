module Capture
  # Screens everything for macro suitability: every published skill, and every task in the flows
  # someone can see. Already-approved reviews are left alone.
  module MacroSweep
    module_function

    def call(user:, limit: 500)
      n = 0
      Skill.published.visible_to(user).limit(limit).find_each do |s|
        next if MacroReview.approved_for("skill", s.name)
        MacroScreen.review!(kind: "skill", key: s.name, title: s.title, instructions: s.description,
                            nature: TaskProfile.infer([s.title, s.description].join(". ")),
                            app: SkillClassification.for(s.name)&.apps&.first || "Excel", skill: s, user: user)
        n += 1
      end
      Flow.where(user: user).find_each do |f|
        f.steps.each do |step|
          next if Flow.pause?(step) || MacroReview.approved_for("flow_step", "#{f.id}:#{step['id']}")
          MacroScreen.review!(kind: "flow_step", key: "#{f.id}:#{step['id']}", title: step["title"], instructions: step["instructions"],
                              nature: step["nature"], app: step["app"], skill: (Skill.current(step["skill_name"]) if step["skill_name"]), user: user)
          n += 1
        end
      end
      n
    end
  end
end
