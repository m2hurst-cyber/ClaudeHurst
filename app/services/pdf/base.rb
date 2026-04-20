module Pdf
  class Base
    include Prawn::View if defined?(Prawn::View)

    def initialize(record)
      @record = record
      @doc = Prawn::Document.new(page_size: "LETTER", margin: 48)
    end

    def render
      draw_header
      draw_body
      draw_footer
      @doc.render
    end

    def render_to(path)
      File.binwrite(path, render)
    end

    private

    def draw_header
      @doc.text "ClaudeHurst Co-Packing", size: 18, style: :bold
      @doc.text "Beverage Contract Manufacturing", size: 10, color: "666666"
      @doc.move_down 12
      @doc.stroke_horizontal_rule
      @doc.move_down 12
    end

    def draw_body
      # override
    end

    def draw_footer
      @doc.number_pages "Page <page> of <total>", at: [0, -20], size: 9, align: :right
    end

    def money(cents, currency = "USD")
      Money.new(cents.to_i, currency).format
    end
  end
end
