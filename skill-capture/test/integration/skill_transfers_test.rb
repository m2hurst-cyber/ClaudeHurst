require "test_helper"

# Person to person: send one skill or a selection to a coworker, free or for credits, without promoting it.
class SkillTransfersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    PromotionPolicy.current.update!(initial_stage: "local")
    @admin = make_user(role: "admin", name: "Ada Admin")
    @rae = make_user(role: "member", domains: %w[finance], name: "Rae")
    @dee = make_user(role: "member", domains: %w[legal], name: "Dee")
    @sam = make_user(role: "member", domains: %w[sales], name: "Sam")
    @a = publish("rae-alpha", @rae)
    @b = publish("rae-beta", @rae)
    @other = publish("someone-elses", nil)
    @firm = publish("firm-wide", nil).tap { |s| s.update!(stage: "firm") }
  end

  def publish(name, requester)
    steps = ["x.#{name}:a", "x.#{name}:b"]
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted", requested_by: requester,
                               draft_name: name, draft_title: name.titleize, draft_description: "Does #{name}.", draft_body: "1. a\n2. b")
    Capture::Publisher.publish!(c, reviewer: @admin).tap { |s| assert_equal "local", s.stage }
  end

  test "free transfer of a selection: the recipient sees the skills at their stage, nothing is promoted" do
    refute @a.visible_to?(@dee)
    t = SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[rae-alpha rae-beta], message: "These save me an hour")
    assert_equal ["offered", "2 skills"], [t.status, t.label]
    assert Notification.exists?(user: @dee, kind: "skill_transfer")
    refute @a.visible_to?(@dee), "not before accepting"
    t.accept!(by: @dee)
    assert @a.visible_to?(@dee) && @b.visible_to?(@dee)
    assert_equal %w[local local], [@a.reload.stage, @b.reload.stage]
    refute @a.visible_to?(@sam)
    assert_equal %w[rae-alpha rae-beta], Skill.published.at_level("received", @dee).pluck(:name).sort
    assert_equal 0, CreditEntry.count
    assert_raises(SkillTransfer::Error) { t.accept!(by: @dee) }
  end

  test "paid transfer: credits move from recipient to sender on acceptance, never below zero" do
    CreditEntry.create!(user: @dee, amount: 30, reason: "bounty")
    t = SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[rae-alpha], price: 50)
    e = assert_raises(SkillTransfer::Error) { t.accept!(by: @dee) }
    assert_match(/30.0 credits/, e.message)
    refute @a.visible_to?(@dee)
    CreditEntry.create!(user: @dee, amount: 25, reason: "bounty")
    assert_raises(SkillTransfer::Error) { t.accept!(by: @sam) }
    t.accept!(by: @dee)
    assert_equal [5, 50], [@dee.credits.to_i, @rae.credits.to_i]
    assert_equal 2, t.credit_entries.count
    assert @a.visible_to?(@dee)
  end

  test "rules: what you can send, what you can sell, who can respond" do
    err = ->(**kw) { assert_raises(ActiveRecord::RecordInvalid) { SkillTransfer.offer!(sender: @rae, recipient: @dee, **kw) }.record.errors.full_messages.to_sentence }
    assert_match(/can only charge/, err.(names: %w[firm-wide], price: 5))
    assert_match(/can't be you/, assert_raises(ActiveRecord::RecordInvalid) { SkillTransfer.offer!(sender: @rae, recipient: @rae, names: %w[rae-alpha]) }.message)
    assert_match(/No skill/, err.(names: %w[nope]))
    SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[firm-wide]) # sharing a firm skill free is fine
    # Someone else's local skill in my area: I can see it but can't send it on
    assert @other.visible_to?(@rae)
    assert_match(/can't send/, err.(names: %w[someone-elses]))

    # Forwarding: only with permission, and only free
    SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[rae-alpha]).accept!(by: @dee)
    assert_raises(ActiveRecord::RecordInvalid) { SkillTransfer.offer!(sender: @dee, recipient: @sam, names: %w[rae-alpha]) }
    SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[rae-beta], allow_forward: true).accept!(by: @dee)
    assert_match(/can only charge/, assert_raises(ActiveRecord::RecordInvalid) { SkillTransfer.offer!(sender: @dee, recipient: @sam, names: %w[rae-beta], price: 1) }.message)
    SkillTransfer.offer!(sender: @dee, recipient: @sam, names: %w[rae-beta]).accept!(by: @sam)
    assert @b.visible_to?(@sam)

    # Paying for something the coworker can already use is refused
    assert_match(/can already use/, err.(names: %w[rae-alpha], price: 3))
    # Withdraw and decline; expiry
    t = SkillTransfer.offer!(sender: @rae, recipient: @sam, names: %w[rae-alpha])
    assert_raises(SkillTransfer::Error) { t.cancel!(by: @sam) }
    t.cancel!(by: @rae)
    assert_raises(SkillTransfer::Error) { t.accept!(by: @sam) }
    t2 = SkillTransfer.offer!(sender: @rae, recipient: @sam, names: %w[rae-alpha])
    t2.update!(expires_at: 1.minute.ago)
    assert_raises(SkillTransfer::Error) { t2.accept!(by: @sam) }
  end

  test "console portal: send from the skill page, accept from the inbox" do
    CreditEntry.create!(user: @dee, amount: 20, reason: "bounty")
    sign_in @rae
    get skill_path(@a)
    assert_select "a[href=?]", new_transfer_path(skills: ["rae-alpha"])
    get new_transfer_path(skills: ["rae-alpha"])
    assert_select "input[name='skills[]'][value=rae-alpha][checked]"
    assert_select "input[name='skills[]'][value=someone-elses]", count: 0
    post transfers_path, params: { recipient_id: @dee.id, skills: %w[rae-alpha rae-beta], price: "12.50", message: "Worth it" }
    t = SkillTransfer.last
    assert_redirected_to transfer_path(t)
    assert_equal 12.5, t.price.to_f
    sign_out @rae

    sign_in @dee
    get transfers_path
    assert_select "a", text: "Transfers (1)"
    assert_select "button", text: "Pay & accept"
    post accept_transfer_path(t)
    follow_redirect!
    assert_select "p", text: /Sent to me/
    get skills_path(level: "received")
    assert_select "a", text: "Rae Alpha"
    assert_equal 7.5, @dee.credits.to_f
    get transfer_path(SkillTransfer.create!(sender: @rae, recipient: @sam, items: [{ "name" => "firm-wide", "version" => 1, "title" => "Firm Wide" }]))
    assert_response :redirect, "a stranger can't open someone else's transfer"
  end

  test "add-in: send from a skill, see and accept offers in the library" do
    token = ->(u) { { "Authorization" => "Bearer #{AddinToken.issue!(user: u, host: 'Excel').last}", "Content-Type" => "application/json" } }
    get "/api/v1/addin/skills/rae-alpha", headers: token.(@rae)
    assert_equal [true, true], response.parsed_body.values_at("can_send", "can_sell")
    get "/api/v1/addin/transfers/coworkers", params: { q: "De" }, headers: token.(@rae)
    assert_equal ["Dee"], response.parsed_body.map { |u| u["name"] }
    post "/api/v1/addin/transfers", params: { skills: ["rae-alpha"], recipient_id: @dee.id, message: "Try it" }.to_json, headers: token.(@rae)
    assert_response :created
    id = response.parsed_body["id"]
    post "/api/v1/addin/transfers", params: { skills: ["someone-elses"], recipient_id: @dee.id }.to_json, headers: token.(@rae)
    assert_response :unprocessable_entity

    get "/api/v1/addin/transfers", headers: token.(@dee)
    assert_equal [id], response.parsed_body["incoming"].map { |x| x["id"] }
    post "/api/v1/addin/transfers/#{id}/accept", headers: token.(@sam)
    assert_response :not_found
    post "/api/v1/addin/transfers/#{id}/accept", headers: token.(@dee)
    assert_equal "accepted", response.parsed_body["status"]
    get "/api/v1/addin/skills", params: { level: "received" }, headers: token.(@dee)
    assert_equal %w[rae-alpha], response.parsed_body.map { |s| s["name"] }
  end
end
