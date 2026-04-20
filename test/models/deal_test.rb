require "test_helper"

class DealTest < ActiveSupport::TestCase
  def company
    @company ||= Company.create!(name: "DealCo #{SecureRandom.hex(2)}", status: "active")
  end

  def build_deal(**overrides)
    Deal.new({ name: "Demo", company: company, amount_cents: 10_000 }.merge(overrides))
  end

  test "starts in lead state" do
    d = build_deal
    d.save!
    assert d.lead?
  end

  test "stage must be in STAGES" do
    d = build_deal(stage: "imaginary")
    assert_not d.valid?
  end

  test "win transition moves to closed_won and stamps closed_at" do
    d = build_deal
    d.save!
    d.propose!
    d.win!
    assert d.closed_won?
    assert_not_nil d.reload.closed_at
  end

  test "cannot skip lose to win" do
    d = build_deal
    d.save!
    d.lose!
    assert d.closed_lost?
    assert_not d.win
  end

  test "open? excludes closed states" do
    d = build_deal
    d.save!
    assert d.open?
    d.lose!
    assert_not d.open?
  end
end
