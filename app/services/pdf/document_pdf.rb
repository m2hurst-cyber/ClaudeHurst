module Pdf
  class DocumentPdf < Base
    LABELS = {
      "Quote" => "QUOTE",
      "Invoice" => "INVOICE"
    }.freeze

    def draw_body
      type = @record.class.name
      @doc.text(LABELS.fetch(type, type.upcase), size: 22, style: :bold)
      @doc.text "Number: #{@record.number}"
      @doc.text "Date: #{@record.issued_on || Date.current}"
      @doc.text "Bill to: #{@record.company.name}"
      @doc.move_down 10

      rows = [["Description", "Qty", "Unit", "Total"]]
      @record.line_items.each do |li|
        total = (li.quantity * li.unit_price_cents * (1 + li.tax_rate)).round
        rows << [li.description, li.quantity.to_s, money(li.unit_price_cents), money(total)]
      end
      rows << ["", "", "Subtotal", money(@record.subtotal_cents)]
      rows << ["", "", "Tax", money(@record.tax_cents)]
      rows << ["", "", "Total", money(@record.total_cents)]
      @doc.table(rows, header: true, width: @doc.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = "EEEEEE"
      end

      if @record.respond_to?(:notes) && @record.notes.present?
        @doc.move_down 12
        @doc.text "Notes:", style: :bold
        @doc.text @record.notes
      end
    end
  end
end
