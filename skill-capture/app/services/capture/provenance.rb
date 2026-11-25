module Capture
  # The provenance chain: append-only, hash-linked, periodically anchored.
  #
  #   entry_hash = SHA256(canonical({ sequence, prev, event, skill, version, content, actor, at, payload }))
  #
  # Each entry commits to the previous one's hash, so editing any historical row breaks
  # every hash after it and `verify` says where. A daily anchor publishes the Merkle root
  # of that day's entries together with the chain tip; put that root anywhere outside this
  # database — the mirror, a counterparty, a notary, a chain — and the history under it is
  # fixed. Nothing here needs a blockchain; a blockchain would only be another place to
  # put the root.
  module Provenance
    module_function

    # Appends one entry. Serialized with an advisory lock so two publishes cannot claim
    # the same sequence number or branch the chain.
    def append!(event:, skill: nil, actor: nil, content_hash: nil, occurred_at: nil, **payload)
      raise ArgumentError, "unknown provenance event #{event}" unless ProvenanceEntry::EVENTS.include?(event)

      ProvenanceEntry.transaction do
        ProvenanceEntry.connection.execute("SELECT pg_advisory_xact_lock(hashtext('provenance_chain'))")
        tip = ProvenanceEntry.order(sequence: :desc).first
        entry = ProvenanceEntry.new(
          sequence: (tip&.sequence || 0) + 1,
          prev_hash: tip&.entry_hash || ProvenanceEntry::GENESIS,
          event: event,
          skill_name: skill.respond_to?(:name) ? skill.name : skill.presence,
          skill_version: skill.respond_to?(:version) ? skill.version : nil,
          content_hash: content_hash || (skill.respond_to?(:content_hash) ? skill.content_hash : nil),
          actor_key: actor_key(actor),
          payload: Canonical.form(payload.deep_stringify_keys),
          occurred_at: occurred_at || Time.current,
          created_at: Time.current
        )
        entry.entry_hash = entry.computed_hash
        entry.save!
        entry
      end
    end

    def actor_key(actor)
      case actor
      when nil then "system"
      when User then "user:#{actor.id}"
      when Source then "source:#{actor.id}"
      when String then actor
      else "#{actor.class.name.underscore}:#{actor.try(:id)}"
      end
    end

    Verdict = Struct.new(:ok, :checked, :broken_at, :reason, keyword_init: true) do
      def to_s = ok ? "#{checked} entries, chain intact" : "broken at ##{broken_at}: #{reason}"
    end

    # Walks the whole chain (or from a sequence) recomputing every hash and every link.
    def verify(from: 1)
      prev = from <= 1 ? ProvenanceEntry::GENESIS : ProvenanceEntry.find_by(sequence: from - 1)&.entry_hash
      return Verdict.new(ok: false, checked: 0, broken_at: from - 1, reason: "no entry to start from") if prev.nil?

      checked = 0
      ProvenanceEntry.where("sequence >= ?", from).chronological.find_each do |e|
        return Verdict.new(ok: false, checked: checked, broken_at: e.sequence, reason: "link does not match the previous entry") unless e.prev_hash == prev
        return Verdict.new(ok: false, checked: checked, broken_at: e.sequence, reason: "contents do not match the stored hash") unless e.intact?
        prev = e.entry_hash
        checked += 1
      end
      Verdict.new(ok: true, checked: checked)
    end

    # Everything the chain says about one skill, oldest first.
    def history(skill_name) = ProvenanceEntry.for_skill(skill_name)

    def tip = ProvenanceEntry.order(sequence: :desc).first

    # Commits to every entry on a date. Idempotent: anchoring the same date twice is a no-op.
    def anchor!(on = Date.current)
      return ProvenanceAnchor.find_by(on_date: on) if ProvenanceAnchor.exists?(on_date: on)
      entries = ProvenanceEntry.where(occurred_at: on.all_day).chronological
      return nil if entries.empty?

      hashes = entries.pluck(:entry_hash)
      anchor = ProvenanceAnchor.create!(
        on_date: on, from_sequence: entries.first.sequence, to_sequence: entries.last.sequence,
        entry_count: hashes.size, root_hash: Canonical.merkle_root(hashes),
        tip_hash: tip.entry_hash, created_at: Time.current
      )
      mirror(anchor)
      append!(event: "anchor.published", on_date: on.iso8601, root: anchor.root_hash, entries: hashes.size)
      anchor
    end

    # The anchor is also written outside the database, so losing or rewriting the table
    # is not enough to rewrite history.
    def mirror(anchor)
      dir = Pathname(ENV.fetch("SKILL_CAPTURE_PROVENANCE_DIR", Rails.root.join("storage", "provenance", Rails.env).to_s))
      dir.mkpath
      dir.join("anchor-#{anchor.on_date.iso8601}.json").write(JSON.pretty_generate(anchor.to_h))
    rescue SystemCallError => e
      Rails.logger.warn("Provenance anchor mirror failed: #{e.class}: #{e.message}")
    end

    # What a counterparty receives: the skill's identity, its chain, and the anchors that
    # commit to it. Checkable with no access to this database.
    def manifest(skill)
      entries = history(skill.name)
      { "skill" => skill.name, "version" => skill.version, "content_hash" => skill.content_hash,
        "entries" => entries.map { |e| e.body.merge("hash" => e.entry_hash) },
        "anchors" => ProvenanceAnchor.where("to_sequence >= ?", entries.first&.sequence || 0).recent.map(&:to_h) }
    end
  end
end
