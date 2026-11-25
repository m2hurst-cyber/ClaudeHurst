module Capture
  # The help centre, kept as files rather than rows: guides are Markdown with a little
  # frontmatter, the FAQ is one YAML file. Anyone who can edit a file can fix the help,
  # it reviews like code, and every page is already Markdown — so agents can read the
  # same text people do.
  module Help
    DIR = Rails.root.join("help")
    SECTIONS = {
      "start" => "Getting started",
      "how-to" => "How to",
      "concepts" => "How it works",
      "admin" => "Running it",
      "agents" => "Agents and integrations"
    }.freeze

    Guide = Struct.new(:slug, :title, :summary, :section, :order, :tags, :body, keyword_init: true) do
      def section_label = SECTIONS.fetch(section, section.to_s.humanize)
      def to_markdown = "# #{title}\n\n_#{summary}_\n\n#{body}"
      def haystack = [title, summary, tags.join(" "), body].join("\n").downcase
    end

    module_function

    def reload? = !Rails.env.production?

    def guides
      @guides = nil if reload? && stale?
      @guides ||= begin
        @loaded_at = Time.current
        Dir.glob(DIR.join("*.md")).sort.filter_map { |path| parse(Pathname(path)) }
           .sort_by { |g| [SECTIONS.keys.index(g.section) || 99, g.order, g.title] }
      end
    end

    def stale?
      return true if @loaded_at.nil?
      Dir.glob(DIR.join("*")).any? { |f| File.mtime(f) > @loaded_at }
    end

    def parse(path)
      raw = path.read
      front, body = raw.start_with?("---\n") ? raw.split(/^---\s*$/, 3).values_at(1, 2) : [nil, raw]
      meta = front ? (YAML.safe_load(front, permitted_classes: [Date]) || {}) : {}
      Guide.new(slug: path.basename(".md").to_s, title: meta["title"].to_s.presence || path.basename(".md").to_s.humanize,
                summary: meta["summary"].to_s, section: meta["section"].to_s.presence || "how-to",
                order: meta["order"].to_i, tags: Array(meta["tags"]).map(&:to_s), body: body.to_s.strip)
    rescue Psych::SyntaxError => e
      Rails.logger.warn("Help guide #{path.basename} has broken frontmatter: #{e.message}")
      nil
    end

    def find(slug) = guides.find { |g| g.slug == slug.to_s }

    def by_section = guides.group_by(&:section)

    # One question, one answer, and where to read more.
    Question = Struct.new(:question, :answer, :topic, :guide, keyword_init: true) do
      def haystack = [question, answer, topic].join("\n").downcase
    end

    def faq
      @faq = nil if reload? && stale?
      @faq ||= begin
        file = DIR.join("faq.yml")
        return [] unless file.exist?
        YAML.safe_load(file.read).flat_map do |topic, items|
          Array(items).map { |i| Question.new(question: i["q"], answer: i["a"], topic: topic, guide: i["guide"]) }
        end
      end
    end

    def topics = faq.group_by(&:topic)

    # One search box over both, because nobody knows whether their question is a FAQ or a guide.
    Hit = Struct.new(:kind, :title, :blurb, :slug, :score, keyword_init: true)

    # Words that appear in any paragraph of English and so cannot narrow anything.
    STOP = %w[the a an and or of to in on for with at by from is are was be been it its this that
              these those i you we they do does did how what when where why which who can could
              should would will my our your their there here about into over after before too
              many much some any all not no if then than as but].to_set.freeze

    def search(query)
      q = query.to_s.downcase.strip
      return [] if q.length < 2
      words = q.scan(/[\w-]+/).reject { |w| w.length < 3 || STOP.include?(w) }
      phrase = q.length >= 4
      # Help answers a question or it stays quiet. Half a sentence in common with a guide is
      # not an answer — the front door would fill with pages that merely share English.
      return [] if words.empty? && !phrase

      hits = guides.filter_map do |g|
        score = relevance(g.haystack, q, words, title: g.title.downcase)
        Hit.new(kind: "guide", title: g.title, blurb: g.summary, slug: g.slug, score: score) if score.positive?
      end
      hits += faq.filter_map do |f|
        score = relevance(f.haystack, q, words, title: f.question.downcase)
        Hit.new(kind: "question", title: f.question, blurb: f.answer.to_s.truncate(160), slug: f.guide, score: score) if score.positive?
      end
      hits.sort_by { |h| [-h.score, h.title] }
    end

    # Either the whole phrase appears, or every word that carries meaning does. Anything
    # looser answers questions it was not asked.
    def relevance(haystack, phrase, words, title:)
      whole = haystack.include?(phrase)
      return 0 unless whole || (words.any? && words.all? { |w| haystack.include?(w) })

      score = 0
      score += 100 if title.include?(phrase)
      score += 40 if whole
      score += 30 if words.any?
      # How much the page is *about* the word, not merely whether it mentions it once.
      # How much the page is *about* the word, not merely whether it mentions it once —
      # capped, so a long page cannot out-rank the page actually named for the subject.
      density = [words.sum { |w| [haystack.scan(w).size, 4].min }, 12].min
      score + (words.count { |w| title.include?(w) } * 25) + density
    end
  end
end
