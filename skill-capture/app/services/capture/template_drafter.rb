module Capture
  # Deterministic drafter: used when no LLM is configured, and as the fallback
  # whenever the LLM call fails. Plain, but always valid.
  class TemplateDrafter
    def self.call(candidate) = new(candidate).call

    def initialize(candidate)
      @c = candidate
      @labels = candidate.step_labels
    end

    def call
      { name: name, title: title, description: description, tags: tags, inputs: [], outputs: [], body: body }
    end

    private

    def label(step) = @labels[step].to_s.sub(/[.\s]+\z/, "")
    def lower_first(s) = s.sub(/\A./) { |c| c.downcase }

    def title
      return @c.draft_title.strip if @c.origin == "manual" && @c.draft_title.present?
      steps = @c.steps
      text = if steps.size <= 3
        ([label(steps.first)] + steps.drop(1).map { |s| lower_first(label(s)) }).join(", then ")
      else
        "#{label(steps.first)} through #{lower_first(label(steps.last))}"
      end
      text.first(120)
    end

    def name
      n = Naming.skill_name(title)
      n.presence || "workflow-#{@c.id}"
    end

    def description
      return @c.draft_description if @c.origin == "manual" && @c.draft_description.present?
      area = @c.domain.present? ? " (#{@c.domain})" : ""
      "Performs a #{@c.steps.size}-step procedure#{area}: #{lower_first(title)}. Use when you need to do this task end to end; " \
        "captured from a workflow repeated #{@c.occurrence_count} times by #{@c.distinct_actor_count} " \
        "#{'person'.pluralize(@c.distinct_actor_count)}.".first(1024)
    end

    def tags
      ([@c.domain] + @c.steps.map { |s| s.split(/[.:#\/]/).first }).compact.map(&:parameterize).reject(&:blank?).uniq.first(6)
    end

    def body
      seen = [@c.first_seen_at, @c.last_seen_at].compact.map { |t| t.to_date.iso8601 }.uniq.join(" to ")
      lines = ["# #{title}", "", "## When to use", ""]
      if @c.origin == "manual"
        lines << (@c.draft_description.presence || "Use this procedure when you need to #{lower_first(title)}.")
        lines << "" << "Recorded by #{@c.contributor_names.to_sentence.presence || 'a colleague'}#{seen.present? ? " on #{seen}" : ''}."
      else
        times = @c.occurrence_count == 1 ? "once" : "#{@c.occurrence_count} times"
        lines << "Use this procedure when you need to #{lower_first(title)}. It was performed #{times} by " \
                 "#{@c.distinct_actor_count} #{'person'.pluralize(@c.distinct_actor_count)}" \
                 "#{seen.present? ? " (#{seen})" : ''} before being captured."
      end
      lines += ["", "## Inputs", "", "- The files and systems the steps below open. Confirm which ones with the person who requested this skill."]
      lines += ["", "## Steps", ""]
      @c.steps.each_with_index do |s, i|
        lines << "#{i + 1}. #{label(s)}.  "
        lines << "   _Action: `#{s}`_"
      end
      lines += ["", "## Outputs", "", "- The result of the last step: #{lower_first(label(@c.steps.last))}."]
      lines += ["", "## Checks", "",
                "- Confirm each step finished successfully before starting the next.",
                "- If a step fails, fix its input and repeat only that step.",
                "", "> Drafted automatically from observed activity. A reviewer should add inputs, outputs and any judgment calls."]
      lines.join("\n")
    end
  end
end
