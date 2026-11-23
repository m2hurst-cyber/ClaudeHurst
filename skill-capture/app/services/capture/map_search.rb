module Capture
  # Search across the route map: roads (skills), intersections and handoffs.
  # Matches titles and skill text, and full text of written directions.
  class MapSearch
    Hit = Struct.new(:key, :kind, :title, :subtitle, :written, :score, keyword_init: true) do
      def to_h = { key: key, kind: kind, label: Waypoint::KIND_LABELS[kind], title: title, subtitle: subtitle, written: written }
    end

    def self.call(q, limit: 20) = new(q).call(limit)

    def initialize(q)
      @q = q.to_s.strip
    end

    def call(limit)
      return [] if @q.length < 2
      hits = {}
      add = ->(h) { hits[h.key] = h if !hits[h.key] || hits[h.key].score < h.score }
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
      written = Waypoint.pluck(:key).to_set

      skills = Skill.published.where("title ILIKE :t OR name ILIKE :t OR description ILIKE :t OR :raw = ANY(tags)", t: term, raw: @q.downcase).to_a
      skills.each do |s|
        title_hit = s.title.downcase.include?(@q.downcase) ? 2 : 1
        add.(Hit.new(key: "road:#{s.name}", kind: "road", title: s.title, subtitle: area(s), written: written.include?("road:#{s.name}"), score: 10 * title_hit))
        if SkillLink.where(from_node: s.name).exists? || written.include?("junction:#{s.name}")
          add.(Hit.new(key: "junction:#{s.name}", kind: "junction", title: "Intersection after #{s.title}",
                       subtitle: exits_text(s.name), written: written.include?("junction:#{s.name}"), score: 6 * title_hit))
        end
        SkillLink.where("from_node = :n OR to_node = :n", n: s.name).distinct.pluck(:from_node, :to_node).each do |a, b|
          sa, sb = Skill.current(a), Skill.current(b)
          next unless sa && sb
          key = Waypoint.key_for("handoff", a, b)
          add.(Hit.new(key: key, kind: "handoff", title: "#{sa.title} → #{sb.title}", subtitle: "Handoff",
                       written: written.include?(key), score: 3))
        end
      end

      Waypoint.text_search(@q).or(Waypoint.where("title ILIKE ?", term)).limit(50).each do |wp|
        next unless live?(wp.key) # skip directions whose skill or road no longer exists
        add.(Hit.new(key: wp.key, kind: wp.kind, title: wp.title, subtitle: "Matches the directions", written: true, score: 12))
      end

      hits.values.sort_by { |h| [-h.score, h.title] }.first(limit)
    end

    private

    def live?(key)
      Directions.find(key)
      true
    rescue Directions::NotFound
      false
    end

    def area(s) = ["Road", s.domain&.then { |d| d.length <= 3 ? d.upcase : d.titleize }].compact.join(" · ")

    def exits_text(name)
      n = SkillLink.where(from_node: name).distinct.count(:to_node)
      "#{n} #{'exit'.pluralize(n)}"
    end
  end
end
