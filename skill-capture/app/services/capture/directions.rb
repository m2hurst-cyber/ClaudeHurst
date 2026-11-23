module Capture
  # Agent directions for places on the route map.
  #
  #   road:<skill>         how to drive this skill's road (tools, guardrails, done-when)
  #   junction:<skill>     the intersection at the end of the skill: which exit to take, and when
  #   handoff:<from>><to>  the connector road between two skills: what to pass on, who to notify
  #
  # Written directions (Waypoint) win. Anything not written yet gets a scaffold generated
  # from live data (exits and their traffic, prices, inputs and outputs), so agents always
  # get usable directions and people only have to add judgment.
  class Directions
    Place = Struct.new(:key, :kind, :from_name, :to_name, :title, :body, :written, :waypoint, :skill, :to_skill,
                       :version, :updated_at, :updated_by, keyword_init: true) do
      def label = Waypoint::KIND_LABELS[kind]
      def to_h
        { key: key, kind: kind, title: title, written: written, version: version, updated_at: updated_at&.iso8601,
          updated_by: updated_by&.name, skill: from_name, to_skill: to_name, markdown: body }.compact
      end
    end

    class NotFound < StandardError; end

    # viewer: a User (sees what they're allowed to), nil (agents: firm and market only),
    # or :system (internal jobs: everything).
    def self.find(key, viewer: :system) = new(viewer: viewer).find(key)

    def initialize(viewer: :system)
      @viewer = viewer
    end

    def visible?(skill) = @viewer == :system || skill.visible_to?(@viewer)

    # Turn-by-turn for a route of skill names: road, intersection, handoff, next road, ... arrive.
    def self.for_route(names, viewer: :system)
      keys = names.each_with_index.flat_map do |name, i|
        nxt = names[i + 1]
        nxt ? ["road:#{name}", "junction:#{name}", Waypoint.key_for("handoff", name, nxt)] : ["road:#{name}"]
      end
      keys.filter_map do |k|
        find(k, viewer: viewer)
      rescue NotFound
        nil
      end
    end

    def find(key)
      kind, from, to = Waypoint.parse_key(key) || raise(NotFound, "unknown place #{key.inspect}")
      skill = Skill.current(from)
      raise NotFound, "no published skill #{from.inspect}" unless skill && visible?(skill)
      to_skill = to && Skill.current(to)
      raise NotFound, "no published skill #{to.inspect}" if to && !(to_skill && visible?(to_skill))
      if kind == "handoff" && !SkillLink.exists?(from_node: from, to_node: to)
        raise NotFound, "no road from #{from} to #{to}"
      end
      wp = Waypoint.find_by(key: key)
      Place.new(key: key, kind: kind, from_name: from, to_name: to, skill: skill, to_skill: to_skill,
                title: wp&.title || default_title(kind, skill, to_skill),
                body: wp&.body || scaffold(kind, skill, to_skill), written: wp.present?, waypoint: wp,
                version: wp&.version, updated_at: wp&.updated_at, updated_by: wp&.updated_by)
    end

    # People who may write directions: reviewers for the area (either end, for a handoff) and admins.
    def self.editable_by?(user, place)
      return false unless user
      user.reviews?(place.skill.domain) || (place.to_skill && user.reviews?(place.to_skill.domain))
    end

    def self.save!(place, body:, title: nil, tags: [], note: nil, user:)
      raise ArgumentError, "Directions can't be empty" if body.to_s.strip.empty?
      RestStops.capture!(place.skill, reason: "before_update", user: user)
      wp = Waypoint.transaction do
        wp = place.waypoint || Waypoint.new(key: place.key, kind: place.kind, from_name: place.from_name, to_name: place.to_name, version: 0)
        wp.assign_attributes(title: title.presence || place.title, body: body.to_s, tags: Array(tags).map { |t| t.to_s.parameterize }.reject(&:blank?).uniq,
                             version: wp.version + 1, updated_by: user)
        wp.save!
        wp.revisions.create!(version: wp.version, body: wp.body, note: note.presence, editor: user)
        AuditLog.record("directions.saved", user: user, subject: wp, key: wp.key, version: wp.version)
        wp
      end
      RestStops.capture!(place.skill, reason: "directions", user: user)
      wp
    end

    def default_title(kind, skill, to_skill)
      case kind
      when "road" then "Road: #{skill.title}"
      when "junction" then "Intersection after #{skill.title}"
      when "handoff" then "Handoff: #{skill.title} → #{to_skill.title}"
      end
    end

    # ---------- scaffolds (generated, not saved) ----------

    def scaffold(kind, skill, to_skill)
      send(:"#{kind}_scaffold", skill, to_skill)
    end

    private

    def schedule = @schedule ||= PricingSchedule.current
    def metric(name) = SkillMetric.for(name)
    def labels(skill) = ActionDefinition.labels_for(Array(skill.source["workflow"]))

    def traffic_line(name)
      m = metric(name)
      return "Not enough traffic to price yet." unless m&.priced?
      tier = schedule.tier(m.tier)["label"]
      "#{tier} traffic: about #{fmt_minutes(m.median_minutes)} per trip (free-flow #{fmt_minutes(m.freeflow_minutes)}), " \
        "#{m.price.to_s('F')} #{schedule.currency} per trip."
    end

    def fmt_minutes(m)
      return "unknown" if m.nil?
      m < 90 ? "#{m.round} min" : (m < 2160 ? "#{(m / 60.0).round(1)} h" : "#{(m / 1440.0).round(1)} days")
    end

    def reviewers(domain)
      names = User.active.where(role: "reviewer").select { |u| u.domains.include?(domain) }.map(&:name)
      names.any? ? names.join(", ") : "an admin"
    end

    def road_scaffold(skill, _)
      steps = labels(skill)
      prev = SkillLink.neighbours(skill.name, direction: :previous).filter_map { |l| (s = Skill.current(l[:name])) && visible?(s) && s }
      bounty = Bounty.active_for(skill.name)
      <<~MD
        # Road: #{skill.title}

        Skill `#{skill.name}` v#{skill.version}#{" · area: #{skill.domain}" if skill.domain}. #{skill.description}

        ## Before you start
        #{(Array(skill.inputs).map { |i| "- Have: #{i}" } + prev.map { |p| "- Usually reached after: **#{p.title}** (`#{p.name}`)" }).presence&.join("\n") || "- Confirm you have what the first step needs."}

        ## Drive
        Follow the skill's steps in order (full procedure in its SKILL.md):
        #{steps.values.each_with_index.map { |l, i| "#{i + 1}. #{l}" }.join("\n")}

        ## Watch for
        - #{traffic_line(skill.name)}
        #{bounty ? "- This road is congested and has an open bounty (#{bounty.pool.to_s('F')} #{schedule.currency}). Note where you get held up." : "- No known hazards yet. Add guardrails, permissions and common mistakes here."}

        ## Done when
        #{Array(skill.outputs).map { |o| "- #{o}" }.presence&.join("\n") || "- Every step is complete and confirmed."}

        ## Then
        Continue at the intersection: **Intersection after #{skill.title}** (`junction:#{skill.name}`).
      MD
    end

    def junction_scaffold(skill, _)
      exits = SkillLink.neighbours(skill.name, direction: :next).filter_map { |l| (s = Skill.current(l[:name])) && visible?(s) && l.merge(skill: s) }
      branches = Skill.published.where(parent_skill_id: Skill.where(name: skill.name).select(:id)).where.not(name: skill.name).select { |b| visible?(b) }
      total = exits.sum { |e| e[:traffic] }
      lines = exits.each_with_index.map do |e, i|
        share = total.positive? && e[:traffic].positive? ? "#{(e[:traffic] * 100.0 / total).round}% of trips" : "linked by a reviewer"
        "#{i + 1}. **#{e[:skill].title}** (`#{e[:skill].name}`): #{share}. #{traffic_line(e[:skill].name)}"
      end
      <<~MD
        # Intersection after #{skill.title}

        You have finished `#{skill.name}`. Choose the next road.

        ## Exits
        #{lines.presence&.join("\n") || "No exits observed yet. This is the end of the known road."}
        #{branches.any? ? "\n## Variants of the road you just drove\n" + branches.map { |b| "- **#{b.title}** (`#{b.name}`): a branch of this skill; take it instead next time when it fits better." }.join("\n") + "\n" : ""}
        ## How to choose
        - Write the decision rule here, for example: "If the account holds foreign currency, take Reconcile a multi-currency bank account."
        #{exits.any? ? "- Default: take the most-travelled exit (**#{exits.first[:skill].title}**) unless a rule above applies." : ""}
        - Prefer free-flowing roads when two exits fit equally well.

        ## If no exit fits
        Stop and ask a reviewer for #{skill.domain || "this area"}: #{reviewers(skill.domain)}.
      MD
    end

    def handoff_scaffold(skill, to_skill)
      link = SkillLink.where(from_node: skill.name, to_node: to_skill.name)
      trips = link.sum(:traffic)
      m = metric(to_skill.name)
      <<~MD
        # Handoff: #{skill.title} → #{to_skill.title}

        The road from `#{skill.name}` to `#{to_skill.name}`. #{trips.positive? ? "Taken #{trips} times recently." : "Linked by a reviewer."}#{m&.median_wait_minutes ? " Typical wait before the next skill starts: #{fmt_minutes(m.median_wait_minutes)}." : ""}

        ## Hand over
        #{(Array(skill.outputs).map { |o| "- From #{skill.title}: #{o}" } + Array(to_skill.inputs).map { |i| "- #{to_skill.title} needs: #{i}" }).presence&.join("\n") || "- List what must be passed on (files, links, approvals)."}

        ## Notify
        - Who picks this up, and how (channel, queue, owner). Reviewers for #{to_skill.domain || "this area"}: #{reviewers(to_skill.domain)}.

        ## Watch for
        - #{traffic_line(to_skill.name)}
      MD
    end
  end
end
