require "test_helper"
require "rake"

class BootstrapAdminTest < ActiveSupport::TestCase
  setup do
    @task = Rake::Task["users:bootstrap"] if Rake::Task.task_defined?("users:bootstrap")
    unless @task
      Rails.application.load_tasks
      @task = Rake::Task["users:bootstrap"]
    end
    @task.reenable
  end

  def with_env(value)
    previous = ENV["SKILL_CAPTURE_BOOTSTRAP_ADMIN"]
    value.nil? ? ENV.delete("SKILL_CAPTURE_BOOTSTRAP_ADMIN") : ENV["SKILL_CAPTURE_BOOTSTRAP_ADMIN"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("SKILL_CAPTURE_BOOTSTRAP_ADMIN") : ENV["SKILL_CAPTURE_BOOTSTRAP_ADMIN"] = previous
  end

  test "an empty installation gets its first administrator, and the password is shown once" do
    assert_equal 0, User.count
    output = with_env("founder@example.org") { capture_io { @task.invoke }.first }

    user = User.sole
    assert_equal "founder@example.org", user.email
    assert_equal "admin", user.role
    assert_equal "founder", user.name, "a name is taken from the address when none is given"

    assert_match(/FIRST ADMINISTRATOR CREATED/, output)
    password = output[/Password: (\S+)/, 1]
    assert password.present?
    assert user.valid_password?(password), "the password printed has to be the password that works"
    assert_match(/only time the password is shown/, output)
  end

  test "it does nothing once anybody has an account, so it cannot become a way in later" do
    existing = make_user(role: "member")
    output = with_env("intruder@example.org") { capture_io { @task.invoke }.first }

    assert_equal [existing], User.all.to_a
    assert_match(/already has an account/, output)
    refute User.exists?(email: "intruder@example.org")
  end

  test "it is silent and harmless when nothing asked for it" do
    output = with_env(nil) { capture_io { @task.invoke }.first }
    assert_equal 0, User.count
    assert_equal "", output.strip, "a deployment that did not request this should see nothing about it"
  end

  test "the password is random each time" do
    first = with_env("a@example.org") { capture_io { @task.invoke }.first }[/Password: (\S+)/, 1]
    User.delete_all
    @task.reenable
    second = with_env("b@example.org") { capture_io { @task.invoke }.first }[/Password: (\S+)/, 1]
    refute_equal first, second
    assert_operator first.length, :>=, 16
  end
end
