module CaptureHelpers
  def make_user(role: "member", domains: [], name: nil)
    User.create!(email: "#{role}-#{SecureRandom.hex(4)}@example.test", password: "pw-#{SecureRandom.hex(8)}",
                 name: name || "#{role.capitalize} #{SecureRandom.hex(2)}", role: role, domains: domains)
  end

  def make_source(name: "Test collector")
    Source.issue!(name: name, kind: "integration")
  end

  # Scripted workflow written straight into the event stream, one step per minute.
  def perform_workflow(source, actor, steps, start: 3.hours.ago, session: SecureRandom.hex(6), domain: nil, spacing: 1.minute)
    steps.each_with_index do |key, i|
      UsageEvent.create!(source: source, actor_key: actor, actor_name: "Person #{actor}", session_key: session,
                         action_key: key, domain: domain, occurred_at: start + i * spacing)
    end
  end

  def drafted_candidate(steps: %w[crm.open:account erp.create:order erp.send:invoice], domain: "finance", name: "bill-a-new-order")
    SkillCandidate.create!(
      signature: SkillCandidate.signature_for(steps), steps: steps, domain: domain, status: "drafted",
      occurrence_count: 4, distinct_actor_count: 2,
      contributors: [{ "key" => "a-1", "name" => "Person A" }, { "key" => "a-2", "name" => "Person B" }],
      first_seen_at: 2.days.ago, last_seen_at: 1.hour.ago,
      draft_name: name, draft_title: "Bill a new order", draft_description: "Create and invoice an order.",
      draft_body: "# Bill a new order\n\n1. Open the account\n2. Create the order\n3. Send the invoice",
      draft_tags: %w[finance], draft_generator: "template", drafted_at: Time.current
    )
  end
end
