module Capture
  # Uploading, reading and confirming the documents on a return.
  module ReturnDocuments
    module_function

    def upload!(run, files, user:)
      Array(files).reject(&:blank?).first(20).map do |file|
        doc = ReturnDocument.from_upload(run, file, user: user)
        doc.save!
        AuditLog.record("return.document_uploaded", user: user, subject: run, document: doc.id, bytes: doc.byte_size)
        if DocumentReader.enabled?
          doc.update!(status: "reading")
          ReturnDocumentReadJob.perform_later(doc.id)
        end
        doc
      end
    end

    def read!(doc, client: nil)
      r = DocumentReader.call(doc, client: client)
      doc.kind = r.kind
      doc.assign_fields(r.fields, doc.playbook_run.playbook.catalog)
      doc.update!(tax_year: r.tax_year, payer: r.payer.presence, confidence: r.confidence, notes: r.notes.presence,
                  status: "read", read_by: "ai", label: label_for(doc))
      Legs.new(doc.playbook_run).verify_all!
      doc
    rescue DocumentReader::Error, Anthropic::Errors::Error => e
      doc.update!(status: "failed", notes: "Couldn't read it automatically (#{e.message.first(120)}). Choose the kind and enter the boxes.")
      doc
    end

    # The filer's check: kind, year and figures as they appear on the document. confirm: true locks it in.
    def update!(doc, params, user:, confirm:)
      catalog = doc.playbook_run.playbook.catalog
      kind = params[:kind].presence
      raise ArgumentError, "Unknown document kind" if kind && !catalog.key?(kind)
      doc.kind = kind if kind
      doc.assign_fields(params[:fields] || {}, catalog) if params.key?(:fields)
      doc.tax_year = params[:tax_year].to_i.nonzero? if params.key?(:tax_year)
      doc.payer = params[:payer].to_s.gsub(ReturnDocument::IDENTIFIER, "").squish.first(80).presence if params.key?(:payer)
      doc.label = label_for(doc) if doc.kind_changed? || doc.label.blank?
      doc.read_by ||= "manual"
      if confirm
        raise ArgumentError, "Choose what kind of document this is first" if doc.kind.blank?
        doc.status = "confirmed"
        doc.confirmed_at = Time.current
      elsif doc.status == "confirmed"
        doc.status = "read"
        doc.confirmed_at = nil
      end
      doc.save!
      AuditLog.record(confirm ? "return.document_confirmed" : "return.document_edited", user: user, subject: doc.playbook_run, document: doc.id, kind: doc.kind)
      Legs.new(doc.playbook_run).verify_all!
      doc
    end

    def label_for(doc)
      return nil if doc.kind.blank?
      short = if doc.kind == "w2" then "W-2"
              elsif doc.kind.match?(/\A(\d|ssa-|form-)/) then doc.kind.upcase.sub(/\AFORM-/, "Form ")
              else doc.playbook_run.playbook.catalog.dig(doc.kind, "name") || doc.kind.humanize
              end
      same = doc.playbook_run.documents.where(kind: doc.kind)
      n = (doc.persisted? ? same.where("id < ?", doc.id) : same).count + 1 # numbered in upload order
      "#{short} ##{n}"
    end
  end
end
