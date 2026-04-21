require "application_system_test_case"

class CompanyShowTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(
      email: "company-admin@test.dev",
      password: "password123",
      password_confirmation: "password123",
      first_name: "Casey",
      last_name: "Admin",
      role: "admin",
      active: true
    )

    @company = Company.create!(name: "Northwind Bev", status: "active", owner: @user)
    @primary_contact = Contact.create!(company: @company, first_name: "Priya", last_name: "Primary", email: "priya@test.dev", primary: true, title: "Buyer")
    @secondary_contact = Contact.create!(company: @company, first_name: "Sam", last_name: "Secondary", email: "sam@test.dev", primary: false, title: "Planner")
    @deal = Deal.create!(company: @company, name: "Spring launch", amount_cents: 250_00, owner: @user, expected_close_on: Date.current + 5.days)
    @product = Product.create!(company: @company, name: "Citrus Spark", sku: "CIT-001")
    @line = ProductionLine.create!(name: "Line 1", code: "L1")
    @run = ProductionRun.create!(
      product: @product,
      production_line: @line,
      owner: @user,
      planned_units: 1_000,
      scheduled_start: 2.days.from_now.change(sec: 0),
      scheduled_end: 2.days.from_now.change(sec: 0) + 2.hours
    )

    Task.create!(subject: @company, title: "Company kickoff", assignee: @user, due_on: Date.current + 1.day, priority: "normal")
    Task.create!(subject: @deal, title: "Deal follow-up", assignee: @user, due_on: Date.current + 2.days, priority: "high")
    Task.create!(subject: @product, title: "Product QA review", assignee: @user, due_on: Date.current + 3.days, priority: "normal")

    Reminder.create!(subject: @company, user: @user, remind_at: 1.day.from_now.change(sec: 0), channel: "both", recurrence: "none", message: "Confirm forecast")

    sign_in_as(@user)
  end

  test "company page shows restored cards for contacts, tasks, deals, runs, and reminders" do
    visit company_path(@company)

    assert_text "Primary and secondary contacts"
    assert_text @primary_contact.display_name
    assert_text @secondary_contact.display_name

    assert_text "Current tasks and deals"
    assert_text @deal.name
    assert_text "Company kickoff"
    assert_text "Deal follow-up"
    assert_text "Product QA review"

    assert_text "Upcoming runs"
    assert_text @run.number

    assert_text "Tagged reminders"
    assert_text "Confirm forecast"
  end

  test "reminder created from a company page stays tagged to that company" do
    visit company_path(@company)
    click_link "+ Reminder"

    assert_text "Tagged to #{@company.name}"
    fill_in "Message", with: "Prep launch checklist"
    click_button "Create Reminder"

    assert_current_path company_path(@company)
    assert_text "Reminder scheduled."
    assert_text "Prep launch checklist"
  end

  private

  def sign_in_as(user)
    visit "/users/sign_in"
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button "Log in"
  end
end