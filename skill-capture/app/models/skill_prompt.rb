# A nudge for one person: save a workflow they repeat, extend a skill they keep adding to,
# or branch a skill they keep doing their own way. Created by Capture::Prompter.
class SkillPrompt < ApplicationRecord
  KINDS = %w[save extend branch].freeze
  # evaluating: found by a trigger, being judged by the AI; filtered: the AI judged it not worth a skill
  STATUSES = %w[evaluating filtered open snoozed accepted dismissed].freeze

  belongs_to :user
  belongs_to :candidate, class_name: "SkillCandidate", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :fingerprint, presence: true, uniqueness: { scope: :user_id }

  scope :live, -> { where(status: "open").or(where(status: "snoozed").where("snoozed_until <= ?", Time.current)).order(occurrences: :desc, updated_at: :desc) }

  def skill = skill_name && Skill.current(skill_name)
  def step_labels = labels(steps)
  def added_labels = labels(Array(evidence["added"]))
  def removed_labels = labels(Array(evidence["removed"]))
  def labels(keys) = (known = ActionDefinition.labels_for(keys)) && keys.map { |k| known[k] }

  # The choices this prompt offers, best first.
  def choices
    case kind
    when "save" then %w[save]
    when "extend" then %w[extend branch]
    when "branch" then %w[branch extend]
    end
  end

  def ai = evidence["ai"] || {}

  def headline
    s = skill
    case kind
    when "save" then "You've done the same #{steps.size} steps #{occurrences} times. Save them as a skill?"
    when "extend" then "After “#{s&.title || skill_name}” you add #{added_labels.size == 1 ? "a step" : "#{added_labels.size} steps"} every time (#{occurrences}×). Extend the skill?"
    when "branch" then "You do “#{s&.title || skill_name}” your own way (#{occurrences}×). Branch it?"
    end
  end

  def to_api
    { id: id, kind: kind, headline: headline, skill: skill_name, skill_title: skill&.title, occurrences: occurrences,
      steps: steps.zip(step_labels).map { |k, l| { action: k, label: l } },
      added: added_labels, removed: removed_labels, choices: choices,
      suggested_title: ai["title"], suggested_description: ai["description"], why: ai["rationale"], evaluated_by: ai["by"] }
  end
end
