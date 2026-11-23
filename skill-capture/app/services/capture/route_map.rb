module Capture
  # The road network of know-how, for the route map.
  #
  #   nodes  = published skills (paved roads) and open, unpublished workflows (unpaved)
  #   edges  = "next"   - people go from A to B (observed traffic and/or a reviewer's link)
  #            "branch" - B was forked from A (a variant road splitting off)
  # Improvements (new versions of the same skill) show as a count on the node.
  class RouteMap
    def self.call(user: nil) = new(user).call

    # user: limits unpublished workflows to the ones this person may see (policy scope).
    def initialize(user = nil)
      @user = user
    end

    def call
      skills = Skill.published.includes(:parent_skill).to_a
      versions = Skill.group(:name).count
      metrics = SkillMetric.where(name: skills.map(&:name)).index_by(&:name)
      bounties = Bounty.active.where(skill_name: skills.map(&:name)).index_by(&:skill_name)
      names = skills.map(&:name).to_set

      nodes = skills.map do |s|
        { id: s.name, title: s.title, area: s.domain, kind: "skill", version: s.version,
          improvements: versions[s.name].to_i - 1, steps: Array(s.source["workflow"]).size,
          apps: apps(Array(s.source["workflow"])), url: url_helpers.skill_path(s),
          contributors: Array(s.source["contributors"]).size }.merge(traffic(metrics[s.name], bounties[s.name]))
      end
      scope = @user ? SkillCandidatePolicy::Scope.new(@user, SkillCandidate).resolve : SkillCandidate
      candidates = scope.open.to_a
      nodes += candidates.map do |c|
        { id: SkillLink.candidate_key(c), title: c.display_title, area: c.domain, kind: "unpaved",
          status: c.status, steps: c.steps.size, apps: apps(c.steps), url: url_helpers.skill_candidate_path(c),
          contributors: c.distinct_actor_count }
      end
      ids = nodes.map { |n| n[:id] }.to_set

      edges = SkillLink.where(from_node: ids.to_a, to_node: ids.to_a).group(:from_node, :to_node)
                       .pluck(:from_node, :to_node, Arel.sql("SUM(traffic)"), Arel.sql("BOOL_OR(origin = 'manual')"))
                       .map { |a, b, t, m| { from: a, to: b, kind: "next", traffic: t.to_i, manual: m } }

      skills.each do |s|
        origin = s.lineage.drop(1).find { |anc| anc.name != s.name }
        next unless origin
        from = names.include?(origin.name) ? origin.name : nil
        edges << { from: from, to: s.name, kind: "branch", traffic: 0, manual: false } if from
      end

      { nodes: nodes, edges: edges, areas: nodes.map { |n| n[:area] }.compact.uniq.sort }
    end

    private

    def traffic(m, bounty)
      return {} unless m
      { tier: m.tier, index: m.congestion_index, price: m.price&.to_f, median_minutes: m.median_minutes,
        freeflow_minutes: m.freeflow_minutes, trips: m.trips, bounty: bounty && { status: bounty.status, pool: bounty.pool.to_f } }.compact
    end

    def apps(steps)
      steps.map { |k| SkillMap::APPS[k.to_s.split(/[.:]/).first] }.compact.uniq
    end

    def url_helpers = Rails.application.routes.url_helpers
  end
end
