module Capture
  # Where the organization's know-how lives: one entry per area (domain), with
  # how far its workflows have got (detected → awaiting review → published),
  # who reviews it, who contributed, and which Office apps the work happens in.
  class SkillMap
    UNASSIGNED = "unassigned".freeze
    STAGES = %w[published awaiting_review detected].freeze
    APPS = { "excel" => "Excel", "word" => "Word", "powerpoint" => "PowerPoint" }.freeze

    Area = Struct.new(:name, :published, :awaiting_review, :detected, :reviewers, :contributors,
                      :apps, :top_skills, keyword_init: true) do
      def total = published + awaiting_review + detected
      def unassigned? = name == UNASSIGNED
      def no_reviewer? = reviewers.empty?
      def uncaptured? = published.zero? && (awaiting_review + detected).positive?
      def gaps
        g = []
        g << "No reviewer for this area" if no_reviewer? && !unassigned?
        g << "Repeated work, nothing published yet" if uncaptured?
        g << "Needs an area so the right reviewer sees it" if unassigned? && total.positive?
        g
      end
    end

    def self.call(user: nil) = new(user).call

    def initialize(user = nil)
      @user = user
    end

    def call
      skills = (@user ? Skill.published.visible_to(@user) : Skill.published)
               .select(:id, :name, :title, :domain, :source, :published_at, :stage).to_a
      candidates = SkillCandidate.open.select(:id, :domain, :status, :steps, :contributors).to_a
      reviewers = User.active.where(role: "reviewer").pluck(:name, :domains)

      names = (skills.map(&:domain) + candidates.map(&:domain)).map { |d| d.presence || UNASSIGNED } +
              reviewers.flat_map(&:last)
      areas = names.uniq.map do |name|
        in_area = ->(d) { (d.presence || UNASSIGNED) == name }
        s = skills.select { |x| in_area.(x.domain) }
        c = candidates.select { |x| in_area.(x.domain) }
        steps = s.flat_map { |x| Array(x.source["workflow"]) } + c.flat_map(&:steps)
        Area.new(
          name: name,
          published: s.size,
          awaiting_review: c.count { |x| x.status == "drafted" },
          detected: c.count { |x| x.status == "detected" },
          reviewers: reviewers.select { |_, ds| ds.include?(name) }.map(&:first).sort,
          contributors: (s.flat_map { |x| Array(x.source["contributors"]) } +
                         c.flat_map { |x| x.contributors.map { |k| k["name"].presence || k["key"] } }).uniq.size,
          apps: steps.map { |k| APPS[k.to_s.split(/[.:]/).first] }.compact.tally.sort_by { |_, n| -n }.to_h,
          top_skills: s.sort_by { |x| x.published_at || Time.at(0) }.reverse.first(3).map { |x| { id: x.id, title: x.title } }
        )
      end
      areas.sort_by { |a| [a.unassigned? ? 1 : 0, -a.total, a.name] }
    end
  end
end
