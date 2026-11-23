module SkillCapture
  # Deterministic drafter used when no LLM is configured (and as the fallback
  # when the LLM call fails). Produces a usable, if plain, SKILL.md draft.
  class TemplateDrafter
    def self.call(candidate) = new(candidate).call

    def initialize(candidate)
      @c = candidate
    end

    def call
      {
        name: name,
        title: title,
        description: description,
        tags: tags,
        inputs: inputs,
        outputs: outputs,
        body: body
      }
    end

    private

    def short(step)
      controller, action = step.split("#", 2)
      "#{action.tr('_', ' ').sub(/\bit\z/, '').strip} #{controller.split('/').last.singularize.tr('_', ' ')}"
    end

    def resource(step)
      step.split("#").first.split("/").last.singularize.humanize
    end

    def title
      first, last = @c.steps.first, @c.steps.last
      ending = same_resource?(first, last) ? action(last) : short(last)
      "#{short(first).capitalize} through #{ending}"
    end

    def action(step)
      step.split("#", 2).last.tr("_", " ").sub(/\bit\z/, "").strip
    end

    def same_resource?(a, b)
      a.split("#").first == b.split("#").first
    end

    def name
      title.parameterize.first(64).sub(/-+\z/, "")
    end

    def description
      "Step-by-step procedure to #{short(@c.steps.first)} and carry it through to " \
        "#{same_resource?(@c.steps.first, @c.steps.last) ? action(@c.steps.last) : short(@c.steps.last)} " \
        "in the Great Southern Copacker CRM-ERP (#{@c.steps.size} steps, #{@c.domain} area). " \
        "Use when you need to #{title.downcase}; captured from a workflow staff repeated #{@c.occurrence_count} times."
    end

    def tags
      ([@c.domain] + @c.steps.map { |s| s.split("#").first.split("/").last.tr("_", "-") }).uniq
    end

    def inputs
      [resource(@c.steps.first)].uniq.map { |r| "Existing or new #{r.downcase} record" }
    end

    def outputs
      ["#{resource(@c.steps.last)} updated by: #{SkillCapture::Catalog.describe(@c.steps.last).downcase}"]
    end

    def body
      when_seen = [@c.first_seen_at, @c.last_seen_at].compact.map { |t| t.to_date.iso8601 }.uniq.join(" to ")
      lines = []
      lines << "# #{title}"
      lines << ""
      lines << "## When to use"
      lines << ""
      lines << "Use this procedure when you need to #{title.downcase}. It was performed " \
               "#{@c.occurrence_count} times by #{@c.distinct_user_count} #{'person'.pluralize(@c.distinct_user_count)}" \
               "#{when_seen.present? ? " (#{when_seen})" : ''} before being captured as a skill."
      lines << ""
      lines << "## Inputs"
      lines << ""
      inputs.each { |i| lines << "- #{i}" }
      lines << ""
      lines << "## Steps"
      lines << ""
      @c.steps.each_with_index do |s, i|
        lines << "#{i + 1}. #{SkillCapture::Catalog.describe(s)}  "
        lines << "   _App action: `#{s}`_"
      end
      lines << ""
      lines << "## Outputs"
      lines << ""
      outputs.each { |o| lines << "- #{o}" }
      lines << ""
      lines << "## Checks"
      lines << ""
      lines << "- Confirm each step shows a success notice before moving on."
      lines << "- If a step is rejected (validation or permission), fix the record and repeat that step only."
      lines.join("\n")
    end
  end
end
