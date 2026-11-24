module Capture
  # Preparing and verifying each leg of a return's road.
  #
  # prepare!  computes the leg's figures from the confirmed documents and the filer's inputs,
  #           then has the AI preparer (Claude, or rules) write the workpaper memo and list issues
  #           against the skill's own instructions; then verifies.
  # verify!   runs the leg's checks (legs.yml). The leg is verified only when every check passes:
  #           documents in and confirmed, figures that tie, inputs entered, attestations given,
  #           AI issues resolved, and for review, a second person's sign-off.
  # Anything that changes the return (a document, an input, an answer) re-verifies every leg,
  # so a verified leg can't silently go stale.
  class Legs
    Check = Struct.new(:id, :label, :ok, :detail, keyword_init: true)

    def initialize(run)
      @run = run
      @pb = run.playbook
      @spec = @pb.leg_specs
      @memo = {}
    end

    def catalog = @pb.catalog
    def spec(leg) = @pb.leg_spec(leg)
    def docs = @docs ||= @run.documents.confirmed.to_a
    def docs_for(leg) = @run.documents.ordered.select { |d| Array(spec(leg)["documents"]).map(&:to_s).include?(d.kind.to_s) }

    # A figure: kind.field (summed over confirmed documents), input.key or totals.key.
    def resolve(ref)
      ns, key = ref.split(".", 2)
      case ns
      when "input" then @run.inputs[key].to_s.delete(",$").to_f
      when "totals" then total(key)
      else docs.select { |d| d.kind == ns }.sum { |d| d.fields[key].to_f }
      end
    end

    def total(key, stack = [])
      return @memo[key] if @memo.key?(key)
      raise Formula::Error, "circular total #{key}" if stack.include?(key)
      expr = @spec.fetch("totals", {}).fetch(key) { raise Formula::Error, "unknown total #{key}" }
      @memo[key] = if expr.is_a?(Array)
        expr.sum { |r| resolve(r) }.round(2)
      else
        Formula.new(expr) { |r| r.start_with?("totals.") ? total(r.delete_prefix("totals."), stack + [key]) : resolve(r) }.value.round(2)
      end
    end

    def shown(leg) = Array(spec(leg)["show"]).to_h { |k| [k, total(k)] }

    def prepare!(leg, user:, client: nil)
      raise ArgumentError, "#{leg} isn't on this return's road" unless route_names.include?(leg)
      figures = shown(leg)
      r = LegPreparer.call(@run, leg, figures: figures, documents: docs_for(leg), client: client)
      state = @run.leg(leg).merge(
        "prepared_at" => Time.current.iso8601, "prepared_by" => r.by, "prepared_by_user" => user.id,
        "memo" => r.memo, "issues" => r.issues, "acknowledged" => [], "figures" => figures,
        "documents_signature" => documents_signature(leg)
      )
      @run.legs = @run.legs.merge(leg => state)
      AuditLog.record("return.leg_prepared", user: user, subject: @run, leg: leg, by: r.by, issues: r.issues.size)
      verify_all!
      @run.leg(leg)
    end

    def verify_all!
      @docs = nil
      @memo = {}
      legs = @run.legs.dup
      route_names.each do |leg|
        checks = checks_for(leg)
        state = (legs[leg] || {}).merge("checks" => checks.map(&:to_h).map(&:stringify_keys), "figures" => shown(leg))
        ok = checks.all?(&:ok)
        state["status"] = ok ? "verified" : (state["prepared_at"] ? "prepared" : "not_started")
        state["verified_at"] = ok ? (state["verified_at"] || Time.current.iso8601) : nil
        state["stale"] = state["prepared_at"].present? && state["documents_signature"] != documents_signature(leg)
        legs[leg] = state
        # later checks (prior_legs) see this leg's result
        @run.legs = legs
      end
      @run.done = route_names.select { |l| legs.dig(l, "status") == "verified" }
      @run.save!
      @run
    end

    def checks_for(leg)
      Array(spec(leg)["checks"]).each_with_index.map { |c, i| run_check(leg, c, i) }
    end

    def route_names = @run.route.reject { |x| x[:pending] }.map { |x| x[:name] }

    private

    def documents_signature(leg)
      Digest::SHA256.hexdigest(docs_for(leg).map { |d| [d.id, d.status, d.kind, d.tax_year, d.fields] }.to_json + @run.inputs.to_json)[0, 16]
    end

    def money(v) = ActiveSupport::NumberHelper.number_to_delimited(v.to_f == v.to_f.round ? v.to_f.round : v.to_f.round(2))

    def run_check(leg, c, i)
      id = "#{c['type']}:#{c['key'] || c['kind'] || i}"
      label, ok, detail = case c["type"]
      when "answered"
        sits = Situation.for_playbook(@run.playbook_key).where(status: "active").to_a
        open = sits.reject { |s| %w[yes no].include?(@run.answers[s.key]) }
        ["Every situation question is answered yes or no", open.empty?, open.any? ? "#{open.size} unanswered or not sure" : nil]
      when "document"
        kind = c["kind"].to_s
        name = catalog.dig(kind, "name") || kind
        found = docs.select { |d| d.kind == kind }
        found = found.select { |d| c["where"].all? { |f, v| d.fields[f].to_s.downcase == v.to_s.downcase } } if c["where"]
        [c["label"] || "#{name} is in and confirmed", found.any?, found.empty? ? "Upload and confirm the #{name}" : nil]
      when "documents_confirmed"
        all = @run.documents.to_a
        bad = all.reject { |d| d.status == "confirmed" }
        ["Every uploaded document is identified and confirmed", all.any? && bad.empty?,
         all.empty? ? "No documents uploaded yet" : (bad.any? ? "#{bad.size} not confirmed: #{bad.map { |d| d.label || d.filename }.join(', ')}" : nil)]
      when "situation_documents"
        missing = Situation.for_playbook(@run.playbook_key).select { |s| @run.applies?(s.key) }.filter_map do |s|
          kinds = @pb.situation_documents(s.key).map(&:to_s)
          next if kinds.empty? || docs.any? { |d| kinds.include?(d.kind) }
          "#{s.key.tr('-', ' ')} (#{kinds.map { |k| catalog.dig(k, 'name') || k }.join(' or ')})"
        end
        ["Each situation that applies has its documents", missing.empty?, missing.any? ? "Missing: #{missing.join('; ')}" : nil]
      when "tax_year"
        year = @run.inputs["tax_year"].to_i
        off = docs.select { |d| d.tax_year && d.tax_year != year && !%w[form-8879 efile-acknowledgment payment-confirmation engagement-letter extension-confirmation payment-plan-confirmation].include?(d.kind) }
        ["Every document is for tax year #{year.nonzero? || '(set the tax year)'}", year.positive? && off.empty?,
         year.zero? ? "Enter the tax year when engaging the client" : (off.any? ? "#{off.map(&:label).join(', ')} #{off.size == 1 ? 'is' : 'are'} for another year" : nil)]
      when "no_duplicates"
        dupes = docs.group_by { |d| [d.kind, d.payer.to_s.downcase, d.fields.to_a.sort] }.select { |k, v| k[0] && v.size > 1 }
        ["No document is counted twice", dupes.empty?, dupes.any? ? dupes.values.map { |v| v.map(&:label).join(' = ') }.join('; ') : nil]
      when "input"
        meta = @spec.dig("inputs", c["key"]) || {}
        v = @run.inputs[c["key"]]
        ["#{meta['label'] || c['key']} is entered", v.present?, nil]
      when "attest"
        [c["text"], @run.leg(leg).dig("attested", c["key"]).present?, nil]
      when "equal", "at_most", "at_least"
        l = resolve_ref(c["left"])
        r = resolve_ref(c["right"])
        tol = c["tolerance"].to_f
        ok = case c["type"]
             when "equal" then (l - r).abs <= tol
             when "at_most" then l <= r + tol
             else l + tol >= r
             end
        waived = !ok && c["unless_attested"] && @run.leg(leg).dig("attested", c["unless_attested"]).present?
        detail = ok ? "#{money(l)} vs #{money(r)}" : "#{money(l)} vs #{money(r)}#{waived ? ' (explained by the filer)' : ''}"
        [c["label"] || "#{c["left"]} #{c["type"].tr("_", " ")} #{c["right"]}", ok || !!waived, detail]
      when "ai_review"
        st = @run.leg(leg)
        blocking = Array(st["issues"]).each_with_index.select { |iss, n| iss["severity"] == "blocking" && !Array(st["acknowledged"]).include?(n) }
        ["The #{st['prepared_by'] == 'ai' ? 'AI preparer' : 'preparer'} found no unresolved blocking issue",
         st["prepared_at"].present? && blocking.empty?,
         st["prepared_at"].blank? ? "Prepare this leg first" : (blocking.any? ? "#{blocking.size} blocking: #{blocking.map { |iss, _| iss['text'] }.join(' | ')}" : nil)]
      when "generated"
        partners = docs.select { |d| d.kind == "partner" }
        made = K1Generator.generated(@run)
        missing = partners.map { |d| d.fields["partner_ref"] } - made.map { |d| d.fields["partner_ref"] || d.payer }
        [c["label"] || "Every partner has a generated K-1", partners.any? && missing.empty? && made.size == partners.size,
         partners.empty? ? "Confirm the partner allocations first" : (missing.any? || made.size != partners.size ? "Generate the K-1s (#{made.size} of #{partners.size})" : nil)]
      when "prior_legs"
        names = route_names
        before = names.first(names.index(leg).to_i)
        open = before.reject { |l| @run.legs.dig(l, "status") == "verified" }
        ["Every earlier leg is verified", open.empty?, open.any? ? "Not verified: #{open.map { |l| Skill.current(l)&.title || l }.join(', ')}" : nil]
      when "reviewer"
        rv = @run.reviewer
        changed = rv && @run.reviewed_at && @run.documents.where("updated_at > ?", @run.reviewed_at).exists?
        ok = rv.present? && rv.id != @run.user_id && @run.reviewed_at.present? && !changed
        ["A second preparer reviewed and signed off", ok,
         rv.nil? ? "Ask a reviewer to review the return" : (@run.reviewed_at.nil? ? "Waiting for #{rv.name}" : (changed ? "Documents changed after #{rv.name}'s sign-off" : "Signed off by #{rv.name}"))]
      else
        ["Unknown check #{c['type']}", false, nil]
      end
      Check.new(id: id, label: label, ok: ok, detail: detail)
    end

    def resolve_ref(ref)
      return ref.to_f if ref.is_a?(Numeric) || ref.to_s.match?(/\A-?\d+(\.\d+)?\z/)
      ref.to_s.start_with?("totals.") ? total(ref.delete_prefix("totals.")) : resolve(ref.to_s)
    end
  end
end
