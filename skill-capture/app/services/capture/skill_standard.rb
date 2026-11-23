module Capture
  # Anthropic's Agent Skills format for SKILL.md, enforced on every skill.
  #
  # Required (errors block publishing):
  #   name         1-64 chars; lowercase letters, digits and single hyphens; no "anthropic" or "claude"
  #   description  1-1024 chars; no XML tags
  #   body         Markdown instructions, not empty, no frontmatter of its own, under 500 lines
  #
  # Best practice (warnings shown to reviewers; drafts are formatted to meet them):
  #   description written in the third person and says both what the skill does and when to use it
  #   body opens with a "# Title", has "## When to use", "## Steps" (numbered), "## Outputs" and "## Checks"
  module SkillStandard
    module_function

    NAME_MAX = 64
    DESCRIPTION_MAX = 1024
    BODY_MAX_LINES = 500
    RESERVED = %w[anthropic claude].freeze
    NAME_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
    XML_TAG = %r{</?[A-Za-z][^>]*>}
    SECTIONS = ["When to use", "Inputs", "Steps", "Outputs", "Checks"].freeze

    Check = Struct.new(:rule, :ok, :level, :message, keyword_init: true)
    Report = Struct.new(:checks) do
      def errors = checks.select { |c| !c.ok && c.level == :error }
      def warnings = checks.select { |c| !c.ok && c.level == :warning }
      def ok? = errors.empty?
      def clean? = errors.empty? && warnings.empty?
    end

    def check(name:, description:, body:)
      name = name.to_s
      desc = description.to_s.strip
      body = body.to_s
      lines = body.lines.size
      checks = [
        Check.new(rule: "name", level: :error, ok: name.present? && name.length <= NAME_MAX && name.match?(NAME_FORMAT),
                  message: "Name: 1-#{NAME_MAX} lowercase letters, digits and single hyphens"),
        Check.new(rule: "name_reserved", level: :error, ok: RESERVED.none? { |w| name.downcase.include?(w) },
                  message: "Name can't contain the reserved words #{RESERVED.join(' or ')}"),
        Check.new(rule: "description", level: :error, ok: desc.present? && desc.length <= DESCRIPTION_MAX,
                  message: "Description: 1-#{DESCRIPTION_MAX} characters (now #{desc.length})"),
        Check.new(rule: "description_xml", level: :error, ok: !desc.match?(XML_TAG), message: "Description can't contain XML tags"),
        Check.new(rule: "body", level: :error, ok: body.strip.present?, message: "Instructions can't be empty"),
        Check.new(rule: "body_frontmatter", level: :error, ok: !body.lstrip.start_with?("---"),
                  message: "Instructions can't start with their own frontmatter (it's generated)"),
        Check.new(rule: "body_length", level: :error, ok: lines <= BODY_MAX_LINES,
                  message: "Instructions: under #{BODY_MAX_LINES} lines (now #{lines}); move detail to resources"),
        Check.new(rule: "third_person", level: :warning, ok: !desc.match?(/\A(I|I'm|We|We're|You|You're|My|Our|Your)\b/),
                  message: "Description in the third person (\"Reconciles…\", not \"I/You reconcile…\")"),
        Check.new(rule: "when_to_use", level: :warning, ok: desc.match?(/\b(use|used|when|whenever)\b/i),
                  message: "Description says when to use it (\"Use when…\")"),
        Check.new(rule: "title", level: :warning, ok: body.lstrip.start_with?("# "), message: "Instructions open with a \"# Title\""),
        *SECTIONS.map do |s|
          Check.new(rule: "section_#{s.parameterize(separator: '_')}", level: :warning, ok: body.match?(/^##\s+#{Regexp.escape(s)}\b/i),
                    message: "Has a \"## #{s}\" section")
        end,
        Check.new(rule: "numbered_steps", level: :warning, ok: body.match?(/^\s*1\.\s+\S/), message: "Steps are a numbered list")
      ]
      Report.new(checks)
    end

    def check_skill(s) = check(name: s.name, description: s.description, body: s.body)
    def check_candidate(c) = check(name: c.draft_name, description: c.draft_description, body: c.draft_body)

    # Brings a draft into the format without changing what it says.
    def normalize(attrs)
      a = attrs.dup
      title = a[:title].to_s.strip
      name = Naming.skill_name(a[:name].to_s)
      RESERVED.each { |w| name = name.gsub(/(\A|-)#{w}(-|\z)/) { $1.presence && $2.presence ? "-" : "" } }
      name = name.gsub(/-{2,}/, "-").delete_prefix("-").delete_suffix("-")
      a[:name] = name.presence || Naming.skill_name(title).presence || "workflow"

      desc = a[:description].to_s.gsub(XML_TAG, "").squish
      desc = desc.sub(/\A(You|We)\s+(\w)/) { $2.upcase } # "You reconcile…" → "Reconcile…"
      if desc.present? && !desc.match?(/\b(use|used|when|whenever)\b/i) && title.present?
        desc = "#{desc.sub(/[.\s]*\z/, '.')} Use when you need to #{title.sub(/\A./) { |c| c.downcase }.sub(/[.\s]*\z/, '')}."
      end
      a[:description] = truncate_sentence(desc, DESCRIPTION_MAX)

      body = a[:body].to_s.sub(/\A\s*---\s*\n.*?\n---\s*\n/m, "").strip
      body = "# #{title}\n\n#{body}" if title.present? && !body.start_with?("# ")
      a[:body] = body
      a
    end

    def truncate_sentence(text, max)
      return text if text.length <= max
      cut = text.first(max)
      (i = cut.rindex(/[.!?]\s/)) && i > max / 2 ? cut[0..i] : cut.first(max - 1) + "…"
    end
  end
end
