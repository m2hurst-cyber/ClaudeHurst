# The Office app marks, drawn as inline SVG.
#
# These are our own renditions in the Office visual language — the layered panel, the
# darker tab carrying the letter, the brand hues — not Microsoft's own files. Microsoft
# distributes those under its trademark and brand guidelines, and they are not on any
# package registry we can pull from. If the firm holds a licence for the genuine assets,
# drop them in `app/assets/images/office/<key>.svg` and `office_icon` serves those
# instead, with no other change.
module OfficeIconsHelper
  # Brand hues, light to dark, as used in each mark.
  OFFICE = {
    "Excel"      => { key: "excel",      tones: %w[#21a366 #33c481 #107c41 #185c37], letter: "X" },
    "Word"       => { key: "word",       tones: %w[#2b7cd3 #41a5ee #185abd #103f91], letter: "W" },
    "PowerPoint" => { key: "powerpoint", tones: %w[#ed6c47 #ff8f6b #c43e1c #9d3415], letter: "P" },
    "Outlook"    => { key: "outlook",    tones: %w[#1a73c7 #50b0e8 #0f6cbd #0a4f91], letter: "O" },
    "Teams"      => { key: "teams",      tones: %w[#5b5fc7 #7b83eb #4b53bc #3b41a5], letter: "T" },
    "Power BI"   => { key: "powerbi",    tones: %w[#e6a000 #f2c811 #b48a00 #8a6900], letter: "" },
    "SharePoint" => { key: "sharepoint", tones: %w[#036c70 #1a9ba1 #025c5f #03494c], letter: "S" }
  }.freeze

  def office_icon(app, size: 24, title: nil)
    spec = OFFICE[app] or return app_letter_fallback(app, size)
    licensed = Rails.root.join("app/assets/images/office/#{spec[:key]}.svg")
    body = licensed.exist? ? licensed.read.sub(/\A.*?<svg[^>]*>/m, "").sub(%r{</svg>\s*\z}, "") : send(:"#{spec[:key]}_mark", spec[:tones])
    tag.svg(raw(body), viewBox: "0 0 32 32", class: "shrink-0", width: size, height: size,
            role: title ? "img" : nil, "aria-hidden": title ? nil : true,
            "aria-label": title) # title given only where the mark stands alone
  end

  # The mark on a floating tile, the way Microsoft shows them: white, softly rounded,
  # lifted off the page. `active` rings it.
  def office_tile(app, size: 28, active: false, classes: "")
    # An explicit radius: the shape is a rounded square, and must not follow a token that
    # would turn a small tile into a circle.
    tag.span(office_icon(app, size: (size * 0.62).round),
             class: "grid place-items-center rounded-[10px] bg-white shadow-[0_1px_2px_rgb(31_54_42/0.06),0_6px_14px_-6px_rgb(31_54_42/0.28)] " \
                    "transition-transform duration-200 #{active ? 'ring-2 ring-slate-900' : 'hover:-translate-y-0.5'} #{classes}",
             style: "width: #{size}px; height: #{size}px")
  end

  private

  def app_letter_fallback(app, size)
    letter, colour = ApplicationHelper::APP_STYLE.fetch(app, ["?", "#52514e"])
    tag.span(letter, class: "grid place-items-center rounded-md font-bold text-white",
                     style: "width: #{size}px; height: #{size}px; background: #{colour}; font-size: #{(size * 0.42).round}px")
  end

  def letter_on(tone, letter, x: 3, y: 8, w: 15, h: 16)
    return "" if letter.blank?
    %(<rect x="#{x}" y="#{y}" width="#{w}" height="#{h}" rx="2" fill="#{tone}"/>) +
      %(<text x="#{x + w / 2.0}" y="#{y + h / 2.0 + 0.5}" text-anchor="middle" dominant-baseline="middle" ) +
      %(font-family="Segoe UI, Inter, system-ui, sans-serif" font-size="#{(h * 0.72).round}" font-weight="700" fill="#fff">#{letter}</text>)
  end

  # A document panel with a grid: the spreadsheet.
  def excel_mark(t)
    cells = []
    3.times { |r| 3.times { |c| cells << %(<rect x="#{16 + c * 5}" y="#{6 + r * 6.6}" width="4.2" height="5.6" rx="0.6" fill="#{(r + c).even? ? t[1] : t[0]}"/>) } }
    %(<path d="M12 4h16a2 2 0 0 1 2 2v20a2 2 0 0 1-2 2H12z" fill="#{t[2]}"/>) +
      %(<path d="M12 4h16a2 2 0 0 1 2 2v3H12z" fill="#{t[0]}"/>) + cells.join + letter_on(t[3], "X")
  end

  # A document panel with lines: the page.
  def word_mark(t)
    lines = 3.times.map { |i| %(<rect x="19" y="#{9 + i * 5}" width="9" height="2.2" rx="1.1" fill="#{i.zero? ? t[1] : t[0]}" opacity="#{i.zero? ? 1 : 0.85}"/>) }
    %(<path d="M12 4h16a2 2 0 0 1 2 2v20a2 2 0 0 1-2 2H12z" fill="#{t[0]}"/>) +
      %(<path d="M12 4h16a2 2 0 0 1 2 2v3H12z" fill="#{t[1]}"/>) + lines.join + letter_on(t[2], "W")
  end

  # A panel with a disc: the slide.
  def powerpoint_mark(t)
    %(<path d="M12 4h16a2 2 0 0 1 2 2v20a2 2 0 0 1-2 2H12z" fill="#{t[0]}"/>) +
      %(<circle cx="23" cy="16" r="6.5" fill="#{t[1]}"/>) +
      %(<path d="M23 9.5A6.5 6.5 0 0 1 29.5 16H23z" fill="#{t[2]}"/>) + letter_on(t[2], "P")
  end

  # An envelope behind the mark: mail.
  def outlook_mark(t)
    %(<path d="M15 8h14a1.5 1.5 0 0 1 1.5 1.5v13A1.5 1.5 0 0 1 29 24H15z" fill="#{t[1]}"/>) +
      %(<path d="M15 9.5 22.5 16 30 9.5v2L22.5 18 15 11.5z" fill="#{t[0]}" opacity="0.65"/>) + letter_on(t[2], "O")
  end

  # Two figures beside the mark: the team.
  def teams_mark(t)
    %(<circle cx="24.5" cy="8.5" r="3" fill="#{t[1]}"/>) +
      %(<path d="M19 13.5h11v7a4.5 4.5 0 0 1-4.5 4.5h-2A4.5 4.5 0 0 1 19 20.5z" fill="#{t[1]}"/>) +
      %(<circle cx="19.5" cy="9.5" r="2.4" fill="#{t[0]}" opacity="0.9"/>) + letter_on(t[2], "T")
  end

  # Rising columns: the report.
  def powerbi_mark(t)
    %(<rect x="5" y="17" width="5.5" height="11" rx="1.4" fill="#{t[0]}"/>) +
      %(<rect x="13.2" y="11" width="5.5" height="17" rx="1.4" fill="#{t[1]}"/>) +
      %(<rect x="21.4" y="4" width="5.5" height="24" rx="1.4" fill="#{t[2]}"/>)
  end

  # Linked nodes: the site.
  def sharepoint_mark(t)
    %(<circle cx="22" cy="9" r="5" fill="#{t[1]}"/>) +
      %(<circle cx="26" cy="19" r="5.5" fill="#{t[0]}" opacity="0.92"/>) +
      %(<circle cx="17.5" cy="22" r="4.5" fill="#{t[2]}" opacity="0.92"/>) + letter_on(t[3], "S", x: 2, y: 9, w: 13, h: 14)
  end
end
