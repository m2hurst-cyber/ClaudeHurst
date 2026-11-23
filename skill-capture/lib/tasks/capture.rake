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
  end

  desc "Write every published skill to DIR/<name>/SKILL.md (default ./skill-repo)"
  task :export, [:dir] => :environment do |_, args|
    dir = Pathname.new(args[:dir] || Rails.root.join("skill-repo"))
    Skill.published.find_each { |s| puts "wrote #{Capture::SkillFile.export(s, dir: dir)}" }
  end

  desc "Development demo: register a demo source and feed it scripted repeated workflows, then sweep"
  task demo: :environment do
    abort "Development only" unless Rails.env.development?
    source = Source.find_by(name: "Demo collector") || Source.issue!(name: "Demo collector", kind: "custom").first
    flows = {
      "finance" => [["excel.open:month_end_workbook", "Open the month-end close workbook"],
                    ["excel.refresh:gl_extract", "Refresh the general-ledger extract"],
                    ["excel.run_macro:reconcile_accounts", "Run the account-reconciliation macro"],
                    ["outlook.send:close_summary", "Email the close summary to the controller"]],
      "support" => [["zendesk.view:escalated_ticket", "Open the escalated ticket"],
                    ["slack.post:incident_channel", "Post the ticket in the incident channel"],
                    ["jira.create:bug", "File a bug with reproduction steps"],
                    ["zendesk.reply:customer_update", "Reply to the customer with the bug link and next update time"]]
    }
    actors = [%w[a-1001 Analyst\ A], %w[a-1002 Analyst\ B], %w[a-1003 Analyst\ C]]
    events = []
    flows.each_with_index do |(domain, steps), f|
      4.times do |i|
        actor = actors[(i + f) % actors.size]
        steps.each_with_index do |(key, label), j|
          events << { action: key, label: label, domain: domain, actor: { id: actor[0], name: actor[1] },
                      session: "demo-#{f}-#{i}", occurred_at: ((i + 1).days.ago + f.hours + (j * 4).minutes).utc.iso8601 }
        end
      end
    end
    r = Capture::Ingestor.call(source, events)
    puts "Ingested #{r.accepted} events"
    Rake::Task["capture:sweep"].invoke
  end
end
