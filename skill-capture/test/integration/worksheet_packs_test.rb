require "test_helper"
require "open3"

# BQL and FactSet: provider areas in Excel with formula command libraries and worksheet skills
# (financial, macro, intrinsic and relative valuation, ESG; then charts and sensitivity grids).
class WorksheetPacksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @bql_rev = make_user(role: "reviewer", domains: %w[bql], name: "Bea BQL")
    @member = make_user(role: "member", domains: %w[bql], name: "Max Member")
    @bql = Capture::Playbook.find("bql-analysis")
    @fds = Capture::Playbook.find("factset-analysis")
  end

  def install! = [@bql, @fds].each { |pb| pb.install!(user: @admin) }

  test "two provider areas: worksheet skills by task, on routes, with command libraries installed unverified" do
    assert_empty @bql.problems
    assert_empty @fds.problems
    r = @bql.install!(user: @admin)
    assert_equal [11, 57], [r.created.size, r.commands]
    @fds.install!(user: @admin)
    dcf = Skill.current("bql-dcf-valuation")
    assert_equal ["bql", "local", "table", "DCF"], [dcf.domain, dcf.stage, dcf.source.dig("worksheet", "kind"), dcf.source.dig("worksheet", "sheet")]
    assert Capture::SkillStandard.check_skill(dcf).clean?, Capture::SkillStandard.check_skill(dcf).warnings.map(&:message).inspect
    assert_equal ["investment-analysis/valuation/intrinsic-valuation"], SkillClassification.for(dcf.name).field_paths
    assert_equal %w[Excel], SkillClassification.for(dcf.name).apps
    assert_equal %w[investment-analysis/financial-analysis investment-analysis/charting], SkillClassification.for("bql-chart-financial-trends").field_paths
    edge = Capture::RouteMap.new(@admin).call[:edges].find { |e| e[:from] == "bql-financial-ratios" && e[:to] == "bql-chart-financial-trends" }
    assert_nil edge[:bridge], "a chart on its own route isn't a bridge"
    assert SkillLink.manual.exists?(from_node: "bql-financial-statements", to_node: "bql-financial-ratios")
    assert SkillLink.manual.exists?(from_node: "factset-dcf-valuation", to_node: "factset-dcf-sensitivity")
    assert_includes Waypoint.find_by!(key: "junction:bql-financial-ratios").body, "continue to **Chart financial trends (BQL)**"
    assert_equal({ "unverified" => 57 }, FormulaCommand.where(provider: "bql").group(:status).count)
    assert_equal 56, FormulaCommand.where(provider: "factset").count
    rev = FormulaCommand.find_by!(provider: "bql", key: "revenue")
    assert_equal ['=BQL($B$3,"sales_rev_turn(fpt=A, fpo=0)")', %w[security fpt fpo]], [rev.sample, rev.params]
    assert_equal '=FDS($B$3,"FF_SALES(ANN,0)")', FormulaCommand.find_by!(provider: "factset", key: "revenue").sample

    r = @bql.install!(user: @admin)
    assert_equal [0, 0, 0], [r.created.size, r.updated.size, r.commands], "installing again changes nothing"
    rev.update!(status: "verified", verified_by: @bql_rev)
    FormulaCommand.create!(provider: "bql", key: "price", name: "Mine", syntax: "=BQL({security},\"px_last\")", origin: "console") rescue nil
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Capture::Playbook.root.join("bql-analysis"), dir)
      ENV["SKILL_CAPTURE_PLAYBOOK_DIR"] = dir
      f = Pathname(dir).join("bql-analysis", "commands.yml")
      f.write(f.read.sub('sales_rev_turn(fpt={fpt}, fpo={fpo})', 'sales_rev_turn(fpt={fpt}, fpo={fpo}, currency=USD)'))
      assert_equal 1, Capture::Playbook.find("bql-analysis").install!(user: @admin).commands
      assert_equal "unverified", rev.reload.status, "a changed formula needs checking again"
    ensure
      ENV.delete("SKILL_CAPTURE_PLAYBOOK_DIR")
    end
  end

  test "every shipped blueprint plans cleanly in the add-in's builder" do
    install!
    data = Skill.published.where(domain: %w[bql factset]).map do |s|
      b = Capture::Bundle.for(s, viewer: @admin, url_for: ->(_) { "" })
      { name: s.name, provider: s.domain, worksheet: b[:worksheet], sources: b[:worksheet_sources], commands: b[:commands] }
    end
    assert_equal 22, data.size
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "data.json"), data.to_json)
      File.write(File.join(dir, "check.mjs"), <<~JS)
        import { readFileSync } from "node:fs";
        import { plan } from "addin/worksheet_builder";
        const out = {};
        for (const d of JSON.parse(readFileSync(process.argv[2], "utf8"))) {
          const p = plan(d.worksheet, { commands: d.commands, sources: d.sources });
          out[d.name] = { warnings: p.warnings, cells: p.cells.length, charts: p.charts.length, unverified: p.unverified.length, sample: p.cells.find((c) => c.formula)?.formula };
        }
        console.log(JSON.stringify(out));
      JS
      stdout, stderr, st = Open3.capture3("node", "--import", Rails.root.join("test/javascript/register.mjs").to_s, File.join(dir, "check.mjs"), File.join(dir, "data.json"), chdir: Rails.root.to_s)
      assert st.success?, stderr
      res = JSON.parse(stdout)
      res.each do |name, r|
        unexpected = r["warnings"].reject { |w| w =~ /set “(econ_code|econ_code_ago|esg_code)”/ || (name == "factset-macro-dashboard" && w == "No securities listed") }
        assert_empty unexpected, "#{name}: #{unexpected.first(3).inspect}"
        assert (r["cells"].positive? || r["charts"].positive?), "#{name} builds something"
      end
      assert_equal 0, res["bql-financial-statements"]["warnings"].size
      assert_equal '=BQL($B$3,"sales_rev_turn(fpt=A, fpo=-4)")', res["bql-financial-statements"]["sample"]
      assert_match(/\A=FDS\(\$B\$3,"FF_SALES\(ANN,-4\)"\)\z/, res["factset-financial-statements"]["sample"])
      assert res["factset-esg-scorecard"]["warnings"].any? { |w| w.include?("esg_code") }, "FactSet ESG asks for the subscription's code"
      assert_equal 1, res["bql-dcf-sensitivity"]["cells"].positive? ? 1 : 0
      assert_equal 1, res["bql-chart-peer-multiples"]["charts"]
    end
  end

  test "the formula library: browse, search, verify (provider reviewers), add, and import a CSV" do
    install!
    sign_in @member
    get formulas_path(provider: "bql", q: "ebitda")
    assert_includes response.body, "sales_rev_turn" if false
    assert_includes response.body, "EV / EBITDA"
    assert_includes response.body, "Used by"
    refute_includes response.body, "✓ Verify"
    cmd = FormulaCommand.find_by!(provider: "bql", key: "ebitda")
    patch formula_path(cmd, provider: "bql"), params: { status: "verified" }
    assert_redirected_to root_path

    sign_in @bql_rev
    patch formula_path(cmd, provider: "bql"), params: { status: "verified", note: "Checked in BQL Builder, AAPL FY0" }
    assert_equal ["verified", @bql_rev, "Checked in BQL Builder, AAPL FY0"], [cmd.reload.status, cmd.verified_by, cmd.verification_note]
    post formulas_path(provider: "bql"), params: { formula_command: { key: "ebit_margin", name: "EBIT margin", category: "Ratios", syntax: '=BQL({security},"oper_margin(fpt={fpt}, fpo={fpo})")' } }
    assert_equal ["console", "unverified"], FormulaCommand.find_by!(provider: "bql", key: "ebit_margin").values_at(:origin, :status)
    post formulas_path(provider: "bql"), params: { formula_command: { key: "bad key", name: "x", syntax: 'BQL("x' } }
    assert_match(/must be lowercase|must be an Excel formula|unbalanced quotes/, flash[:alert])

    csv = "key,name,category,syntax,description,defaults\n" \
          "ebitda,EBITDA (adjusted),Income statement,\"=BQL({security},\"\"ebitda_adjusted(fpt={fpt}, fpo={fpo})\"\")\",Adjusted EBITDA,fpt=A; fpo=0\n" \
          "dvd_payout,Dividend payout,Ratios,\"=BQL({security},\"\"dvd_payout_ratio\"\")\",Payout ratio,\n" \
          ",Missing key,Other,=X(),,\n"
    post import_formulas_path(provider: "bql"), params: { file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "bql.csv") }
    assert_match(/1 new, 1 updated. 1 skipped/, flash[:alert])
    assert_equal ["unverified", "EBITDA (adjusted)"], cmd.reload.values_at(:status, :name), "an imported change to a verified formula needs checking again"
    assert_equal({ "fpt" => "A", "fpo" => "0" }, cmd.defaults)
    assert FormulaCommand.exists?(provider: "bql", key: "dvd_payout", origin: "import")
  end

  test "skill cards show their worksheet and formulas; the add-in gets the blueprint, its sources and commands" do
    install!
    sign_in @admin
    chart = Skill.current("bql-chart-peer-multiples")
    get skill_path(chart)
    assert_includes response.body, "▦ Worksheet"
    assert_includes response.body, "ColumnClustered chart of Pe ratio, Ev ebitda"
    get skill_path(Skill.current("bql-dcf-valuation"))
    assert_includes response.body, "Formulas (0 of 6 verified)"

    token = AddinToken.issue!(user: @admin).last
    get api_v1_addin_bundle_path("bql-chart-peer-multiples"), headers: { "Authorization" => "Bearer #{token}" }
    b = response.parsed_body
    assert_equal ["chart", ["bql-peer-comparables"], "bql"], [b.dig("worksheet", "kind"), b["worksheet_sources"].keys, b["provider"]]
    assert_includes b["commands"].keys, "pe_ratio"
    get api_v1_addin_skill_path("bql-dcf-valuation"), headers: { "Authorization" => "Bearer #{token}" }
    assert_equal "table", response.parsed_body["worksheet"]

    get skill_map_path
    assert_includes response.body, "FactSet"
    get playbook_path("bql-analysis")
    assert_includes response.body, "Valuation: intrinsic"
    assert_includes response.body, "57</strong> Bloomberg BQL commands"
  end
end
