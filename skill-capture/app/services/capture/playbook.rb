module Capture
  # A playbook: a curated, linear workflow kept as files (playbooks/<key>/playbook.yml plus one
  # Agent Skills SKILL.md per skill and its resource files) and installed as published skills.
  #
  # Installing creates or updates, idempotently:
  #   - the fields it declares, and the resource folder and files (a changed file is a new version)
  #   - one skill per mainline step, linked in order by roads
  #   - one branch skill per situation, a variant of the step it leaves after, rejoining at the next
  #   - each skill's fields, apps and resources, and intersection directions that say which
  #     situations branch off where
  #   - the situations themselves (the intake questions)
  # A skill whose file changed is revised (a new version; rest stops keep the old one). Skills are
  # never deleted by an install. Installing is an admin action and counts as the approval to
  # publish at the playbook's stage.
  class Playbook
    class Error < StandardError; end
    Report = Struct.new(:created, :updated, :unchanged, :resources, :situations, :commands, keyword_init: true)
    APPS = { "excel" => "Excel", "word" => "Word", "powerpoint" => "PowerPoint", "outlook" => "Outlook" }.freeze

    attr_reader :key, :dir, :data

    def self.root = Pathname(ENV.fetch("SKILL_CAPTURE_PLAYBOOK_DIR", Rails.root.join("playbooks").to_s))
    def self.all = Dir.glob(root.join("*", "playbook.yml")).sort.map { |f| new(Pathname(f).dirname) }
    def self.find(key)
      raise Error, "unknown playbook #{key}" unless key.to_s.match?(/\A[a-z0-9-]+\z/) && root.join(key.to_s, "playbook.yml").exist?
      new(root.join(key.to_s))
    end

    def initialize(dir)
      @dir = Pathname(dir)
      @data = YAML.safe_load(@dir.join("playbook.yml").read)
      @key = @data.fetch("key")
    end

    def title = data["title"]
    def description = data["description"]
    def disclaimer = data["disclaimer"]
    def area = data["area"]
    def version = data["version"].to_i
    def mainline = data["mainline"] || []
    def mainline_names = mainline.map { |m| m["name"] }
    def pack? = data["kind"] == "pack"
    def provider = data["provider"]
    def runnable? = mainline.any? # returns are worked through a mainline; packs are libraries of routes
    # Named routes; a playbook with a mainline has one.
    def routes = data["routes"] || { "main" => { "title" => title, "steps" => mainline } }
    def commands_spec = @commands_spec ||= (f = dir.join("commands.yml")).exist? ? YAML.safe_load(f.read).fetch("commands", {}) : {}
    def situation_specs = Array(data["situations"])
    def to_param = key

    # Every skill (mainline and branches) with its file content.
    def skills
      @skills ||= (routes.values.flat_map { |r| Array(r["steps"]) }.map { |m| m.merge("kind" => "step") } +
                   situation_specs.map { |s| s.merge("name" => s["branch"], "kind" => "branch") }).map do |spec|
        file = dir.join("skills", "#{spec['name']}.md")
        front, body = if file.exist? then parse(file.read)
                      elsif spec["worksheet"] then generated_skill(spec)
                      else raise Error, "#{key}: missing skills/#{spec['name']}.md"
                      end
        spec.merge("title" => front.dig("metadata", "title") || front["name"], "description" => front["description"].to_s.squish,
                   "body" => body, "front_name" => front["name"], "workflow" => workflow(spec["steps"]))
      end
    end

    def skill_spec(name) = skills.find { |s| s["name"] == name }

    # Worksheet skills without a hand-written SKILL.md get one written from their blueprint.
    def generated_skill(spec)
      bp = spec["worksheet"]
      route = routes.find { |_, r| Array(r["steps"]).any? { |s| s["name"] == spec["name"] } }
      steps_in_route = route ? Array(route[1]["steps"]) : []
      i = steps_in_route.index { |s| s["name"] == spec["name"] }.to_i
      before = i.positive? ? steps_in_route[i - 1] : nil
      prov = FormulaCommand.provider_name(provider)
      inputs = Array(bp["inputs"]).map { |x| "- #{x['label'] || x['key'].humanize}#{x['default'].present? ? " (default: #{x['default'].to_s.lines.first.strip}#{x['default'].to_s.lines.size > 1 ? ', …' : ''})" : ''}" }
      inputs << "- The “#{skill_spec_title(bp['source'])}” sheet, built first" if bp["source"]
      cmds = Worksheets.command_keys(bp).map { |k| "`#{k}`" }
      body = <<~MD.strip
        # #{spec['title']}

        ## When to use

        #{spec['description']}#{route ? " Part of the #{route[1]['title']} route#{before ? ", after “#{before['title']}”" : ''}." : ''}

        ## Inputs

        #{inputs.any? ? inputs.join("
") : "- None beyond the source sheet"}

        ## Steps

        #{Array(spec['steps']).each_with_index.map { |(_, label), n| "#{n + 1}. #{label}." }.join("
")}

        To build it: in Excel, open the Skill Capture tab, find this skill and choose **Build worksheet**, fill in the inputs and build. The sheet holds live #{prov} formulas, which calculate in your #{prov} session.

        ## Outputs

        #{Worksheets.outline(bp).map { |l| "- #{l}" }.join("
")}

        ## Checks

        #{(Array(spec['notes']) + ["Commands used: #{cmds.join(', ').presence || 'none'}. Any marked unverified in the command library need checking against #{prov} documentation before the sheet is relied on."]).map { |n| "- #{n}" }.join("
")}
      MD
      [{ "name" => spec["name"], "description" => spec["description"], "metadata" => { "title" => spec["title"] } }, body]
    end

    def skill_spec_title(name) = name && (routes.values.flat_map { |r| Array(r["steps"]) }.find { |s| s["name"] == name }&.dig("title") || name)

    # Document catalog (documents.yml) and leg specifications (legs.yml), when the playbook has them.
    def catalog = @catalog ||= (f = dir.join("documents.yml")).exist? ? YAML.safe_load(f.read).fetch("kinds") : {}
    def leg_specs = @leg_specs ||= (f = dir.join("legs.yml")).exist? ? YAML.safe_load(f.read) : {}
    def leg_spec(name) = leg_specs.dig("legs", name) || { "checks" => [{ "type" => "attest", "key" => "done", "text" => "I completed this step following its instructions" }] }
    def situation_documents(key) = Array(situation_specs.find { |s| s["key"] == key }&.dig("documents"))
    def prepares_legs? = catalog.any?

    # Problems that would stop an install.
    def problems
      out = []
      skills.each do |s|
        out << "#{s['name']}: frontmatter name is #{s['front_name'].inspect}" if s["front_name"] != s["name"]
        r = SkillStandard.check(name: s["name"], description: s["description"], body: s["body"])
        out += r.errors.map { |e| "#{s['name']}: #{e.message}" }
        out << "#{s['name']}: needs at least 2 steps" if s["workflow"].size < 2
      end
      situation_specs.each { |s| out << "situation #{s['key']}: unknown step #{s['after']}" unless mainline_names.include?(s["after"]) }
      declared = Array(data["fields"]).map { |f| f["path"] }
      Array(data["fields"]).each do |f|
        out << "field #{f['path']}: the last part must be #{f['name'].parameterize.inspect} (paths come from names)" unless f["path"].split("/").last == f["name"].to_s.parameterize
      end
      skills.flat_map { |s| Array(s["fields"]) }.uniq.each { |p| out << "unknown field #{p}" unless declared.include?(p) || Field.exists?(path: p) }
      Array(data.dig("resources", "items")).each { |r| out << "resource #{r['file']} missing" unless dir.join("resources", r["file"]).exist? }
      out += leg_problems if prepares_legs?
      if pack?
        known = commands_spec.keys.map(&:to_s) | FormulaCommand.where(provider: provider).pluck(:key)
        by_name = skills.to_h { |s| [s["name"], s["worksheet"]] }
        skills.each { |s| Worksheets.problems(s["worksheet"], commands: known, skills: by_name).each { |e| out << "#{s['name']}: #{e}" } if s["worksheet"] }
        commands_spec.each do |k, c|
          out << "command #{k}: syntax must start with =" unless c["syntax"].to_s.start_with?("=")
          out << "command #{k}: unbalanced quotes" if c["syntax"].to_s.count('"').odd?
        end
      end
      out
    end

    def leg_problems
      out = []
      totals = leg_specs.fetch("totals", {})
      inputs = leg_specs.fetch("inputs", {})
      ref_ok = lambda do |ref|
        next true if ref.is_a?(Numeric)
        ns, key = ref.split(".", 2)
        case ns
        when "input" then inputs.key?(key)
        when "totals" then totals.key?(key)
        else catalog.dig(ns, "fields")&.any? { |f| f["key"] == key }
        end
      end
      totals.each do |name, expr|
        refs = expr.is_a?(Array) ? expr : Formula.refs(expr)
        refs.each { |r| out << "total #{name}: unknown #{r}" unless ref_ok.(r) }
      end
      leg_specs.fetch("legs", {}).each do |leg, spec|
        out << "legs: #{leg} isn't a skill in this playbook" unless skill_spec(leg)
        Array(spec["documents"]).each { |k| out << "#{leg}: unknown document #{k}" unless catalog.key?(k) }
        Array(spec["inputs"]).each { |k| out << "#{leg}: unknown input #{k}" unless inputs.key?(k) }
        Array(spec["show"]).each { |k| out << "#{leg}: unknown total #{k}" unless totals.key?(k) }
        Array(spec["checks"]).each do |c|
          [c["left"], c["right"]].compact.each { |r| out << "#{leg}: unknown #{r}" unless ref_ok.(r) }
          out << "#{leg}: unknown document #{c['kind']}" if c["kind"] && !catalog.key?(c["kind"])
        end
      end
      situation_specs.each { |s| Array(s["documents"]).each { |k| out << "situation #{s['key']}: unknown document #{k}" unless catalog.key?(k) } }
      out
    end

    # :missing, :current or :changed for each skill.
    def status
      skills.to_h do |s|
        current = Skill.current(s["name"])
        [s["name"], current.nil? ? :missing : (same?(current, s) ? :current : :changed)]
      end
    end

    def installed? = status.values.none?(:missing)

    def install!(user:)
      raise Error, "Only admins install playbooks" unless user&.admin?
      issues = problems
      raise Error, "#{title} can't be installed: #{issues.join('; ')}" if issues.any?

      report = Report.new(created: [], updated: [], unchanged: [], resources: 0, situations: 0)
      ensure_fields!(user)
      report.commands = install_commands!(user) if pack?
      resources = install_resources!(user, report)
      skills.each do |s|
        current = Skill.current(s["name"])
        skill = if current.nil?
          report.created << s["name"]
          publish_new!(s, user)
        elsif !same?(current, s)
          report.updated << s["name"]
          Publisher.revise!(current, editor: user, attrs: { title: s["title"], description: s["description"], body: s["body"],
                                                            workflow: s["workflow"], source_extra: { "worksheet" => s["worksheet"] }.compact,
                                                            change_note: "Updated from the #{title} playbook (v#{version})" })
        else
          report.unchanged << s["name"]
          current
        end
        classify!(skill, s, user)
        Array(s["resources"]).each { |n| SkillResource.find_or_create_by!(skill_name: skill.name, resource: resources.fetch(n)) { |sr| sr.added_by = user } }
      end
      link!(user)
      report.situations = upsert_situations!
      Playbook.all.each { |pb| pb.connect_handoffs!(user) } # roads between playbooks, whichever was installed first
      refresh_junctions!(user)
      AuditLog.record("playbook.installed", user: user, playbook: key, version: version,
                      created: report.created, updated: report.updated, resources: report.resources)
      report
    end

    # Roads from this playbook's skills into another playbook's, with written handoff directions.
    # Connected once both ends are installed.
    def connect_handoffs!(user)
      Array(data["handoffs"]).each do |h|
        next unless Skill.current(h["from"]) && Skill.current(h["to"])
        SkillLink.find_or_create_by!(from_node: h["from"], to_node: h["to"], origin: "manual") { |l| l.created_by = user }
        key = Waypoint.key_for("handoff", h["from"], h["to"])
        body = h["directions"].to_s.strip
        next if body.empty? || Waypoint.find_by(key: key)&.body == body
        Directions.save!(Directions.find(key), body: body, note: "#{title} playbook v#{version}", user: user)
      end
    end

    # Each mainline intersection says where the road goes next and which situations branch off.
    def refresh_junctions!(user)
      return refresh_route_junctions!(user) if pack?
      names = mainline_names
      names.each_with_index do |name, i|
        skill = Skill.current(name) or next
        nxt = names[i + 1] && Skill.current(names[i + 1])
        sits = Situation.for_playbook(key).where(after_skill: name).to_a
        lines = ["# Intersection after #{skill.title}", "",
                 nxt ? "Mainline: continue to **#{nxt.title}** (`road:#{nxt.name}`)." : "End of the #{title} route.", ""]
        if sits.any?
          lines += ["## Situations that branch here", ""]
          sits.each do |s|
            b = s.branch
            lines << "- **#{s.question}** Take **#{b&.title || 'a branch still in review'}**#{b ? " (`road:#{b.name}`)" : ''}" \
                     "#{s.forms.any? ? ", forms: #{s.forms.join(', ')}" : ''}, then #{nxt ? "rejoin at #{nxt.title}" : 'finish'}."
          end
          lines << ""
        end
        outs = Array(data["handoffs"]).select { |h| h["from"] == name }.filter_map { |h| (t = Skill.current(h["to"])) && [h, t] }
        if outs.any?
          lines += ["## Hands off to another road", ""]
          outs.each { |h, t| lines << "- **#{t.title}** (`road:#{t.name}`) in the #{h['playbook'].to_s.tr('-', ' ')} playbook. See the handoff directions (`handoff:#{name}>#{t.name}`)." }
          lines << ""
        end
        lines << "> #{disclaimer}" if disclaimer
        body = lines.join("\n")
        next if Waypoint.find_by(key: "junction:#{name}")&.body == body
        Directions.save!(Directions.find("junction:#{name}"), body: body, note: "#{title} playbook v#{version}", user: user)
      end
    end

    # A pack's intersections: where each route goes next.
    def refresh_route_junctions!(user)
      routes.each_value do |r|
        names = Array(r["steps"]).map { |x| x["name"] }
        names.each_with_index do |name, i|
          skill = Skill.current(name) or next
          nxt = names[i + 1] && Skill.current(names[i + 1])
          body = ["# Intersection after #{skill.title}", "",
                  nxt ? "#{r['title']} route: continue to **#{nxt.title}** (`road:#{nxt.name}`), which reads this sheet." : "End of the #{r['title']} route.",
                  "", "> #{disclaimer}"].join("\n")
          next if Waypoint.find_by(key: "junction:#{name}")&.body == body
          Directions.save!(Directions.find("junction:#{name}"), body: body, note: "#{title} v#{version}", user: user)
        end
      end
    end

    # Installs the pack's command library. A command first installed from the pack is updated from it;
    # a changed formula goes back to unverified. Commands added in the console or by import are left alone.
    def install_commands!(user)
      commands_spec.count do |k, c|
        cmd = FormulaCommand.find_or_initialize_by(provider: provider, key: k.to_s)
        next false if cmd.persisted? && cmd.origin != "pack"
        changed_syntax = cmd.persisted? && (cmd.syntax != c["syntax"] || cmd.defaults != (c["defaults"] || {}))
        cmd.assign_attributes(name: c["name"], category: c["category"] || "Other", syntax: c["syntax"], defaults: c["defaults"] || {},
                              description: c["description"], origin: "pack", created_by: cmd.created_by || user)
        cmd.assign_attributes(status: "unverified", verified_by: nil, verified_at: nil) if changed_syntax
        next false unless cmd.new_record? || cmd.changed?
        cmd.save!
        true
      end
    end

    private

    def parse(text)
      m = text.match(/\A---\s*\n(.*?)\n---\s*\n(.*)\z/m) or raise Error, "#{key}: a skill file has no frontmatter"
      [YAML.safe_load(m[1]) || {}, m[2].strip]
    end

    def workflow(steps) = Array(steps).map { |app, label| "#{app}.step:#{label.parameterize}" }
    def labels(steps) = Array(steps).map { |app, label| ["#{app}.step:#{label.parameterize}", label] }

    def same?(skill, s)
      skill.title == s["title"] && skill.description == s["description"] && skill.body.strip == s["body"] &&
        Array(skill.source["workflow"]) == s["workflow"] && skill.source["worksheet"] == s["worksheet"]
    end

    def ensure_fields!(user)
      Array(data["fields"]).each do |f|
        next if Field.exists?(path: f["path"])
        parent = f["path"].include?("/") ? Field.find_by!(path: f["path"].rpartition("/").first) : nil
        Field.create!(name: f["name"], parent: parent, keywords: Array(f["keywords"]), created_by: user)
      end
    end

    def install_resources!(user, report)
      spec = data["resources"] or return {}
      folder = nil
      spec["folder"].split("/").each do |name|
        folder = ResourceFolder.find_or_create_by!(path: [folder&.path, name.parameterize].compact.join("/")) do |f|
          f.assign_attributes(name: name, parent: folder, audience: "firm", created_by: user)
        end
      end
      spec["items"].to_h do |item|
        path = dir.join("resources", item["file"])
        bytes = path.binread
        r = folder.resources.find_or_initialize_by(slug: item["name"].parameterize)
        if r.new_record? || r.checksum != Digest::SHA256.hexdigest(bytes)
          r.version = r.new_record? ? 1 : r.version + 1
          r.assign_attributes(name: item["name"], description: item["description"], uploaded_by: user)
          r.attach_file(StringIO.new(bytes), filename: item["file"], content_type: Rack::Mime.mime_type(File.extname(item["file"])))
          r.save!
          report.resources += 1
        end
        [item["name"], r]
      end
    end

    def publish_new!(s, user)
      labels(s["steps"]).each { |k, l| ActionDefinition.find_or_create_by!(key: k) { |d| d.label = l; d.domain = area } }
      base = s["kind"] == "branch" ? Skill.current(s["after"]) : nil
      c = SkillCandidate.find_or_initialize_by(signature: "playbook:#{key}:#{s['name']}")
      c.assign_attributes(steps: s["workflow"], domain: area, origin: "manual", status: "drafted",
                          draft_name: s["name"], draft_title: s["title"], draft_description: s["description"], draft_body: s["body"],
                          draft_tags: [area, key].compact, draft_generator: "playbook", drafted_at: Time.current,
                          proposal_kind: base ? "branch" : nil, base_skill: base, requested_by: user,
                          occurrence_count: 0, distinct_actor_count: 0, contributors: [],
                          review_notes: "Installed from the #{title} playbook (v#{version}).")
      c.save!
      skill = Publisher.publish!(c, reviewer: user, source_extra: { "playbook" => key, "worksheet" => s["worksheet"] }.compact)
      stage = data["stage"].presence
      skill.update!(stage: stage, stage_changed_at: Time.current) if stage && Skill::STAGES.include?(stage) && skill.stage != stage
      skill
    end

    def classify!(skill, s, user)
      c = SkillClassification.find_or_initialize_by(skill_name: skill.name)
      c.assign_attributes(apps: Array(s["steps"]).map { |app, _| APPS[app] }.compact.uniq, source: "user", confirmed: true, updated_by: user)
      c.save!
      paths = Array(s["fields"])
      fields = Field.where(path: paths).index_by(&:path).values_at(*paths).compact # in the playbook's order: the first is primary
      c.set_fields!(fields, source: "user") if fields.any?
    end

    def link!(user)
      names = mainline_names
      pairs = routes.values.flat_map { |r| Array(r["steps"]).map { |x| x["name"] }.each_cons(2).to_a }
      situation_specs.each do |s|
        nxt = names[names.index(s["after"]) + 1]
        pairs << [s["branch"], nxt] if nxt # the branch rejoins the mainline at the next step
      end
      pairs.each { |a, b| SkillLink.find_or_create_by!(from_node: a, to_node: b, origin: "manual") { |l| l.created_by = user } }
    end

    def upsert_situations!
      situation_specs.each_with_index do |s, i|
        sit = Situation.find_or_initialize_by(playbook_key: key, key: s["key"])
        sit.update!(question: s["question"], after_skill: s["after"], branch_skill: s["branch"], forms: Array(s["forms"]),
                    keywords: Array(s["keywords"]), position: i, status: "active")
      end
      situation_specs.size
    end
  end
end
