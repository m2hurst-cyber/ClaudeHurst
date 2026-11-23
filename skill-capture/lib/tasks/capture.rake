namespace :users do
  desc "Create a user and print a one-time password: bin/rails users:create EMAIL=a@b.org NAME='A B' ROLE=admin [DOMAINS=finance,ops]"
  task create: :environment do
    email = ENV.fetch("EMAIL") { abort "EMAIL is required" }
    password = SecureRandom.base58(16)
    user = User.create!(email: email, name: ENV.fetch("NAME", email.split("@").first), role: ENV.fetch("ROLE", "member"),
                        domains: ENV.fetch("DOMAINS", "").split(","), password: password, password_confirmation: password)
    puts "Created #{user.role} #{user.email}"
    puts "One-time password: #{password}"
  end
end

namespace :capture do
  desc "Detect repeated workflows and draft new candidates now"
  task sweep: :environment do
    result = Capture::WorkflowDetector.call
    result.created.each { |c| Capture::DraftGenerator.call(c) }
    puts "#{result.patterns.size} repeated workflows; #{result.created.size} new, #{result.updated.size} updated"
    result.patterns.each { |p| puts "  #{p.occurrences}x by #{p.actors.size}: #{p.steps.join(' → ')}" }
    chains = Capture::ChainDetector.call
    puts "#{chains.size} skill-to-skill transitions observed"
    result = Capture::Congestion.call
    Capture::Bounties.sweep(result)
    priced = result.metrics.select(&:priced?)
    puts "#{priced.size} skills priced; #{Bounty.active.count} active bounties"
  end

  desc "Write the map to DIR (default ./skill-repo): <name>/SKILL.md, <name>/ROAD.md, <name>/INTERSECTION.md, handoffs/<from>--<to>.md"
  task :export, [:dir] => :environment do |_, args|
    dir = Pathname.new(args[:dir] || Rails.root.join("skill-repo"))
    write = lambda do |path, place|
      FileUtils.mkdir_p(path.dirname)
      front = { "key" => place.key, "kind" => place.kind, "title" => place.title, "written" => place.written, "version" => place.version }.compact
      File.write(path, "#{front.to_yaml}---\n\n#{place.body.strip}\n")
      puts "wrote #{path}"
    end
    Skill.published.find_each do |s|
      puts "wrote #{Capture::SkillFile.export(s, dir: dir)}"
      write.(dir.join(s.name, "ROAD.md"), Capture::Directions.find("road:#{s.name}"))
      if SkillLink.where(from_node: s.name).exists? || Waypoint.exists?(key: "junction:#{s.name}")
        write.(dir.join(s.name, "INTERSECTION.md"), Capture::Directions.find("junction:#{s.name}"))
      end
    end
    SkillLink.distinct.pluck(:from_node, :to_node).each do |a, b|
      place = Capture::Directions.find(Waypoint.key_for("handoff", a, b))
      write.(dir.join("handoffs", "#{a}--#{b}.md"), place)
    rescue Capture::Directions::NotFound
      next
    end
  end

  desc "Development demo: published skills that chain into end-to-end journeys, with a branch, an improvement and unpaved roads"
  task demo: :environment do
    abort "Development only" unless Rails.env.development?
    admin = User.find_by(role: "admin") or abort("Create an admin first: bin/rails users:create ROLE=admin ...")

    step = ->(host, text) { ["#{host}.step:#{text.parameterize}", text] }
    skills = {
      "export-trial-balance" => ["finance", "Export the trial balance", [step.("excel", "Refresh the GL extract"), step.("excel", "Export the trial balance by entity")]],
      "reconcile-bank-statement" => ["finance", "Reconcile the bank statement", [step.("excel", "Import the bank statement"), step.("excel", "Match payments to ledger lines"), step.("excel", "Investigate unmatched items")]],
      "post-month-end-accruals" => ["finance", "Post month-end accruals", [step.("excel", "List open purchase orders"), step.("excel", "Calculate accruals"), step.("excel", "Load the accrual journal")]],
      "month-end-close-pack" => ["finance", "Build the month-end close pack", [step.("powerpoint", "Update KPI slides"), step.("powerpoint", "Add variance commentary")]],
      "build-quote-deck" => ["sales", "Build a quote deck", [step.("powerpoint", "Duplicate the quote template"), step.("powerpoint", "Fill in pricing tables")]],
      "write-proposal" => ["sales", "Write the proposal", [step.("word", "Start from the proposal template"), step.("word", "Insert scope and pricing")]],
      "prepare-contract" => ["sales", "Prepare the customer contract", [step.("word", "Generate the contract from the template"), step.("word", "Fill in commercial terms")]],
      "redline-contract" => ["legal", "Redline a customer contract", [step.("word", "Compare against the clause library"), step.("word", "Mark up deviations")]],
      "legal-sign-off" => ["legal", "Get legal sign-off", [step.("word", "Summarize deviations for counsel"), step.("word", "Record the approval")]],
      "review-nda" => ["legal", "Review an NDA", [step.("word", "Check the NDA against the standard"), step.("word", "Flag non-standard terms")]]
    }
    created = {}
    skills.each do |name, (area, title, steps)|
      next created[name] = Skill.current(name) if Skill.current(name)
      steps.each { |key, label| ActionDefinition.find_or_create_by!(key: key) { |d| d.label = label; d.domain = area } }
      c = SkillCandidate.create!(signature: "demo:#{name}", steps: steps.map(&:first), domain: area, origin: "detected", status: "drafted",
                                 occurrence_count: 4, distinct_actor_count: 3, draft_name: name, draft_title: title,
                                 draft_description: "#{title} (demo skill).", draft_body: "# #{title}\n\n" + steps.each_with_index.map { |(_, l), i| "#{i + 1}. #{l}" }.join("\n"),
                                 contributors: [{ "key" => "demo-1", "name" => "Analyst A" }, { "key" => "demo-2", "name" => "Analyst B" }],
                                 first_seen_at: 20.days.ago, last_seen_at: 2.days.ago)
      created[name] = Capture::Publisher.publish!(c, reviewer: admin)
    end
    # An improvement and a branch
    if Skill.where(name: "reconcile-bank-statement").count == 1
      Capture::Publisher.revise!(created["reconcile-bank-statement"], editor: admin, attrs: { body: created["reconcile-bank-statement"].body + "\n4. Sign off the reconciliation", change_note: "Added sign-off" })
      Capture::Publisher.revise!(Skill.current("reconcile-bank-statement"), editor: admin,
                                 attrs: { name: "reconcile-multi-currency-bank", title: "Reconcile a multi-currency bank account" })
      # A real variant differs in its steps; give the demo fork its own currency step.
      fork = Skill.current("reconcile-multi-currency-bank")
      key, label = step.("excel", "Revalue balances at month-end rates")
      ActionDefinition.find_or_create_by!(key: key) { |d| d.label = label; d.domain = "finance" }
      fork.update!(source: fork.source.merge("workflow" => fork.source["workflow"].insert(1, key)))
    end
    # Unpaved: workflows seen but not yet reviewed
    [["finance", "Chase late expense reports", %w[outlook.step:list-late-claims excel.step:email-reminders]],
     ["legal", "Renew a supplier contract", %w[word.step:check-renewal-date word.step:update-term-dates]]].each do |area, title, steps|
      SkillCandidate.find_or_create_by!(signature: "demo:#{title.parameterize}") do |c|
        c.assign_attributes(steps: steps, domain: area, origin: "detected", status: "detected", draft_title: title, occurrence_count: 3, distinct_actor_count: 2)
      end
    end

    # End-to-end journeys (traffic). The integration source stands in for the add-in here.
    # Baseline: 2 months at normal speed. Last week: legal redlines queue up (jammed),
    # accruals slow down (heavy), the close pack is a little slow.
    src = Source.find_by(name: "Demo journeys") || Source.issue!(name: "Demo journeys", kind: "integration").first
    journeys = [
      [%w[export-trial-balance reconcile-bank-statement post-month-end-accruals month-end-close-pack], 7],
      [%w[export-trial-balance reconcile-multi-currency-bank post-month-end-accruals], 3],
      [%w[build-quote-deck write-proposal prepare-contract redline-contract legal-sign-off], 6],
      [%w[build-quote-deck write-proposal prepare-contract], 2],
      [%w[review-nda legal-sign-off], 5]
    ]
    slowdown = { "redline-contract" => 6.0, "post-month-end-accruals" => 2.2, "month-end-close-pack" => 1.5 }
    events = []
    emit = lambda do |chain, actor, start, recent|
      t = start
      chain.each do |name|
        factor = recent ? slowdown.fetch(name, 1.0) : 1.0
        t += (30.minutes * factor)                       # wait before this skill (handoff)
        steps = Array(Skill.current(name)&.source&.dig("workflow"))
        steps.each_with_index do |key, m|
          events << { action: key, actor: { id: actor }, session: "#{actor}-#{name}", occurred_at: (t + m * 8.minutes * factor).utc.iso8601 }
        end
        t += (steps.size - 1) * 8.minutes * factor
      end
    end
    journeys.each_with_index do |(chain, recent_times), j|
      8.times { |i| emit.(chain, "base-#{j}-#{i}", (20 + i * 5).days.ago - j.hours, false) }
      recent_times.times { |i| emit.(chain, "now-#{j}-#{i}", (i % 6 + 1).days.ago - j.hours - i.minutes * 7, true) }
    end
    events.each_slice(400) { |b| Capture::Ingestor.call(src, b) }
    n = Capture::ChainDetector.call.size
    result = Capture::Congestion.call
    Capture::Bounties.sweep(result)
    # Written agent directions for a few places (the rest stay generated)
    {
      "junction:export-trial-balance" => <<~MD,
        # Intersection after Export the trial balance

        You have the trial balance for every entity. Pick the reconciliation road per bank account:

        - **If the account holds any foreign-currency balance**, take **Reconcile a multi-currency bank account** (`reconcile-multi-currency-bank`). Rates come from the treasury rate sheet dated the last business day of the month.
        - **Otherwise**, take **Reconcile the bank statement** (`reconcile-bank-statement`).
        - Reconcile every account before moving on to accruals; don't split the close across roads.

        If an account is new or closed this month, stop and ask the finance reviewer.
      MD
      "handoff:redline-contract>legal-sign-off" => <<~MD,
        # Handoff: Redline → Legal sign-off

        This is the slowest handoff on the map (contracts wait days for counsel).

        ## Hand over
        - The redlined Word file **and** a one-paragraph summary of every deviation from the clause library.
        - The customer's requested signature date.

        ## Notify
        - Post in the legal intake queue, not by email to a person. Tag priority **high** only if signature is due within 3 business days.

        ## Don't
        - Don't send partial redlines; counsel reviews the whole document once.
      MD
      "road:redline-contract" => <<~MD
        # Road: Redline a customer contract

        ## Tools
        - Word with Track Changes on; the clause library (SharePoint › Legal › Clauses).

        ## Guardrails
        - Never accept the customer's limitation-of-liability changes yourself; mark them for counsel.
        - Keep comments factual: quote the standard clause next to each deviation.

        ## Done when
        - Every deviation is marked and listed in the summary for the handoff.
      MD
    }.each do |key, body|
      place = Capture::Directions.find(key)
      Capture::Directions.save!(place, body: body, user: admin, note: "Demo directions") unless place.written
    end

    result.metrics.select(&:priced?).sort_by { |m| -m.congestion_index }.each do |m|
      puts format("  %-32s index %4.2f  %-12s %s", m.name, m.congestion_index, m.tier, m.price.to_s("F"))
    end
    puts "Demo ready: #{Skill.published.count} skills, #{n} roads, #{Bounty.active.count} bounties. Open /map (Traffic) and /bounties."
  end
end
