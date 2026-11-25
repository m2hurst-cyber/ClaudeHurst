require "test_helper"

class SetupReadinessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { @admin = make_user(role: "admin") }

  def with_env(vars)
    previous = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # ---------- mail ----------

  test "mail says what is missing, in words and in variable names" do
    with_env("SMTP_ADDRESS" => nil, "SMTP_USER_NAME" => nil, "SMTP_PASSWORD" => nil, "MAIL_FROM" => nil) do
      refute Capture::MailCheck.configured?
      assert_match(/cannot reach anyone/, Capture::MailCheck.summary)
      assert_match(/SMTP_ADDRESS/, Capture::MailCheck.summary)
    end
  end

  test "mail is satisfied when all four are set" do
    with_env("SMTP_ADDRESS" => "smtp.example.com", "SMTP_USER_NAME" => "u", "SMTP_PASSWORD" => "p", "MAIL_FROM" => "no-reply@firm.test") do
      assert Capture::MailCheck.configured?
      assert_match(/no-reply@firm\.test/, Capture::MailCheck.summary)
    end
  end

  test "an unconfigured installation does not pretend mail works" do
    with_env("SMTP_ADDRESS" => nil, "SMTP_USER_NAME" => nil, "SMTP_PASSWORD" => nil, "MAIL_FROM" => nil) do
      check = Capture::Readiness.mail
      assert check.blocking?, "a password reset nobody receives is a blocking failure, not a warning"
      assert_match(/the person simply waits/, check.detail)
    end
  end

  test "the reset sender is never a plausible-looking address nobody owns" do
    assert_match(/not-configured@invalid\z/, Devise.mailer_sender) if ENV["MAIL_FROM"].blank?
  end

  # ---------- the rest of the checks ----------

  test "a missing model key degrades rather than blocks" do
    check = Capture::Readiness.model
    refute check.blocking?, "the system still works on rules; it is blunter"
    assert_equal :degraded, check.state
    assert_equal "ANTHROPIC_API_KEY", check.fix
  end

  test "the add-in check wants https and a fixed id" do
    with_env("SKILL_CAPTURE_PUBLIC_URL" => nil, "SKILL_CAPTURE_ADDIN_ID" => nil) do
      assert_match(/SKILL_CAPTURE_PUBLIC_URL/, Capture::Readiness.addin.fix)
      assert_match(/second add-in/, Capture::Readiness.addin.detail)
    end
    with_env("SKILL_CAPTURE_PUBLIC_URL" => "https://skills.firm.test", "SKILL_CAPTURE_ADDIN_ID" => SecureRandom.uuid) do
      assert Capture::Readiness.addin.ok?
    end
    with_env("SKILL_CAPTURE_PUBLIC_URL" => "http://insecure.test", "SKILL_CAPTURE_ADDIN_ID" => SecureRandom.uuid) do
      refute Capture::Readiness.addin.ok?, "Office will not load an add-in over plain http"
    end
  end

  # ---------- what each provider needs ----------

  test "every provider says what registering it takes, and where" do
    Capture::Integrations.all.each do |p|
      assert p.registration.present? && p.registration.length > 30, "#{p.key} does not say what registering it involves"
      assert p.portal.to_s.start_with?("https://"), "#{p.key} has no portal to get keys from"
      assert p.credentials.any?, "#{p.key} declares no credentials"
      p.credentials.each do |c|
        assert c["env"].to_s.match?(/\A[A-Z][A-Z0-9_]+\z/), "#{p.key}: #{c['env']} is not an env var name"
        assert c["what"].present?, "#{p.key}: #{c['env']} does not say what it is"
      end
    end
  end

  test "credential names do not collide between providers" do
    names = Capture::Integrations.all.flat_map(&:env_names)
    assert_equal names.size, names.uniq.size, "two providers want the same variable: #{names.tally.select { |_, n| n > 1 }.keys}"
  end

  test "the four that cannot be registered once are marked as such" do
    per_tenant = Capture::Integrations.all.select(&:per_tenant?).map(&:key)
    assert_equal %w[netsuite sage-intacct sap-s4hana workday].sort, per_tenant.sort,
                 "these create credentials inside each customer's own tenant, so they cannot be set here once"
  end

  test "a provider is ready only when all of its keys are present" do
    xero = Capture::Integrations.find("xero")
    with_env("XERO_CLIENT_ID" => "id", "XERO_CLIENT_SECRET" => nil) do
      refute xero.ready?
      assert_equal ["XERO_CLIENT_SECRET"], xero.missing_credentials.map { |c| c["env"] }
    end
    with_env("XERO_CLIENT_ID" => "id", "XERO_CLIENT_SECRET" => "secret") { assert xero.ready? }
  end

  test "QuickBooks reads its API details from its own manifest now" do
    provider = Capture::Integrations.find("quickbooks")
    assert provider.api.present?, "the API config lives with the rest of the provider's description"
    assert_equal provider.api["token_url"], Capture::Quickbooks::Config.token_url
    refute provider.endpoints_verified?
    refute Capture::Quickbooks::Config.verified?
  end

  test "an unverified provider is shown as not fully set up even with its keys" do
    with_env("QUICKBOOKS_CLIENT_ID" => "a", "QUICKBOOKS_CLIENT_SECRET" => "b",
             "QUICKBOOKS_REDIRECT_URI" => "https://x.test/cb", "QUICKBOOKS_WEBHOOK_VERIFIER" => "v") do
      check = Capture::Readiness.integrations.find { |c| c.key == "integration:quickbooks" }
      assert_equal :degraded, check.state
      assert_match(/not been checked/, check.detail)
    end
  end

  # ---------- the page ----------

  test "an admin sees what is blocking and what each system needs" do
    sign_in @admin
    get admin_setup_path
    assert_response :success
    assert_match(/Mail/, response.body)
    assert_match(/Register once/, response.body)
    assert_match(/Per customer tenant/, response.body)
    assert_match(/SALESFORCE_CLIENT_ID/, response.body)
    assert_match(/no app to register/, response.body)
  end

  test "setup is an admin's business" do
    sign_in make_user
    get admin_setup_path
    assert_response :redirect
  end
end
