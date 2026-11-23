require "test_helper"

# The filer uploads documents; the AI reads them and prepares each leg of the road; each leg is
# done only when its checks verify it. Documents are encrypted and private to filer and reviewer.
class ReturnPreparationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  KEY = "individual-income-tax".freeze
  SAMPLES = Rails.root.join("playbooks", KEY, "samples")

  class FakeClaude
    attr_reader :reqs
    Msg = Struct.new(:stop_reason, :content)
    Block = Struct.new(:type, :text)
    def initialize(*answers) = (@answers = answers) && (@reqs = [])
    def beta = self
    def messages = self
    def create(**req)
      @reqs << req
      Msg.new(:end_turn, [Block.new(:text, (@answers.size > 1 ? @answers.shift : @answers.first).to_json)])
    end
  end

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @cpa = make_user(role: "reviewer", domains: %w[tax], name: "Casey CPA")
    @filer = make_user(role: "member", domains: %w[tax], name: "Pat Preparer")
    Capture::Playbook.find(KEY).install!(user: @admin)
    @run = @filer.playbook_runs.create!(playbook_key: KEY, reference: "2026-0142")
    Capture::Legs.new(@run).verify_all! # as creating a return in the console does
  end

  def upload(name, type = "application/pdf") = Rack::Test::UploadedFile.new(SAMPLES.join(name), type)

  def doc!(kind, fields, year: 2025, status: "confirmed")
    d = @run.documents.new(kind: kind, content_type: "application/pdf", content: Base64.strict_encode64("pdf #{SecureRandom.hex}"),
                           byte_size: 10, checksum: SecureRandom.hex, filename: "#{kind}.pdf", tax_year: year, status: status, read_by: "manual")
    d.assign_fields(fields, @run.playbook.catalog)
    d.label = Capture::ReturnDocuments.label_for(d)
    d.save!
    d
  end

  def legs = Capture::Legs.new(@run.reload)
  def check(leg, text) = @run.reload.leg(leg)["checks"].find { |c| c["label"].include?(text) }

  test "uploads are encrypted; the AI reads them without copying identifiers; the filer checks and confirms the figures" do
    sign_in @filer
    post playbook_run_documents_path(@run), params: { files: [upload("w2-example-employer.pdf")] }
    doc = @run.reload.documents.sole
    assert_equal ["uploaded", "application/pdf", "w2-example-employer.pdf"], [doc.status, doc.content_type, doc.filename]
    raw = ReturnDocument.connection.select_one("SELECT content, filename FROM return_documents WHERE id = #{doc.id}")
    refute_includes raw["content"], Base64.strict_encode64(File.binread(SAMPLES.join("w2-example-employer.pdf")))[0, 40]
    refute_includes raw["filename"], "w2-example"

    ai = FakeClaude.new(kind: "w2", tax_year: 2025, payer: "Example Employer Inc. EIN 12-3456789",
                        fields: [{ key: "box1", value: "85,000.00" }, { key: "box2", value: "9800" }, { key: "state", value: "CA 123-45-6789" }, { key: "line_9", value: "1" }],
                        confidence: 93, notes: "Employee SSN 123-45-6789 was on the form")
    Capture::ReturnDocuments.read!(doc, client: ai)
    doc.reload
    assert_equal ["read", "ai", "w2", 2025, 93, "W-2 #1"], [doc.status, doc.read_by, doc.kind, doc.tax_year, doc.confidence, doc.label]
    assert_equal({ "box1" => 85000.0, "box2" => 9800.0, "state" => "CA" }, doc.fields, "only the catalog's fields for a W-2, identifiers stripped")
    refute_match(/123-45-6789|12-3456789/, [doc.payer, doc.notes].join)
    block = ai.reqs.first[:messages].first[:content].first
    assert_equal ["document", "base64", "application/pdf"], [block[:type], block.dig(:source, :type), block.dig(:source, :media_type)]
    assert_match(/Never copy Social Security numbers/, ai.reqs.first[:system_])
    assert_not_includes ReturnDocument.connection.select_value("SELECT fields_json FROM return_documents WHERE id = #{doc.id}"), "85000"

    patch playbook_run_document_path(@run, doc), params: { kind: "w2", fields: { box1: "85,000", box2: "9,800" }, confirm: "1" }
    assert_equal "confirmed", doc.reload.status
    patch playbook_run_document_path(@run, doc), params: { kind: "bogus" }
    assert_match(/Unknown document kind/, flash[:alert])

    post playbook_run_documents_path(@run), params: { files: [upload("w2-example-employer.pdf")] }
    assert_match(/matches a document already on this return/, flash[:alert])
    post playbook_run_documents_path(@run), params: { files: [Rack::Test::UploadedFile.new(StringIO.new("MZ"), "application/x-msdownload", original_filename: "x.exe")] }
    assert_match(/must be a PDF or an image/, flash[:alert])
    get playbook_run_document_path(@run, doc)
    assert_equal "application/pdf", response.media_type
  end

  test "the engagement leg verifies only with the signed letter, the inputs, every question answered and the identity attested" do
    sign_in @filer
    l = @run.reload.leg("engage-the-tax-client")
    assert_equal "not_started", l["status"]
    assert_equal 5, l["checks"].count { |c| !c["ok"] }
    doc!("engagement-letter", { signed: "yes" })
    patch inputs_playbook_run_path(@run), params: { leg: "engage-the-tax-client", inputs: { tax_year: "2025", filing_status: "Single", bogus: "x" } }
    assert_nil @run.reload.inputs["bogus"]
    keys = Situation.for_playbook(KEY).pluck(:key)
    patch playbook_run_path(@run), params: { answers: keys.to_h { |k| [k, k == "hsa" ? "unsure" : "no"] } }
    assert_match(/unanswered or not sure/, check("engage-the-tax-client", "situation question")["detail"])
    patch playbook_run_path(@run), params: { answers: { "hsa" => "no" } }
    post attest_playbook_run_path(@run), params: { leg: "engage-the-tax-client", key: "identity", value: "1" }
    assert_equal "verified", @run.reload.leg("engage-the-tax-client")["status"]
    assert_equal [1, 10], @run.progress
    post attest_playbook_run_path(@run), params: { leg: "engage-the-tax-client", key: "made-up", value: "1" }
    assert_response :not_found
  end

  test "the prepared 1040 must tie to the workpapers, and the AI preparer's blocking issues hold the leg until resolved" do
    @run.update!(inputs: { "tax_year" => "2025", "filing_status" => "Single", "standard_deduction" => "15000", "salt_cap" => "10000", "state_local_income_tax" => "4300" })
    doc!("w2", { box1: 85000, box2: 9800 })
    doc!("1099-int", { box1: 1250 })
    doc!("1099-div", { box1a: 2400, box1b: 1900, box2a: 300 })
    doc!("1098", { box1: 9200 })
    doc!("property-tax-bill", { amount: 4100 })
    doc!("charitable-receipt", { amount: 2500, acknowledgment: "yes" })
    l = legs
    assert_equal [85000.0, 1250.0, 2400.0, 9800.0], %w[wages interest dividends federal_withholding].map { |k| l.total(k) }
    assert_equal [8400.0, 20100.0, 20100.0, 1.0], %w[salt itemized deduction itemizes].map { |k| l.total(k) }

    f1040 = doc!("form-1040", { line_1a: 85000, line_2b: 1250, line_3b: 2400, line_25d: 9000, line_12: 20100, line_11: 120000, line_24: 16000, line_37: 1200 })
    ai = FakeClaude.new(memo: "Entered the return; withholding is short by 800 against the W-2 (employee SSN 123-45-6789).",
                        issues: [{ severity: "blocking", text: "Line 25d is 800 less than the W-2s show." }, { severity: "note", text: "Itemizing beats the standard deduction." }])
    sign_in @filer
    state = legs.prepare!("prepare-the-individual-return", user: @filer, client: ai)
    assert_equal ["ai", "prepared"], [state["prepared_by"], state["status"]]
    refute_includes state["memo"], "123-45-6789"
    sent = ai.reqs.first[:messages].first[:content]
    refute_match(/Example|form-1040\.pdf|Pat Preparer/, sent)
    assert_includes JSON.parse(sent)["documents"].first, "line_25d 9,000"
    assert_match(/Follow the\s+skill's instructions/, ai.reqs.first[:system_])
    c = check("prepare-the-individual-return", "Line 25d ties")
    assert_equal [false, "9,000 vs 9,800"], [c["ok"], c["detail"]]
    assert_match(/1 blocking/, check("prepare-the-individual-return", "unresolved blocking")["detail"])

    f1040.assign_fields(f1040.fields.merge("line_25d" => 9800), @run.playbook.catalog)
    f1040.save!
    post attest_playbook_run_path(@run), params: { leg: "prepare-the-individual-return", key: "diagnostics", value: "1" }
    assert check("prepare-the-individual-return", "Line 25d ties")["ok"]
    assert @run.reload.leg("prepare-the-individual-return")["stale"], "flagged: documents changed after it was prepared"
    assert_equal "prepared", @run.leg("prepare-the-individual-return")["status"], "still held by the unresolved blocking issue"
    post acknowledge_playbook_run_path(@run), params: { leg: "prepare-the-individual-return", index: 0 }
    assert_equal "verified", @run.reload.leg("prepare-the-individual-return")["status"]
  end

  test "a whole return, prepared leg by leg and verified end to end, with a second preparer's sign-off" do
    keys = Situation.for_playbook(KEY).pluck(:key)
    @run.update!(answers: keys.to_h { |k| [k, %w[self-employment investment-sales marketplace-insurance].include?(k) ? "yes" : "no"] },
                 inputs: { "tax_year" => "2025", "filing_status" => "Single", "standard_deduction" => "15000", "salt_cap" => "10000",
                           "state_local_income_tax" => "4300", "expected_withholding_next_year" => "9000" })
    doc!("engagement-letter", { signed: "yes" }, year: nil)
    doc!("w2", { box1: 85000, box2: 9800 })
    doc!("1099-int", { box1: 1250 })
    doc!("1099-div", { box1a: 2400, box1b: 1900, box2a: 300 })
    doc!("1099-b", { proceeds: 15000, cost_basis: 11000, short_term_gain: 500, long_term_gain: 3500 })
    doc!("1099-nec", { box1: 18000 })
    doc!("business-summary", { gross_receipts: 21500, total_expenses: 6200 })
    doc!("1095-a", { annual_premium: 6000, annual_slcsp: 6600, annual_advance: 4800 })
    doc!("1098", { box1: 9200 })
    doc!("property-tax-bill", { amount: 4100 })
    doc!("charitable-receipt", { amount: 2500, acknowledgment: "yes" })
    doc!("form-1040", { line_1a: 85000, line_2b: 1250, line_3b: 2400, line_25d: 9800, line_12: 20100, line_11: 120000, line_24: 16000, line_37: 1200 })
    doc!("form-8879", { signed: "yes", agi: 120000, total_tax: 16000 }, year: nil)
    doc!("efile-acknowledgment", { status: "Accepted" }, year: nil)
    doc!("payment-confirmation", { amount: 1200, jurisdiction: "IRS" }, year: nil)

    sign_in @filer
    road = @run.route.map { |x| x[:name] }
    assert_equal 13, road.size
    road.each do |leg|
      post prepare_playbook_run_path(@run), params: { leg: leg }
      Array(@run.playbook.leg_spec(leg)["checks"]).select { |c| c["type"] == "attest" }.each do |c|
        post attest_playbook_run_path(@run), params: { leg: leg, key: c["key"], value: "1" }
      end
    end
    open = road.reject { |leg| @run.reload.verified?(leg) }
    assert_equal ["review-the-individual-return"], open, "everything verifies except review, which needs a second person"
    assert_equal({ "gross_receipts" => 21500.0, "net_profit" => 15300.0, "se_earnings" => 14130.0, "receipts_on_1099s" => 18000.0 },
                 @run.leg("report-self-employment-income")["figures"].slice("gross_receipts", "net_profit", "se_earnings", "receipts_on_1099s"))
    assert_equal [16000.0, 7000.0, 1750.0], @run.leg("plan-next-tax-year")["figures"].values_at("required_annual_payment", "estimates_needed", "quarterly_estimate")

    post sign_off_playbook_run_path(@run)
    assert_redirected_to root_path, "the filer can't sign off their own return"
    post complete_playbook_run_path(@run)
    assert_match(/Every leg must be verified first/, flash[:alert])
    post request_review_playbook_run_path(@run), params: { reviewer_id: @cpa.id }
    assert @cpa.notifications.where(kind: "return_review").exists?

    sign_in @cpa
    get playbook_run_path(@run)
    assert_response :success
    assert_includes response.body, "Sign off as reviewer"
    post sign_off_playbook_run_path(@run)
    assert @run.reload.verified?("review-the-individual-return")
    delete playbook_run_document_path(@run, @run.documents.first)
    assert_redirected_to root_path, "the reviewer can look but not change documents"

    sign_in @filer
    doc = @run.documents.find_by!(kind: "w2")
    patch playbook_run_document_path(@run, doc), params: { fields: { box1: "85000", box2: "9800" }, confirm: "1" }
    assert_match(/Documents changed after Casey CPA's sign-off/, check("review-the-individual-return", "second preparer")["detail"])
    sign_in @cpa
    post sign_off_playbook_run_path(@run)
    sign_in @filer
    post complete_playbook_run_path(@run)
    assert_equal "completed", @run.reload.status
  end

  test "returns and their documents are private to the filer and the reviewer they chose" do
    d = doc!("w2", { box1: 1 })
    stranger = make_user(role: "reviewer", domains: %w[tax])
    sign_in stranger
    get playbook_run_path(@run)
    assert_response :not_found
    sign_in stranger
    get playbook_run_document_path(@run, d)
    assert_response :not_found
    sign_in @filer
    post request_review_playbook_run_path(@run), params: { reviewer_id: @filer.id }
    assert_redirected_to root_path
    get playbook_run_path(@run)
    assert_includes response.body, "W-2 #1"
    assert_includes response.body, "Prepare"
  end

  test "a playbook's leg specs are checked before install" do
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Capture::Playbook.root.join(KEY), dir)
      ENV["SKILL_CAPTURE_PLAYBOOK_DIR"] = dir
      f = Pathname(dir).join(KEY, "legs.yml")
      f.write(f.read.sub("wages: [w2.box1]", "wages: [w2.box99]").sub("documents: [1099-b]", "documents: [1099-zz]"))
      problems = Capture::Playbook.find(KEY).problems
      assert_includes problems, "total wages: unknown w2.box99"
      assert_includes problems, "report-investment-sales: unknown document 1099-zz"
    ensure
      ENV.delete("SKILL_CAPTURE_PLAYBOOK_DIR")
    end
  end
end
