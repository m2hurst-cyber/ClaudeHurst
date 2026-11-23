# One return worked through a playbook: which situations apply and which steps are done.
# Deliberately holds no taxpayer data: a reference, yes/no answers and step names.
class PlaybookRun < ApplicationRecord
  SENSITIVE = [/\b\d{3}-?\d{2}-?\d{4}\b/, /\b\d{2}-?\d{7}\b/, /@/].freeze # SSN/ITIN, EIN, email

  belongs_to :user

  validates :playbook_key, presence: true
  validates :reference, presence: true, length: { maximum: 60 }
  validates :status, inclusion: { in: %w[open completed] }
  validate do
    if SENSITIVE.any? { |re| reference.to_s.match?(re) }
      errors.add(:reference, "looks like an SSN, EIN or email. Use a client reference, not identifying details")
    end
  end

  def playbook = Capture::Playbook.find(playbook_key)
  def applies?(situation_key) = answers[situation_key] == "yes" || answers[situation_key] == "unsure"

  # The route: the mainline in order, each step followed by the branches its "yes" situations add.
  def route
    sits = Situation.for_playbook(playbook_key).to_a.group_by(&:after_skill)
    playbook.mainline_names.flat_map do |name|
      [{ kind: "step", name: name, skill: Skill.current(name) }] +
        Array(sits[name]).select { |s| applies?(s.key) }.map do |s|
          { kind: "branch", name: s.branch_skill, skill: s.branch, situation: s, pending: !s.live? }
        end
    end
  end

  def progress
    steps = route.reject { |r| r[:pending] }
    [steps.count { |r| done.include?(r[:name]) }, steps.size]
  end
end
