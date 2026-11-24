require "test_helper"

# Capture a worksheet from Excel: Observe → Interpret → Document → Write.
class WorksheetCaptureTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @rev = make_user(role: "reviewer", domains: %w[bql], name: "Bea BQL")
    @analyst = make_user(role: "member", domains: %w[bql], name: "Rae Analyst")
    @other = make_user(role: "member", domains: %w[legal], name: "Otto Other")
    Capture::Playbook.find("bql-analysis").install!(user: @admin)
    Capture::Playbook.find("factset-analysis").install!(user: @admin)
  end

  def dcf_cells
    cells = [{ a: "A1", t: "Discounted cash flow valuation" }, { a: "A3", t: "Security" }, { a: "B3", t: "AAPL US Equity" },
             { a: "A4", t: "WACC" }, { a: "B4", n: true }, { a: "A5", t: "Terminal growth" }, { a: "B5", n: true }, { a: "A7", t: "Millions" }]
    cols = %w[B C D E F]
    cols.each_with_index { |c, i| cells << { a: "#{c}7", t: "FY+#{i + 1}" } }
    rows = [["Revenue (consensus)", ->(_, i) { %(=BQL($B$3,"sales_rev_turn(fpt=A, fpo=#{i + 1}, ae=E)")) }],
            ["Free cash flow (consensus)", ->(_, i) { %(=BQL($B$3,"cf_free_cash_flow(fpt=A, fpo=#{i + 1}, ae=E)")) }],
            ["Discount factor", ->(_, i) { "=1/(1+$B$4)^#{i + 1}" }],
            ["PV of free cash flow", ->(c, _) { "=#{c}9*#{c}10" }],
            ["Short interest", ->(_, i) { %(=BQL($B$3,"short_int(fpo=#{i + 1})")) }]]
    rows.each_with_index do |(l, f), ri|
      cells << { a: "A#{8 + ri}", t: l }
      cols.each_with_index { |c, i| cells << { a: "#{c}#{8 + ri}", f: f.(c, i) } }
    end
    cells + [{ a: "A14", t: "Sum of PV of FCF" }, { a: "B14", f: "=SUM(B11:F11)" },
             { a: "A15", t: "Terminal value" }, { a: "B15", f: "=F9*(1+$B$5)/($B$4-$B$5)" },
             { a: "A16", t: "Shares" }, { a: "B16", f: %(=BQL($B$3,"eqy_sh_out")) },
             { a: "A17", t: "Value per share" }, { a: "B17", f: "=($B$14+$B$15)/$B$16" }]
  end

  def addin(method, path, user, params = nil)
    token = AddinToken.issue!(user: user, host: "Excel").last
    send(method, path, params: params&.to_json, headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" })
  end

  test "a BQL DCF sheet: observed, interpreted into a buildable blueprint, documented, written as a draft skill" do
    c = Capture::WorksheetInterpreter.call(user: @analyst, payload: { "sheet" => "DCF", "address" => "A1:F17", "cells" => dcf_cells.map(&:stringify_keys) })
    bp = c.blueprint
    assert_equal ["bql", "rules", "table"], [c.provider, c.interpreted_by, bp["kind"]]
    assert_equal %w[security wacc terminal_growth], bp["inputs"].map { |i| i["key"] }
    assert_equal({ "fpo" => 3, "n" => 3 }, bp["columns"][2]["params"])
    assert_equal %w[revenue_est fcf_est], bp["rows"].first(2).map { |r| r["command"] }
    assert_equal "=1/(1+{input:wacc})^{col:n}", bp["rows"][2]["formula"]
    assert_equal "={row:free_cash_flow_consensus}*{row:discount_factor}", bp["rows"][3]["formula"]
    assert_equal ["={row_sum:pv_of_free_cash_flow}", "={row_last:free_cash_flow_consensus}*(1+{input:terminal_growth})/({input:wacc}-{input:terminal_growth})", nil,
                  "=({cell:sum_of_pv_of_fcf}+{cell:terminal_value})/{cell:shares}"], bp["summary"].map { |r| r["formula"] }
    assert_equal "shares_out", bp["summary"][2]["command"]
    assert_equal "investment-analysis/valuation/intrinsic-valuation", c.interpretation["field"]

    new_cmd = FormulaCommand.find_by!(provider: "bql", key: "short_interest")
    assert_equal ['=BQL({security},"short_int(fpo={fpo})")', "unverified", "capture"], [new_cmd.syntax, new_cmd.status, new_cmd.origin]
    assert_equal "short_interest", bp["rows"][4]["command"]
    assert_empty Capture::Worksheets.problems(bp, commands: FormulaCommand.where(provider: "bql").pluck(:key), skills: [])

    assert_equal 9, c.inventory.size, "every formula pattern documented"
    assert_includes c.formulas_md, "| Summary | Value per share | formula |"
    assert_includes c.formulas_md, "## New commands (unverified)"
    assert_includes c.structure_md, "Discounted cash flow valuation"
    assert_equal %w[STRUCTURE.md FORMULAS.md blueprint.json SKILL.md], c.files.keys

    cand = c.candidate
    assert_equal ["bql", "drafted", "save", "discounted-cash-flow-valuation"], [cand.domain, cand.status, cand.proposal_kind, cand.draft_name]
    assert_equal bp, cand.worksheet
    assert c.skill_md.start_with?("---\nname: discounted-cash-flow-valuation\ndescription: ")
    assert Notification.where(user: @rev).exists?

    skill = Capture::Publisher.publish!(cand, reviewer: @rev)
    assert_equal bp, skill.source["worksheet"], "the published skill builds the captured sheet"
  end

  test "a FactSet comps grid becomes a grid blueprint keyed by the security list" do
    cells = [{ a: "A1", t: "Peer multiples" }, { a: "A3", t: "Ticker" }, { a: "B3", t: "P/E" }, { a: "C3", t: "EV/EBITDA" }]
    %w[AAPL-US MSFT-US GOOGL-US].each_with_index do |t, i|
      r = 4 + i
      cells += [{ a: "A#{r}", t: t }, { a: "B#{r}", f: %(=FDS(A#{r},"P_PE(NOW)")) }, { a: "C#{r}", f: %(=FDS(A#{r},"FG_EV_EBITDA(NOW)")) }]
    end
    cells += [{ a: "A8", t: "Median" }, { a: "B8", f: "=MEDIAN(B4:B6)" }]
    c = Capture::WorksheetInterpreter.call(user: @analyst, payload: { "sheet" => "Comps", "cells" => cells.map(&:stringify_keys) })
    bp = c.blueprint
    assert_equal ["factset", "grid"], [c.provider, bp["kind"]]
    assert_equal "AAPL-US\nMSFT-US\nGOOGL-US", bp["inputs"].first["default"]
    assert_equal ["P/E", "EV/EBITDA"], bp["columns"].map { |x| x["label"] }
    assert bp["columns"].all? { |x| x["command"].present? }
    assert_equal ["median"], bp["stats"]
    assert_equal "investment-analysis/valuation/relative-valuation", c.interpretation["field"]
  end

  test "privacy: numbers are never stored, and without a table the formulas are still documented" do
    payload = { "sheet" => "Scratch", "cells" => [{ "a" => "A1", "n" => true }, { "a" => "B1", "t" => "x" }, { "a" => "C2", "f" => "=A1*2" }, { "a" => "C3", "f" => "=A1*3" }] }
    c = Capture::WorksheetInterpreter.call(user: @analyst, payload: payload)
    assert_equal "excel", c.provider
    assert_equal({}, c.blueprint)
    assert_operator c.inventory.size, :>=, 1
    refute_match(/\b(42|3\.14)\b/, c.observed.to_json)
    assert c.observed["cells"].find { |x| x["a"] == "A1" }["n"]
    assert_raises(Capture::WorksheetInterpreter::Error) { Capture::WorksheetInterpreter.call(user: @analyst, payload: { "sheet" => "S", "cells" => [{ "a" => "A1", "t" => "x" }] }) }
  end

  test "the add-in API captures a sheet; the console shows the stages and files to the right people" do
    addin :post, "/api/v1/addin/worksheet_captures", @analyst, { sheet: "DCF", address: "A1:F17", cells: dcf_cells }
    assert_response :created
    r = response.parsed_body
    assert_equal ["Bloomberg BQL", 9, 1], [r["provider_name"], r["documented"]["formulas"], r["documented"]["new_commands"]]
    assert_equal "discounted-cash-flow-valuation", r["written"]["name"]
    id = r["id"]

    addin :post, "/api/v1/addin/worksheet_captures", @analyst, { sheet: "Empty", cells: [] }
    assert_response :unprocessable_entity
    addin :get, "/api/v1/addin/worksheet_captures/#{id}", @other
    assert_response :forbidden

    sign_in @analyst
    get worksheet_captures_path
    assert_select "a", text: "Discounted cash flow valuation"
    get worksheet_capture_path(id)
    assert_response :success
    assert_select "li", text: /Observe/
    assert_select "table th", text: "Meaning"
    get file_worksheet_capture_path(id, file: "FORMULAS.md")
    assert_includes response.body, "short_interest"
    get file_worksheet_capture_path(id, file: "blueprint.json")
    assert_equal "table", JSON.parse(response.body)["kind"]
    get skill_candidate_path(WorksheetCapture.find(id).candidate)
    assert_select "a", text: "observed, interpreted and documented"
    sign_out @analyst

    sign_in @rev
    get worksheet_captures_path
    assert_select "a", text: "Discounted cash flow valuation"
    sign_out @rev
    sign_in @other
    get worksheet_capture_path(id)
    assert_response :redirect
  end

  test "the agent guide is on the formula library page" do
    sign_in @analyst
    get formulas_path(provider: "bql")
    assert_select "a[href=?]", guide_formulas_path(provider: "bql")
    get guide_formulas_path(provider: "factset")
    assert_response :success
    assert_select "h3", text: /Observe/
    assert_select "h3", text: /Interpret/
  end

  test "road directions document every formula of a worksheet skill" do
    wp = Waypoint.find_by!(key: "road:bql-dcf-valuation")
    assert_includes wp.body, "Every formula"
    assert_includes wp.body, "fcf_est"
  end
end
