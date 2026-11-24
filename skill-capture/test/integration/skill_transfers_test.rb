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
    assert_equal %w[escrow_hold escrow_release], t.credit_entries.order(:id).pluck(:kind)
    assert_equal ["settled", 0], [t.status, t.escrow_balance.to_i]
    assert @a.visible_to?(@dee)
    assert_equal %w[terms_agreed_by_sender skill_leg_deposited terms_agreed_by_buyer payment_leg_deposited crossed], t.contract_log.map { |e| e["event"] }
    assert t.log_intact?
  end

  test "escrow: if the skill changes before the swap, nothing crosses and the credits come back" do
    CreditEntry.create!(user: @dee, amount: 40, reason: "bounty")
    t = SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[rae-alpha], price: 25)
    @a.update_columns(body: "1. something else entirely")
    e = assert_raises(SkillTransfer::Error) { t.accept!(by: @dee) }
    assert_match(/changed since it was offered.*refunded/, e.message)
    assert_equal ["refunded", 40, 0], [t.reload.status, @dee.credits.to_i, @rae.credits.to_i]
    assert_equal %w[escrow_hold escrow_refund], t.credit_entries.order(:id).pluck(:kind)
    refute @a.visible_to?(@dee)
    assert t.log_intact?

    # Tampering with the log is detectable
    log = t.contract_log.deep_dup
    log[1]["detail"]["skills"] = ["something-else"]
    t.update_columns(contract_log: log)
    refute t.reload.log_intact?

    # A funded contract that never crossed is refunded by the sweep; unfunded offers expire
    t2 = SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[rae-beta], price: 10)
    t2.fund!(by: @dee)
    assert_equal 30, @dee.credits.to_i
    t2.update_columns(funded_at: 2.hours.ago)
    t3 = SkillTransfer.offer!(sender: @rae, recipient: @sam, names: %w[rae-beta])
    t3.update_columns(expires_at: 1.minute.ago)
    SkillTransfer.sweep!
    assert_equal ["refunded", "expired", 40], [t2.reload.status, t3.reload.status, @dee.credits.to_i]
  end

  test "a promotion between offer and swap doesn't break the fingerprint; the buyer can download what was delivered" do
    t = SkillTransfer.offer!(sender: @rae, recipient: @dee, names: %w[rae-alpha])
    @a.update!(stage: "firm")
    t.accept!(by: @dee)
    assert t.settled?
    sign_in @dee
    get delivered_transfer_path(t, name: "rae-alpha")
    assert_includes response.body, "name: rae-alpha"
    get transfer_path(t)
    assert_select "section[aria-label='Escrow contract'] li", text: /Cross/
    assert_select "span", text: /hash chain intact/
    sign_in @sam
    get delivered_transfer_path(t, name: "rae-alpha")
    assert_response :redirect
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
    assert_select "button", text: "Pay into escrow"
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
    assert_equal "settled", response.parsed_body["status"]
    get "/api/v1/addin/skills", params: { level: "received" }, headers: token.(@dee)
    assert_equal %w[rae-alpha], response.parsed_body.map { |s| s["name"] }
  end
end
