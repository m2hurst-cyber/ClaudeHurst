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
    Skill.published.shared.find_each do |s| # sandbox (local) skills are never exported
      puts "wrote #{Capture::SkillFile.export(s, dir: dir)}"
      write.(dir.join(s.name, "ROAD.md"), Capture::Directions.find("road:#{s.name}", viewer: nil))
      if SkillLink.where(from_node: s.name).exists? || Waypoint.exists?(key: "junction:#{s.name}")
        write.(dir.join(s.name, "INTERSECTION.md"), Capture::Directions.find("junction:#{s.name}", viewer: nil))
      end
    end
    SkillLink.distinct.pluck(:from_node, :to_node).each do |a, b|
      place = Capture::Directions.find(Waypoint.key_for("handoff", a, b), viewer: nil)
      write.(dir.join("handoffs", "#{a}--#{b}.md"), place)
    rescue Capture::Directions::NotFound
      next
    end
  end

  namespace :rest_stops do
    desc "Check every rest stop against its checksum and its disk mirror; repair what's missing (DRY_RUN=1 to only report)"
    task verify: :environment do
      report = Capture::RestStops.verify!(repair: ENV["DRY_RUN"] != "1")
      puts "Rest stops in #{Capture::Config.rest_stop_dir}: #{report.map { |k, v| "#{k}=#{v}" }.join(' ')}"
      exit(1) if report[:unrecoverable].positive?
    end

    desc "Take a rest stop of every published skill that changed since its last one"
    task sweep: :environment do
      puts "#{Capture::RestStops.sweep!} new rest stops"
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
      "review-nda" => ["legal", "Review an NDA", [step.("word", "Check the NDA against the standard"), step.("word", "Flag non-standard terms")]],
      "variance-analysis" => ["finance", "Run the monthly variance analysis", [step.("excel", "Compute variance by cost centre"), step.("excel", "Run a regression on cost drivers"), step.("excel", "Chart the top variances")]],
      "board-deck-design" => ["finance", "Design the board deck", [step.("powerpoint", "Apply the board slide template"), step.("powerpoint", "Lay out charts and brand colours")]],
      # Bridge skills: they carry work from one app into another.
      "charts-to-ppt-appendix" => ["finance", "Collect workbook charts into a PowerPoint appendix", [step.("excel", "Open the variance workbook and select every chart"), step.("excel", "Copy the charts"), step.("powerpoint", "Add appendix slides from the template"), step.("powerpoint", "Paste one chart per slide and note its source")]],
      "charts-to-word-report" => ["finance", "Turn workbook charts into a Word report", [step.("excel", "Select the key charts in the workbook"), step.("excel", "Copy the charts as pictures"), step.("word", "Start from the monthly report template"), step.("word", "Paste charts under Key figures and write the summary")]]
    }
    created = {}
    skills.each do |name, (area, title, steps)|
      next created[name] = Skill.current(name) if Skill.current(name)
      steps.each { |key, label| ActionDefinition.find_or_create_by!(key: key) { |d| d.label = label; d.domain = area } }
      lower = ->(t) { t.sub(/\A./) { |ch| ch.downcase } }
      c = SkillCandidate.create!(signature: "demo:#{name}", steps: steps.map(&:first), domain: area, origin: "manual", status: "detected",
                                 occurrence_count: 4, distinct_actor_count: 3, draft_title: title,
                                 draft_description: "Walks through how the #{area} team does it: #{steps.map { |_, l| lower.(l) }.join('; ')}.",
                                 contributors: [{ "key" => "demo-1", "name" => "Analyst A" }, { "key" => "demo-2", "name" => "Analyst B" }],
                                 first_seen_at: 20.days.ago, last_seen_at: 2.days.ago)
      Capture::DraftGenerator.call(c, drafter: ->(x) { Capture::TemplateDrafter.call(x) }) # the same Agent Skills formatting as real drafts
      c.update!(draft_name: name, status: "drafted")
      created[name] = Capture::Publisher.publish!(c, reviewer: admin)
    end
    # An improvement and a branch
    if Skill.where(name: "reconcile-bank-statement").count == 1
      Capture::Publisher.revise!(created["reconcile-bank-statement"], editor: admin, attrs: { body: created["reconcile-bank-statement"].body.sub("## Outputs", "4. Sign off the reconciliation.\n\n## Outputs"), change_note: "Added sign-off" })
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
      [%w[post-month-end-accruals variance-analysis month-end-close-pack board-deck-design], 5],
      [%w[variance-analysis charts-to-ppt-appendix board-deck-design], 4],
      [%w[variance-analysis charts-to-word-report], 3],
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
    # Journeys are relative to today with fixed demo actors, so a second run would overlap the first
    # and invent backward roads. Seed them once; delete the "Demo journeys" source's events to re-seed.
    if src.usage_events.exists?
      puts "Demo journeys already seeded; keeping them."
    else
      events.each_slice(400) { |b| Capture::Ingestor.call(src, b) }
    end
    n = Capture::ChainDetector.call.size
    result = Capture::Congestion.call
    Capture::Bounties.sweep(result)
    # Classify everything (rules, or Claude if configured), then show two classifications a person confirmed.
    Capture::Taxonomy.ensure_defaults!
    Skill.published.find_each { |s| Capture::Classifier.apply!(s) }
    { "prepare-contract" => "legal/contracts", "month-end-close-pack" => "data-analysis/reporting" }.each do |name, path|
      SkillClassification.for(name)&.update!(field: Field.find_by(path: path), source: "user", confirmed: true, confidence: nil, rationale: nil, updated_by: admin)
    end

    # Resource library: callable folders with real Office files, attached to the skills that use them.
    folder = lambda do |path, audience = "firm", areas = []|
      parent = nil
      path.split("/").each_with_index do |name, i|
        last = i == path.count("/")
        parent = ResourceFolder.find_or_create_by!(path: [parent&.path, name.parameterize].compact.join("/")) do |f|
          f.assign_attributes(name: name, parent: parent, audience: last ? audience : "firm", areas: last ? areas : [], created_by: admin)
        end
      end
      parent
    end
    files = Rails.root.join("db/demo/resources")
    types = { "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
              "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation" }
    library = {
      ["Legal/Templates", "firm", []] => { "Customer contract template" => "customer-contract-template.docx", "Mutual NDA template" => "mutual-nda-template.docx" },
      ["Finance/Workbooks", "restricted", ["finance"]] => { "Bank reconciliation workbook" => "bank-reconciliation-workbook.xlsx", "Variance analysis workbook" => "variance-analysis-workbook.xlsx" },
      ["Finance/Reports", "firm", []] => { "Monthly report template" => "monthly-report-template.docx" },
      ["Design/Brand", "firm", []] => { "Hex key worksheet" => "hex-key-worksheet.xlsx" },
      ["Design/Templates", "firm", []] => { "Board deck template" => "board-deck-template.pptx", "Appendix slides template" => "appendix-slides-template.pptx" }
    }
    descriptions = {
      "Hex key worksheet" => "Brand colors by hex code, with the Office theme slot, chart series order and how to apply each color in Excel, PowerPoint and Word. Use it whenever a skill formats, charts or designs."
    }
    # Earlier demo data kept the hex key worksheet in Finance/Workbooks; it's a firm-wide brand file.
    if (old = Resource.joins(:folder).find_by(slug: "hex-key-worksheet", resource_folders: { path: "finance/workbooks" }))
      old.skill_resources.destroy_all
      old.destroy!
    end
    by_name = {}
    library.each do |(path, audience, areas), items|
      f = folder.(path, audience, areas)
      items.each do |name, file|
        by_name[name] = f.resources.find_or_initialize_by(slug: name.parameterize).tap do |r|
          next if r.persisted?
          r.name = name
          r.description = descriptions[name]
          r.uploaded_by = admin
          File.open(files.join(file), "rb") { |io| r.attach_file(io, filename: file, content_type: types[File.extname(file).delete(".")]) }
          r.save!
        end
      end
    end
    {
      "prepare-contract" => ["Customer contract template"], "redline-contract" => ["Customer contract template"],
      "review-nda" => ["Mutual NDA template"],
      "reconcile-bank-statement" => ["Bank reconciliation workbook"],
      "reconcile-multi-currency-bank" => ["Bank reconciliation workbook"],
      "variance-analysis" => ["Variance analysis workbook", "Hex key worksheet"],
      "charts-to-ppt-appendix" => ["Variance analysis workbook", "Appendix slides template", "Hex key worksheet"],
      "charts-to-word-report" => ["Variance analysis workbook", "Monthly report template", "Hex key worksheet"],
      "board-deck-design" => ["Board deck template", "Hex key worksheet"],
      "build-quote-deck" => ["Hex key worksheet"]
    }.each do |skill, names|
      names.each { |n| SkillResource.find_or_create_by!(skill_name: skill, resource: by_name.fetch(n)) { |sr| sr.added_by = admin } }
    end

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

    # Stages: most of the network is firm-wide; the FX branch and NDA review are still in the
    # sandbox; the trial-balance export has been promoted to market.
    Skill.published.update_all(stage: "firm", stage_changed_at: 30.days.ago)
    Skill.published.where(name: %w[reconcile-multi-currency-bank review-nda]).update_all(stage: "local", stage_changed_at: 5.days.ago)
    Skill.published.where(name: "export-trial-balance").update_all(stage: "market", license: "CC-BY-4.0")
    # Votes: inactive placeholder voters (they can't sign in) so the comparison has data.
    voters = 4.times.map do |i|
      User.find_or_create_by!(email: "demo-voter-#{i + 1}@example.invalid") do |u|
        u.assign_attributes(name: "Demo voter #{i + 1}", role: "member", domains: ["finance"], active: false, password: SecureRandom.hex(24))
      end
    end
    { "reconcile-multi-currency-bank" => [1, 1, 1, 1], "reconcile-bank-statement" => [1, -1, 1, -1], "post-month-end-accruals" => [1, 1, -1] }.each do |name, values|
      values.each_with_index { |v, i| SkillVote.find_or_create_by!(user: voters[i], skill_name: name) { |sv| sv.value = v; sv.comment = ("Handles FX without a separate sheet" if name.include?("multi") && i.zero?) } }
    end
    # Rest stops: a first snapshot of every skill, plus a hand-made one before a rebrand.
    Capture::RestStops.sweep!
    deck = Skill.current("board-deck-design")
    if deck.version == 1
      Capture::RestStops.capture!(deck, reason: "manual", kind: "manual", user: admin, label: "Before the brand refresh")
      Capture::Publisher.revise!(deck, editor: admin, attrs: {
        body: deck.body.sub("## Outputs", "3. Set the theme colors from the hex key worksheet before laying out slides: titles in Navy (#1F3A5F), charts in Accent 1–6 order.\n\n## Outputs"),
        change_note: "Brand refresh: theme colors from the hex key"
      })
    end

    # Save / extend / branch prompts: each admin and reviewer has, in their own add-in, (a) finished the
    # appendix skill and then applied the brand colors and added a sources slide, three times, and
    # (b) reconciled the bank with auto-match rules instead of matching by hand, twice.
    extra = { "powerpoint.step:apply-brand-colors-from-the-hex-key" => "Apply brand colors from the hex key",
              "powerpoint.step:add-a-sources-slide" => "Add a sources slide",
              "excel.step:run-auto-match-rules" => "Run auto-match rules" }
    extra.each { |k, l| ActionDefinition.find_or_create_by!(key: k) { |d| d.label = l } }
    appendix = Array(Skill.current("charts-to-ppt-appendix").source["workflow"])
    recon = Array(Skill.current("reconcile-bank-statement").source["workflow"])
    office = Source.for_office_host("PowerPoint")
    User.active.where(role: %w[admin reviewer]).find_each do |u|
      next if u.skill_prompts.exists?
      run = ->(steps, at) { steps.each_with_index { |k, i| UsageEvent.create!(source: office, actor_key: u.actor_key, actor_name: u.name, session_key: "demo-#{SecureRandom.hex(4)}", action_key: k, occurred_at: at + i.minutes) } }
      fix_session = ->(at) { UsageEvent.where(actor_key: u.actor_key, occurred_at: at..(at + 1.hour)).update_all(session_key: "demo-#{at.to_i}") }
      3.times { |i| at = (i + 1).days.ago; run.(appendix + extra.keys.first(2), at); fix_session.(at) }
      2.times { |i| at = (i + 1).days.ago - 3.hours; run.([recon[0], "excel.step:run-auto-match-rules", recon[2]], at); fix_session.(at) }
      Capture::Prompter.call(u)
    end

    fx = Skill.current("reconcile-multi-currency-bank")
    unless Promotion.exists?(skill_name: fx.name)
      Promotion.create!(skill_name: fx.name, skill_version: fx.version, from_stage: "local", to_stage: "firm", requested_by: voters.first,
                        pitch: "Every entity with foreign-currency accounts uses this; it removes the manual revaluation sheet.",
                        checks: Capture::Gates.for(fx, "firm").map(&:to_h))
    end

    result.metrics.select(&:priced?).sort_by { |m| -m.congestion_index }.each do |m|
      puts format("  %-32s index %4.2f  %-12s %s", m.name, m.congestion_index, m.tier, m.price.to_s("F"))
    end
    puts "Demo ready: #{Skill.published.count} skills, #{n} roads, #{Bounty.active.count} bounties. Open /map (Traffic) and /bounties."
  end
end
