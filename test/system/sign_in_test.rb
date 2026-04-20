require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "admin can sign in and reach the dashboard" do
    User.create!(
      email: "sys-admin@test.dev",
      password: "password123",
      password_confirmation: "password123",
      first_name: "Sys",
      last_name: "Admin",
      role: "admin",
      active: true
    )

    visit "/users/sign_in"
    fill_in "user_email", with: "sys-admin@test.dev"
    fill_in "user_password", with: "password123"
    click_button "Log in"

    assert_text "Signed in"
    assert_selector "h1, h2", text: /dashboard/i
  end
end
