require "test_helper"

# Bridges (skills and roads that cross fields or apps), the resource library, and sending
# skills from the map into a running add-in's memory (or to an agent).
class BridgesResourcesCommandsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada")
    @rev = make_user(role: "reviewer", domains: %w[finance], name: "Rae")
    @legal = make_user(role: "member", domains: %w[legal], name: "Lee")
    @source, @token = make_source(name: "Close agent")
    @variance = publish("variance-analysis", "Run the monthly variance analysis", %w[excel.step:compute-variance excel.step:run-regression], "Compute variance by cost centre with a regression on drivers.")
    @appendix = publish("charts-to-ppt-appendix", "Collect workbook charts into a PowerPoint appendix",
                        %w[excel.step:select-charts excel.step:copy-charts powerpoint.step:add-appendix-slides powerpoint.step:paste-charts], "Copy the workbook's charts into appendix slides.")
    @contract = publish("prepare-contract", "Prepare the customer contract", %w[word.step:generate-contract word.step:fill-terms], "Generate the contract and redline clause terms.")
    SkillLink.create!(from_node: "variance-analysis", to_node: "charts-to-ppt-appendix", origin: "observed", traffic: 4)
    SkillLink.create!(from_node: "variance-analysis", to_node: "prepare-contract", origin: "manual")
  end

  def publish(name, title, steps, desc)
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                               draft_name: name, draft_title: title, draft_description: desc, draft_body: "1. a\n2. b")
    Capture::Publisher.publish!(c, reviewer: @admin)
  end

  def add_file(folder, name, body = "hello", filename: "#{name.parameterize}.docx")
    r = folder.resources.new(name: name, uploaded_by: @admin)
    r.attach_file(StringIO.new(body), filename: filename, content_type: "application/octet-stream")
    r.save!
    r
  end

  # ---------- bridges ----------

  test "a skill that carries work from Excel into PowerPoint is a bridge, labelled in step order" do
    c = SkillClassification.for("charts-to-ppt-appendix")
    assert_equal %w[Excel PowerPoint], c.apps
    assert c.bridge?
    assert_equal "Excel → PowerPoint", c.bridge_label(@appendix)
  end

  test "roads between skills are bridges when they cross fields or apps" do
    SkillLink.create!(from_node: "charts-to-ppt-appendix", to_node: "prepare-contract", origin: "manual")
    map = Capture::RouteMap.call(user: @admin)
    to_appendix = map[:edges].find { |e| e[:to] == "charts-to-ppt-appendix" }
    assert_nil to_appendix.dig(:bridge, :apps), "Excel analysis → a skill that starts in Excel: the skill itself is the bridge"
    from_appendix = map[:edges].find { |e| e[:from] == "charts-to-ppt-appendix" }
    assert_equal %w[PowerPoint Word], from_appendix.dig(:bridge, :apps), "ends in PowerPoint, next begins in Word"
    to_contract = map[:edges].find { |e| e[:from] == "variance-analysis" && e[:to] == "prepare-contract" }
    assert_equal ["Data analysis", "Legal"], to_contract.dig(:bridge, :fields)
    assert_equal %w[Excel Word], to_contract.dig(:bridge, :apps)
    node = map[:nodes].find { |n| n[:id] == "charts-to-ppt-appendix" }
    assert_equal [true, "Excel → PowerPoint"], node.values_at(:bridge, :bridge_label)
  end

  test "card shows the bridge badge" do
    sign_in @rev
    get skills_path
    assert_includes response.body, "⇄ Bridge: Excel → PowerPoint"
  end

  # ---------- resource library ----------

  test "callable folders: firm folders for everyone and agents, restricted folders for their areas only" do
    legal = ResourceFolder.create!(name: "Legal")
    templates = ResourceFolder.create!(name: "Templates", parent: legal)
    finance = ResourceFolder.create!(name: "Finance")
    workbooks = ResourceFolder.create!(name: "Workbooks", parent: finance, audience: "restricted", areas: ["finance"])
    nda = add_file(templates, "Mutual NDA template")
    hex = add_file(workbooks, "Hex key worksheet", "keys", filename: "hex.xlsx")
    assert_equal "resource:legal/templates/mutual-nda-template", nda.key
    assert_equal nda, Resource.find_by_key(nda.key)
    assert nda.visible_to?(@legal)
    assert hex.visible_to?(@rev)
    assert_not hex.visible_to?(@legal)
    assert_not hex.agents_can_read?

    h = { "Authorization" => "Bearer #{@token}" }
    get api_v1_resources_path, headers: h
    assert_equal ["resource:legal/templates/mutual-nda-template"], response.parsed_body.map { |r| r["key"] }
    get api_v1_resource_path("legal/templates/mutual-nda-template"), headers: h
    assert_equal "hello", response.body
    get api_v1_resource_path("finance/workbooks/hex-key-worksheet"), headers: h
    assert_response :not_found

    sign_in @legal
    get resources_path
    assert_includes response.body, "Mutual NDA template"
    refute_includes response.body, "Hex key worksheet"
    get download_resource_path(hex)
    assert_redirected_to root_path
  end

  test "people upload files or links, attach them to skills, and replace them as new versions" do
    folder = ResourceFolder.create!(name: "Design")
    sign_in @rev
    file = Rack::Test::UploadedFile.new(StringIO.new("deck"), "application/vnd.ms-powerpoint", original_filename: "Board deck template.pptx")
    post resources_path, params: { resource: { folder_id: folder.id, file: file }, skill_id: @appendix.id }
    r = Resource.find_by!(slug: "board-deck-template")
    assert_equal ["Board deck template", "Board deck template.pptx", 4, @rev], [r.name, r.filename, r.byte_size, r.uploaded_by]
    assert SkillResource.exists?(skill_name: "charts-to-ppt-appendix", resource: r)

    post resources_path, params: { resource: { folder_id: folder.id, name: "Brand guide", url: "https://contoso.sharepoint.com/brand" } }
    assert_equal "link", Resource.find_by!(slug: "brand-guide").kind
    post resources_path, params: { resource: { folder_id: folder.id, name: "Bad", url: "http://insecure" } }
    assert_nil Resource.find_by(slug: "bad")

    patch resource_path(r), params: { resource: { file: Rack::Test::UploadedFile.new(StringIO.new("deck v2"), "application/octet-stream", original_filename: "Board deck template.pptx") } }
    assert_equal [2, "deck v2"], r.reload.values_at(:version, :content)

    get skill_path(@appendix)
    assert_includes response.body, "Board deck template"
    assert_includes response.body, "resource:design/board-deck-template"
    delete skill_resource_path(@appendix, r)
    assert_not SkillResource.exists?(skill_name: "charts-to-ppt-appendix", resource: r)

    sign_out @rev
    sign_in @legal # not the uploader, not an admin
    delete resource_path(r)
    assert Resource.exists?(r.id)
  end

  # ---------- map → add-in memory ----------

  test "send a skill from the map to my add-in: it arrives as a bundle with directions and resources" do
    folder = ResourceFolder.create!(name: "Design")
    SkillResource.create!(skill_name: "charts-to-ppt-appendix", resource: add_file(folder, "Appendix slides template", filename: "appendix.pptx"))
    sign_in @rev
    post map_send_path, params: { skills: ["charts-to-ppt-appendix"], target: "me" }, as: :json
    assert_response :created
    cmd_id = response.parsed_body["id"]
    get map_sent_path(ids: [cmd_id])
    assert_equal "pending", response.parsed_body.first["status"]

    token = AddinToken.issue!(user: @rev).last
    get api_v1_addin_commands_path, params: { host: "PowerPoint", platform: "PC" }, headers: { "Authorization" => "Bearer #{token}" }
    cmd = response.parsed_body.sole
    b = cmd["bundles"].sole
    assert_equal "charts-to-ppt-appendix", b["name"]
    assert_includes b["skill_md"], "name: charts-to-ppt-appendix"
    assert_equal %w[road junction], b["directions"].map { |d| d["kind"] } - [nil]
    assert_equal ["resource:design/appendix-slides-template"], b["resources"].map { |r| r["key"] }
    assert_equal %w[Excel PowerPoint], b["apps"]

    get api_v1_addin_commands_path, headers: { "Authorization" => "Bearer #{token}" }
    assert_empty response.parsed_body, "delivered once"
    get map_sent_path(ids: [cmd_id])
    assert_equal ["delivered", "PowerPoint on PC"], response.parsed_body.first.values_at("status", "delivered_to")

    get api_v1_addin_bundle_path("variance-analysis"), headers: { "Authorization" => "Bearer #{token}" }
    assert_equal "Run the monthly variance analysis", response.parsed_body["title"]
  end

  test "route a whole route to a colleague, or a firm skill to an agent; sandbox skills can't leak" do
    sign_in @rev
    post map_send_path, params: { skills: %w[variance-analysis charts-to-ppt-appendix], target: "user:#{@legal.id}" }, as: :json
    assert_response :created
    assert_equal "load_route", AddinCommand.last.kind
    assert Notification.exists?(user: @legal, kind: "skill_sent")

    post map_send_path, params: { skills: ["variance-analysis"], target: "source:#{@source.id}" }, as: :json
    assert_response :created
    get api_v1_commands_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_equal ["variance-analysis"], response.parsed_body.sole["bundles"].map { |b| b["name"] }

    PromotionPolicy.current.update!(initial_stage: "local")
    sandbox = publish("fx-trick", "A sandbox trick", %w[excel.step:a excel.step:b], "Sandbox only, still being tried out by finance.")
    post map_send_path, params: { skills: ["fx-trick"], target: "user:#{@legal.id}" }, as: :json
    assert_response :unprocessable_entity
    assert_match(/can't see/, response.parsed_body["error"])
    post map_send_path, params: { skills: ["fx-trick"], target: "source:#{@source.id}" }, as: :json
    assert_match(/firm or market/, response.parsed_body["error"])
    assert_equal "local", sandbox.stage
  end
end
