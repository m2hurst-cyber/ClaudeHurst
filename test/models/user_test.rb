require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**overrides)
    User.new({
      email: "u#{SecureRandom.hex(4)}@test.dev",
      first_name: "Test",
      role: "admin",
      active: true,
      password: "password123",
      password_confirmation: "password123"
    }.merge(overrides))
  end

  test "valid user saves" do
    assert build_user.save
  end

  test "role must be in ROLES" do
    u = build_user(role: "wizard")
    assert_not u.valid?
    assert_includes u.errors[:role], "is not included in the list"
  end

  test "first_name required" do
    u = build_user(first_name: nil)
    assert_not u.valid?
  end

  test "email must be unique" do
    email = "dup#{SecureRandom.hex(2)}@test.dev"
    build_user(email: email).save!
    dup = build_user(email: email)
    assert_not dup.valid?
  end

  test "display_name falls back to email" do
    u = build_user(first_name: "Jo", last_name: nil)
    assert_equal "Jo", u.display_name
    u2 = build_user(first_name: "A", last_name: "B")
    assert_equal "A B", u2.display_name
  end

  test "role predicates" do
    u = build_user(role: "sales")
    assert u.sales?
    assert_not u.admin?
  end
end
