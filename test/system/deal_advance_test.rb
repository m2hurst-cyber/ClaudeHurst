require "application_system_test_case"

class DealAdvanceTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(
      email: "deal-admin@test.dev",
      password: "password123",
      password_confirmation: "password123",
      first_name: "Sys", last_name: "Admin",
      role: "admin", active: true
    )
    @company = Company.create!(name: "AdvCo", status: "active")
    @deal = Deal.create!(company: @company, name: "Big deal", amount_cents: 100_00, owner: @user)

    visit "/users/sign_in"
    fill_in "user_email", with: @user.email
    fill_in "user_password", with: "password123"
    click_button "Log in"
  end

  test "advance stage button progresses the deal through the pipeline" do
    visit "/deals/#{@deal.id}"
    assert_text "Advance to Qualified"
    click_button "Advance to Qualified"
    @deal.reload
    assert_equal "qualified", @deal.stage
    assert_text "Advance to Proposal"
  end

  test "no advance button on closed deals" do
    @deal.update_column(:stage, "closed_won")
    visit "/deals/#{@deal.id}"
    assert_no_text "Advance to"
  end
end
