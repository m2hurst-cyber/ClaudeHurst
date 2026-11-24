module Capture
  # A minimal one-page PDF (Helvetica, plain text lines), enough for a generated statement.
  # Lines are (text, size, bold) tuples; text is reduced to printable ASCII.
  module SimplePdf
    module_function

    def render(lines)
      y = 760
      ops = ["BT"]
      lines.each do |text, size, bold|
        size ||= 11
        ops << "/#{bold ? 'F2' : 'F1'} #{size} Tf 1 0 0 1 50 #{y} Tm (#{escape(text)}) Tj"
        y -= (size + 7)
      end
      ops << "ET"
      stream = ops.join("\n")
      objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
        "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
      ]
      out = +"%PDF-1.4\n"
      offsets = objects.each_with_index.map do |obj, i|
        at = out.bytesize
        out << "#{i + 1} 0 obj\n#{obj}\nendobj\n"
        at
      end
      xref = out.bytesize
      out << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
      offsets.each { |o| out << format("%010d 00000 n \n", o) }
      out << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
      out.b
    end

    def escape(text)
      ActiveSupport::Inflector.transliterate(text.to_s).gsub(/[^\x20-\x7E]/, "").gsub(/([\\()])/) { "\\#{$1}" }
    end
  end
end
