module Capture
  # Rest stops: automatic, restorable snapshots of skills so any version or branch can be reverted.
  #
  # - capture!  snapshot a skill now (automatic ones are skipped when nothing changed since the last)
  # - revert!   publish a rest stop's content as the next version (history is never rewritten);
  #             the current state is saved first, so a revert can itself be reverted
  # - verify!   redundancy: every rest stop is mirrored to disk as JSON with its checksum;
  #             verify re-checks both copies and repairs whichever one is missing or damaged
  # - sweep!    daily: a rest stop for every published skill that changed (directions,
  #             resources and fields change without a new version)
  class RestStops
    class Error < StandardError; end

    REVERTABLE = %w[title description body tags inputs outputs].freeze

    class << self
      def snapshot(skill)
        c = skill.classification
        {
          "name" => skill.name, "version" => skill.version, "title" => skill.title, "description" => skill.description,
          "body" => skill.body, "tags" => skill.tags, "inputs" => skill.inputs, "outputs" => skill.outputs,
          "license" => skill.license, "domain" => skill.domain, "stage" => skill.stage,
          "workflow" => Array(skill.source["workflow"]),
          "parent" => skill.parent_skill && "#{skill.parent_skill.name}@#{skill.parent_skill.version}",
          "directions" => Waypoint.where(from_name: skill.name).order(:key).map { |w| { "key" => w.key, "title" => w.title, "body" => w.body, "tags" => w.tags } },
          "resources" => SkillResource.where(skill_name: skill.name).includes(resource: :folder).map { |sr| { "key" => sr.resource.key, "name" => sr.resource.name } }.sort_by { |r| r["key"] },
          "fields" => c&.field_paths || [], "apps" => c&.apps || []
        }
      end

      def capture!(skill, reason:, user: nil, label: nil, kind: "auto", pinned: false, snapshot: nil, as_name: nil)
        snap = snapshot || self.snapshot(skill)
        name = as_name || skill.name
        sum = RestStop.checksum_for(snap)
        latest = RestStop.where(skill_name: name).recent.first
        return latest if kind == "auto" && !pinned && latest&.checksum == sum

        stop = RestStop.create!(skill_name: name, skill_version: as_name ? skill.version : snap["version"], skill: as_name ? nil : skill,
                                kind: kind, reason: reason, label: label.presence&.squish&.first(120), snapshot: snap,
                                checksum: sum, pinned: pinned, created_by: user, created_at: Time.current)
        mirror!(stop)
        prune!(name)
        stop
      rescue => e
        raise if kind == "manual" || Rails.env.test?
        Rails.logger.error("Rest stop for #{skill&.name} (#{reason}) failed: #{e.class}: #{e.message}")
        nil
      end

      # A branch's first rest stop is its parent as it was: reverting to it undoes the branch's changes.
      def branch_point!(branch, parent, user: nil)
        snap = snapshot(parent).merge("name" => branch.name, "version" => branch.version, "branched_from" => "#{parent.name}@#{parent.version}")
        capture!(branch, reason: "branch_point", user: user, pinned: true, snapshot: snap, as_name: branch.name,
                 label: "Started from #{parent.title} v#{parent.version}")
      end

      def can_revert?(user, skill)
        return false unless user && skill
        SkillPolicy.new(user, skill).update? || (skill.stage == "local" && skill.published_by_id == user.id)
      end

      def can_capture?(user, skill) = user.present? && skill.present? && (can_revert?(user, skill) || SkillPolicy.new(user, skill).classify?)

      def revert!(stop, user:)
        skill = Skill.current(stop.skill_name) or raise Error, "#{stop.skill_name} has no published version to revert"
        raise Error, "You can't revert #{skill.title}" unless can_revert?(user, skill)
        raise Error, "This rest stop is damaged; run capture:rest_stops:verify to repair it from the mirror" unless stop.intact?

        snap = stop.snapshot
        capture!(skill, reason: "before_revert", user: user, pinned: true, label: "Before reverting to rest stop ##{stop.id}")
        attrs = REVERTABLE.to_h { |k| [k.to_sym, snap[k]] }.merge(
          workflow: snap["workflow"], authorized: true, restoring: true,
          change_note: "Reverted to rest stop ##{stop.id} (#{stop.reason_label.downcase}, v#{stop.skill_version}, #{stop.created_at.to_date})"
        )
        new_skill = Publisher.revise!(skill, editor: user, attrs: attrs)

        restored = restore_directions(stop, new_skill, user) + restore_resources(snap, new_skill, user)
        restore_fields(snap, new_skill, user)
        AuditLog.record("rest_stop.reverted", user: user, subject: new_skill, rest_stop: stop.id, from_version: skill.version, restored: restored)
        capture!(new_skill, reason: "reverted", user: user, label: "Reverted to rest stop ##{stop.id}")
        new_skill
      end

      def sweep!
        n = 0
        Skill.published.find_each { |s| n += 1 if capture!(s, reason: "daily")&.previously_new_record? }
        n
      end

      # Redundancy check. Returns counts; repairs unless repair: false.
      def verify!(repair: true)
        report = Hash.new(0)
        RestStop.find_each do |stop|
          report[:checked] += 1
          file = path_for(stop)
          mirror = (JSON.parse(file.read) rescue nil) if file.exist?
          mirror_ok = mirror && RestStop.checksum_for(mirror["snapshot"]) == mirror["checksum"] && mirror["checksum"] == stop.checksum
          if stop.intact?
            next if mirror_ok
            report[:mirror_repaired] += 1
            mirror!(stop) if repair
          elsif mirror_ok
            report[:restored_from_mirror] += 1
            stop.update_columns(snapshot: mirror["snapshot"]) if repair
          else
            report[:unrecoverable] += 1
          end
        end
        # Mirror files whose rest stop row is gone: bring the row back.
        Dir.glob(Config.rest_stop_dir.join("*", "rest-stop-*.json")).each do |f|
          data = JSON.parse(File.read(f)) rescue next
          next if RestStop.exists?(id: data["id"])
          next unless RestStop.checksum_for(data["snapshot"]) == data["checksum"]
          report[:rows_restored] += 1
          next unless repair
          RestStop.create!(id: data["id"], skill_name: data["skill_name"], skill_version: data["skill_version"],
                           skill: Skill.find_by(name: data["skill_name"], version: data["skill_version"]),
                           kind: data["kind"], reason: data["reason"], label: data["label"], pinned: data["pinned"],
                           snapshot: data["snapshot"], checksum: data["checksum"], created_by_id: User.exists?(data["created_by_id"]) ? data["created_by_id"] : nil,
                           created_at: data["created_at"])
        end
        report
      end

      def path_for(stop) = Config.rest_stop_dir.join(stop.skill_name, "rest-stop-#{stop.id}.json")

      def mirror!(stop)
        path = path_for(stop)
        FileUtils.mkdir_p(path.dirname)
        tmp = path.sub_ext(".json.tmp")
        tmp.write(JSON.pretty_generate(stop.attributes.slice("id", "skill_name", "skill_version", "kind", "reason", "label", "pinned", "checksum", "created_by_id")
                                         .merge("created_at" => stop.created_at.iso8601(6), "snapshot" => stop.snapshot)))
        File.rename(tmp, path) # atomic: a reader never sees half a file
      end

      private

      # Keep every manual, pinned and branch-point rest stop; keep the newest N automatic ones.
      def prune!(name)
        keep = Protocol.for("rest_stop")["keep_auto"]
        old = RestStop.where(skill_name: name, kind: "auto", pinned: false).recent.offset(keep)
        old.each { |s| FileUtils.rm_f(path_for(s)) }
        RestStop.where(id: old.map(&:id)).delete_all
      end

      def restore_directions(stop, skill, user)
        stop.directions.count do |d|
          wp = Waypoint.find_by(key: d["key"])
          next false if wp && wp.body == d["body"] && wp.title == d["title"]
          place = begin
            Directions.find(d["key"])
          rescue Directions::NotFound
            nil
          end
          next false unless place
          Directions.save!(place, body: d["body"], title: d["title"], tags: d["tags"], note: "Reverted to rest stop ##{stop.id}", user: user)
          true
        end
      end

      def restore_resources(snap, skill, user)
        want = Array(snap["resources"]).filter_map { |r| Resource.find_by_key(r["key"]) }
        have = SkillResource.where(skill_name: skill.name)
        removed = have.where.not(resource_id: want.map(&:id)).delete_all
        added = (want.map(&:id) - have.pluck(:resource_id)).count { |id| SkillResource.create!(skill_name: skill.name, resource_id: id, added_by: user) }
        removed + added
      end

      def restore_fields(snap, skill, user)
        c = SkillClassification.for(skill.name) || SkillClassification.new(skill_name: skill.name)
        fields = Field.where(path: snap["fields"]).index_by(&:path).values_at(*snap["fields"]).compact
        c.assign_attributes(apps: Array(snap["apps"]), source: "user", confirmed: true, updated_by: user)
        c.save! if c.new_record? || c.changed?
        c.set_fields!(fields, source: "user") if fields.any?
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("Rest stop: fields not restored for #{skill.name}: #{e.message}")
      end
    end
  end
end
