require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  test "auto-generates slug from name" do
    c = Company.create!(name: "Sunray Seltzer", status: "active")
    assert_equal "sunray-seltzer", c.slug
    assert_equal "sunray-seltzer", c.to_param
  end

  test "status must be in STATUSES" do
    c = Company.new(name: "X", status: "nope")
    assert_not c.valid?
  end

  test "name is required" do
    assert_not Company.new(status: "active").valid?
  end

  test "slug collisions get suffixed" do
    Company.create!(name: "Acme", status: "active")
    b = Company.create!(name: "Acme", status: "active")
    assert_equal "acme-2", b.slug
  end
end
