module SkillCaptureHelpers
  def make_user(role: "ops", first_name: nil)
    User.create!(email: "#{role}-#{SecureRandom.hex(4)}@test.dev", password: "password123",
                 password_confirmation: "password123", first_name: first_name || role.capitalize,
                 last_name: "Tester", role: role, active: true)
  end

  # Writes a scripted workflow into the event stream, one step per minute.
  def perform_workflow(user, steps, start: Time.current - 3.hours, session: SecureRandom.hex(6))
    steps.each_with_index do |key, i|
      UsageEvent.create!(user: user, session_key: session, workflow_key: key, http_method: "POST",
                         resource_type: key.split("#").first.classify, resource_id: rand(1..999),
                         occurred_at: start + i.minutes)
    end
  end

  def drafted_candidate(steps: %w[production_runs#release production_runs#start_run production_runs#complete], name: "run-a-production-batch", contributors: [])
    SkillCandidate.create!(
      signature: SkillCandidate.signature_for(steps), steps: steps, domain: SkillCapture::Catalog.domain_for_steps(steps),
      status: "drafted", occurrence_count: 4, distinct_user_count: contributors.size,
      contributor_ids: contributors.map(&:id), first_seen_at: 2.days.ago, last_seen_at: 1.hour.ago,
      draft_name: name, draft_title: "Run a production batch", draft_description: "Release, start and complete a run.",
      draft_body: "# Run a production batch\n\n1. Release\n2. Start\n3. Complete", draft_tags: %w[ops],
      draft_generator: "template", drafted_at: Time.current
    )
  end
end
