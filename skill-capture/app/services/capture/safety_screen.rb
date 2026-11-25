module Capture
  # Reads a skill the way an attacker would write one.
  #
  # A skill is text that an agent will follow. That makes the text itself the attack
  # surface: a sentence aimed at the agent rather than at the reader, a host to send
  # something to, a request for a credential. Published research finds roughly a quarter
  # of skills in public registries carry at least one such problem, and that a very short
  # insert is enough to change which skill a registry picks.
  #
  # So this does two things a reviewer cannot reliably do by eye:
  #
  #   1. Looks for text that addresses the agent, exfiltrates, escalates, or hides.
  #   2. Compares the body against what the skill *declared* it touches. The gap between
  #      what someone approved and what the skill actually does is the whole problem;
  #      a declaration makes that gap visible instead of implicit.
  #
  # Deterministic and cheap: it runs on every draft, every review and every promotion.
  # It is a floor, not a guarantee — a reviewer still reads the thing.
  class SafetyScreen
    Finding = Struct.new(:key, :severity, :label, :why, :evidence, keyword_init: true) do
      def blocking? = severity == :block
      def to_h = { "key" => key, "severity" => severity.to_s, "label" => label, "why" => why, "evidence" => evidence }
    end

    Report = Struct.new(:findings, :declared) do
      def blocking = findings.select(&:blocking?)
      def warnings = findings.reject(&:blocking?)
      def clean? = findings.empty?
      def safe_to_share? = blocking.empty?
      def summary
        return "Nothing of concern" if clean?
        [("#{blocking.size} blocking" if blocking.any?), ("#{warnings.size} to look at" if warnings.any?)].compact.join(", ")
      end
    end

    # Text that speaks to the agent rather than to the person following the procedure.
    # The giveaway is an instruction about instructions.
    AGENT_DIRECTED = {
      /ignore\s+(all\s+|any\s+)?(previous|prior|earlier|above)\s+(instruction|direction|prompt|rule)/i =>
        "tells the agent to ignore its instructions",
      /disregard\s+(the\s+)?(system|previous|prior|earlier|above)/i => "tells the agent to disregard what it was told",
      /\b(you\s+are\s+now|from\s+now\s+on\s+you|act\s+as\s+(an?\s+)?(unrestricted|different))/i =>
        "tries to change what the agent is",
      /\b(system\s+prompt|developer\s+message)\b/i => "refers to the agent's own instructions",
      /\b(do\s+not|don't|never)\s+(tell|inform|mention\s+to|show)\s+(the\s+)?(user|person|reviewer|anyone)/i =>
        "tells the agent to keep something from the person",
      /\bwithout\s+(asking|telling|informing|confirming\s+with)\s+(the\s+)?(user|anyone|them)/i =>
        "tells the agent to act without asking",
      /\b(regardless|irrespective)\s+of\s+(what|any)\s+(the\s+)?(user|instructions?|policy)/i =>
        "tells the agent to override what it is told",
      /\bbypass|\boverride\s+(the\s+)?(check|gate|review|approval|policy)/i => "asks for a control to be bypassed"
    }.freeze

    # Anything that moves data outward.
    EXFILTRATION = {
      /\b(send|e-?mail|post|upload|forward|share|transmit|exfiltrate)\b[^.\n]{0,40}\b(to|at)\b[^.\n]{0,40}(https?:\/\/|www\.|@)/i =>
        "sends something to an outside address",
      /\bcurl\b[^\n]*https?:\/\//i => "fetches or posts to a URL from the command line",
      /\b(webhook|pastebin|ngrok|requestbin|burpcollaborator)\b/i => "names a service used to collect data"
    }.freeze

    # Credentials and privilege.
    PRIVILEGE = {
      /\b(api[\s_-]?key|secret[\s_-]?key|access[\s_-]?token|bearer\s+token|client[\s_-]?secret)\b/i =>
        "asks for a credential",
      /\b(password|passphrase)\b[^.\n]{0,30}\b(enter|type|provide|paste|supply)\b/i => "asks someone to supply a password",
      /\b(sudo|chmod\s+777|disable\s+(the\s+)?(firewall|antivirus|protection))\b/i => "raises privilege or lowers a protection",
      /\b(ssn|social\s+security\s+number|tax\s*payer\s*id|\bein\b)\b/i => "handles a taxpayer identifier"
    }.freeze

    # Text a reader will not see but a model will.
    HIDDEN = {
      /[​-‏‪-‮⁠-⁤﻿]/ => "contains invisible or direction-changing characters",
      /<!--.*?-->/m => "hides text in an HTML comment"
    }.freeze

    URL = %r{https?://([a-z0-9.-]+)}i
    # Hosts a skill may legitimately name without declaring them.
    ALLOWED_HOSTS = %w[microsoft.com office.com sharepoint.com anthropic.com claude.com].freeze

    def self.call(skill_or_attrs) = new(skill_or_attrs).call

    # Takes a published skill, a candidate still in review, or a plain hash — the same
    # text is screened at every point it could be introduced.
    def initialize(subject)
      @body = read(subject, :body, :draft_body)
      @description = read(subject, :description, :draft_description)
      @declared = Capabilities.of(subject)
    end

    def read(subject, *names)
      names.each do |n|
        v = subject.is_a?(Hash) ? (subject[n] || subject[n.to_s]) : subject.try(n)
        return v.to_s if v.present?
      end
      ""
    end

    def call
      findings = []
      findings.concat(matches(AGENT_DIRECTED, :block, "Speaks to the agent"))
      findings.concat(matches(EXFILTRATION, :block, "Moves data outward"))
      findings.concat(matches(PRIVILEGE, :warn, "Credentials or privilege"))
      findings.concat(matches(HIDDEN, :block, "Hidden from the reader"))
      findings.concat(undeclared)
      Report.new(findings.uniq(&:key), @declared)
    end

    private

    def text = @text ||= "#{@description}\n#{@body}"

    def matches(rules, severity, label)
      rules.filter_map do |pattern, why|
        next unless (m = text.match(pattern))
        Finding.new(key: "#{label.parameterize}-#{why.parameterize.first(28)}", severity: severity,
                    label: label, why: why, evidence: excerpt(m))
      end
    end

    # The line the match sits on, so a reviewer reads a sentence rather than a fragment
    # that stops wherever the pattern happened to end.
    def excerpt(match)
      before = text[0...match.begin(0)].rpartition("\n").last
      after = text[match.end(0)..].to_s.partition("\n").first
      "#{before}#{match}#{after}".strip.squish.truncate(140).presence || match.to_s.inspect
    end

    # The consent gap, made visible: the body does something the skill never said it would.
    def undeclared
      out = []
      hosts = text.scan(URL).flatten.map(&:downcase).uniq
             .reject { |h| ALLOWED_HOSTS.any? { |a| h == a || h.end_with?(".#{a}") } }
      undeclared_hosts = hosts - Array(@declared["hosts"]).map(&:downcase)
      if undeclared_hosts.any?
        out << Finding.new(key: "undeclared-hosts", severity: :block, label: "Reaches somewhere it did not declare",
                           why: "names #{'a host'.pluralize(undeclared_hosts.size)} the skill does not list under what it reaches",
                           evidence: undeclared_hosts.first(3).join(", "))
      end
      if text.match?(/\b(e-?mail|send|notify|message)\b/i) && Array(@declared["sends"]).empty?
        out << Finding.new(key: "undeclared-sends", severity: :warn, label: "Sends without declaring it",
                           why: "the steps send something, but the skill lists nothing under what it sends",
                           evidence: text[/[^\n]*\b(e-?mail|send|notify|message)\b[^\n]*/i].to_s.squish.truncate(120))
      end
      if text.match?(/\b(api[\s_-]?key|token|credential|sign\s*in|log\s*in)\b/i) && !@declared["needs_credentials"]
        out << Finding.new(key: "undeclared-credentials", severity: :warn, label: "Needs a credential without declaring it",
                           why: "the steps involve signing in or a key, but the skill does not say it needs credentials",
                           evidence: text[/[^\n]*\b(api[\s_-]?key|token|credential|sign\s*in|log\s*in)\b[^\n]*/i].to_s.squish.truncate(120))
      end
      out
    end
  end
end
