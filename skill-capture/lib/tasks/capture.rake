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
  end

  desc "Write every published skill to DIR/<name>/SKILL.md (default ./skill-repo)"
  task :export, [:dir] => :environment do |_, args|
    dir = Pathname.new(args[:dir] || Rails.root.join("skill-repo"))
    Skill.published.find_each { |s| puts "wrote #{Capture::SkillFile.export(s, dir: dir)}" }
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
    src = Source.find_by(name: "Demo journeys") || Source.issue!(name: "Demo journeys", kind: "integration").first
    journeys = [
      [%w[export-trial-balance reconcile-bank-statement post-month-end-accruals month-end-close-pack], 6],
      [%w[export-trial-balance reconcile-multi-currency-bank post-month-end-accruals], 2],
      [%w[build-quote-deck write-proposal prepare-contract redline-contract legal-sign-off], 4],
      [%w[build-quote-deck write-proposal prepare-contract], 2],
      [%w[review-nda legal-sign-off], 3]
    ]
    events = []
    journeys.each_with_index do |(chain, times), j|
      times.times do |i|
        t = (i + 1).days.ago - j.hours
        chain.each_with_index do |name, k|
          Array(Skill.current(name)&.source&.dig("workflow")).each_with_index do |key, m|
            events << { action: key, actor: { id: "demo-#{j}-#{i}" }, session: "j#{j}-#{i}-#{k}", occurred_at: (t + k.hours + m.minutes).utc.iso8601 }
          end
        end
      end
    end
    events.each_slice(400) { |b| Capture::Ingestor.call(src, b) }
    n = Capture::ChainDetector.call.size
    puts "Demo ready: #{Skill.published.count} skills, #{n} roads observed. Open /map."
  end
end
