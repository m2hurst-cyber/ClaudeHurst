module Pdf
  class ContractPdf < Base
    def draw_body
      @doc.text "CO-MANUFACTURING AGREEMENT", size: 22, style: :bold
      @doc.text "Number: #{@record.number}"
      @doc.text "Title: #{@record.title}"
      @doc.text "Customer: #{@record.company.name}"
      @doc.text "Term: #{@record.start_on} to #{@record.end_on}"
      @doc.text "Payment terms: #{@record.payment_terms.tr('_', ' ').upcase}"
      @doc.text "Minimum run (units): #{@record.minimum_run_units}" if @record.minimum_run_units
      @doc.move_down 12

      if @record.pricing_tiers.any?
        @doc.text "Pricing Tiers", style: :bold
        rows = [["Product", "Min Qty", "Unit Price"]]
        @record.pricing_tiers.includes(:product).each do |t|
          rows << [t.product.display_name, t.min_quantity.to_s, money(t.unit_price_cents)]
        end
        @doc.table(rows, header: true, width: @doc.bounds.width) do
          row(0).font_style = :bold
          row(0).background_color = "EEEEEE"
        end
        @doc.move_down 12
      end

      @doc.text "Terms:", style: :bold
      @doc.text @record.terms.presence || "Standard co-manufacturing terms apply."
    end
  end
end
