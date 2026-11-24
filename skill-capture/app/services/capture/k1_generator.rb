module Capture
  # The K-1 generator: one Schedule K-1 statement per partner from the confirmed Form 1065 totals
  # and partner allocations. Each line is the 1065 amount times the partner's profit percentage,
  # rounded so the K-1s add up to the return to the cent (largest remainders take the extra cents);
  # distributions are each partner's own. Statements are PDFs stored as confirmed "k-1" documents on
  # the partnership's return, and can be sent into a partner's individual return (the handoff).
  module K1Generator
    class Error < StandardError; end
    LINES = { "ordinary_income" => "Ordinary business income (loss)", "rental_income" => "Net rental real estate income (loss)",
              "interest" => "Interest income", "dividends" => "Ordinary dividends" }.freeze

    module_function

    def generated(run) = run.documents.where(kind: "k-1", read_by: "generated").to_a.sort_by { |d| d.fields["partner_ref"].to_s }

    def generate!(run, user:)
      raise Error, "This playbook doesn't generate K-1s" unless run.playbook.leg_specs.fetch("legs", {}).values.any? { |l| l["generate"] == "k1" }
      docs = run.documents.confirmed.to_a
      summary = docs.select { |d| d.kind == "form-1065-summary" }
      partners = docs.select { |d| d.kind == "partner" }.sort_by { |d| d.fields["partner_ref"].to_s }
      raise Error, "Confirm the Form 1065 totals first" if summary.size != 1
      raise Error, "Confirm the partner allocations first" if partners.empty?
      pct = partners.map { |d| d.fields["profit_pct"].to_f }
      raise Error, "Profit percentages add up to #{pct.sum.round(4)}%, not 100%" unless (pct.sum - 100).abs <= 0.01
      refs = partners.map { |d| d.fields["partner_ref"].to_s.strip }
      raise Error, "Every partner needs a reference" if refs.any?(&:empty?)
      raise Error, "Partner references must be different" if refs.uniq.size != refs.size

      totals = summary.first.fields
      shares = LINES.keys.to_h { |k| [k, split(totals[k].to_f, pct)] }
      year = run.inputs["tax_year"].to_i.nonzero?
      generated(run).each(&:destroy!) # regenerating replaces the previous set
      partners.each_with_index.map do |p, i|
        fields = shares.transform_values { |v| v[i] }.merge("distributions" => p.fields["distributions"].to_f.round(2))
        pdf = statement_pdf(run, p.fields["partner_ref"], p.fields["profit_pct"], fields, year)
        d = run.documents.new(kind: "k-1", read_by: "generated", status: "confirmed", confirmed_at: Time.current, tax_year: year,
                              payer: "Partnership return #{run.reference}", filename: "k-1-#{p.fields['partner_ref'].to_s.parameterize}.pdf",
                              content_type: "application/pdf", content: Base64.strict_encode64(pdf), byte_size: pdf.bytesize,
                              checksum: Digest::SHA256.hexdigest(pdf), uploaded_by: user,
                              notes: "Generated for partner #{p.fields['partner_ref']} (#{p.fields['profit_pct']}% profit share).")
        d.assign_fields(fields.merge("partner_ref" => p.fields["partner_ref"]), run.playbook.catalog)
        d.fields_json = d.fields.merge("partner_ref" => p.fields["partner_ref"]).to_json # kept to match K-1 to partner
        d.label = "K-1 #{p.fields['partner_ref']}"
        d.save!
        d
      end.tap do |made|
        AuditLog.record("k1.generated", user: user, subject: run, count: made.size)
        Legs.new(run.reload).verify_all!
      end
    end

    # Splits an amount by percentages so the parts add up exactly (to the cent).
    def split(amount, pcts)
      cents = (amount * 100).round
      raw = pcts.map { |p| cents * p / 100.0 }
      base = raw.map { |r| r.negative? ? r.ceil : r.floor }
      left = cents - base.sum
      order = raw.each_with_index.sort_by { |r, i| [-(r - base[i]).abs, i] }.map(&:last)
      order.first(left.abs).each { |i| base[i] += left <=> 0 }
      base.map { |c| c / 100.0 }
    end

    # The handoff: copy a generated K-1 into one of the same preparer's open individual returns.
    def deliver!(k1, target, user:)
      raise Error, "Only generated K-1s can be sent" unless k1.kind == "k-1" && k1.read_by == "generated"
      raise Error, "You can only send to your own open returns" unless target.user_id == user.id && target.status == "open"
      raise Error, "That return doesn't take K-1s" unless target.playbook.catalog.key?("k-1")
      if target.documents.exists?(checksum: k1.checksum)
        raise Error, "That return already has this K-1"
      end
      copy = target.documents.new(kind: "k-1", read_by: "handoff", status: "read", tax_year: k1.tax_year, payer: k1.payer,
                                  filename: k1.filename, content_type: k1.content_type, content: k1.content, byte_size: k1.byte_size,
                                  checksum: k1.checksum, uploaded_by: user,
                                  notes: "Sent from the K-1 generator on partnership return #{k1.playbook_run.reference}. Check the figures and confirm.")
      copy.assign_fields(k1.fields, target.playbook.catalog)
      copy.label = ReturnDocuments.label_for(copy)
      copy.save!
      sit = Situation.for_playbook(target.playbook_key).find_by(key: "k1-income")
      target.update!(answers: target.answers.merge(sit.key => "yes")) if sit
      sent = k1.playbook_run
      log = sent.legs.dig("generate-schedule-k1s", "delivered") || {}
      sent.legs = sent.legs.merge("generate-schedule-k1s" => sent.leg("generate-schedule-k1s").merge("delivered" => log.merge(k1.id.to_s => { "to" => target.id, "reference" => target.reference, "at" => Time.current.iso8601 })))
      sent.save!
      AuditLog.record("k1.delivered", user: user, subject: target, from_run: sent.id, k1: k1.id)
      Legs.new(target.reload).verify_all!
      copy
    end

    def statement_pdf(run, ref, pct, fields, year)
      money = ->(v) { ActiveSupport::NumberHelper.number_to_currency(v, unit: "") }
      lines = [["Schedule K-1 statement (generated)", 18, true],
               ["Partnership return #{run.reference}#{year ? " - tax year #{year}" : ''}", 11, false],
               ["Partner: #{ref} - profit share #{pct}%", 11, false],
               ["", 6, false]]
      LINES.each { |k, label| lines << ["#{label.ljust(42, '.')} #{money.(fields[k]).rjust(14)}", 11, false] }
      lines << ["#{'Distributions'.ljust(42, '.')} #{money.(fields['distributions']).rjust(14)}", 11, false]
      lines += [["", 6, false], ["Allocation statement for review and entry in tax software; the official", 9, false],
                ["Schedule K-1 (Form 1065) is produced by the software. Partner TINs are not shown.", 9, false]]
      SimplePdf.render(lines)
    end
  end
end
