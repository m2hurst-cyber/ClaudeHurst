require "test_helper"

class ProductionRunTest < ActiveSupport::TestCase
  def setup
    @company = Company.create!(name: "ProdCo #{SecureRandom.hex(2)}", status: "active")
    @product = Product.create!(company: @company, name: "Test Seltzer", sku: "SEL-#{SecureRandom.hex(2)}", format: "can", case_pack: 12)
    @line = ProductionLine.create!(name: "Line A", code: "LA")
  end

  def build_run(**overrides)
    ProductionRun.new({
      product: @product,
      production_line: @line,
      planned_units: 1000,
      scheduled_start: Time.current + 1.day
    }.merge(overrides))
  end

  test "starts in planned state" do
    r = build_run
    r.save!
    assert r.planned?
  end

  test "assigns number and batch_code on create" do
    r = build_run
    r.save!
    assert_match(/\APR-\d{4}-\d{4}\z/, r.number)
    assert_match(/\AB\d{5}-LA\z/, r.batch_code)
  end

  test "planned_units must be positive" do
    r = build_run(planned_units: 0)
    assert_not r.valid?
  end

  test "release transitions planned -> released" do
    r = build_run
    r.save!
    r.release!
    assert r.released?
  end

  test "cannot skip from planned directly to in_progress" do
    r = build_run
    r.save!
    assert_not r.start_run
    assert r.reload.planned?
  end

  test "full lifecycle planned -> released -> in_progress -> completed -> closed" do
    r = build_run
    r.save!
    r.release!
    r.start_run!
    r.complete!
    r.close!
    assert r.closed?
    assert_not_nil r.actual_start
    assert_not_nil r.actual_end
  end

  test "cancel works from planned or released" do
    r = build_run
    r.save!
    r.cancel!
    assert r.cancelled?
  end
end
