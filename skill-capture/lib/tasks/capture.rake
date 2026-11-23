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

  desc "Development demo: feed the add-in's built-in Excel and Word sources with repeated workflows, then sweep"
  task demo: :environment do
    abort "Development only" unless Rails.env.development?
    flows = {
      ["Excel", "finance"] => [["excel.document.opened", nil], ["excel.worksheet.switched", nil], ["excel.rows.inserted", nil],
                               ["excel.cells.edited", nil], ["excel.formula.changed", nil], ["excel.data.sorted", nil],
                               ["excel.step:check-totals-match-the-bank-statement", "Check totals match the bank statement"]],
      ["Word", "legal"] => [["word.document.opened", nil], ["word.contentcontrol.added", nil], ["word.paragraph.changed", nil],
                            ["word.step:check-clause-library-for-current-wording", "Check the clause library for the current wording"],
                            ["word.paragraph.deleted", nil]]
    }
    labels = {
      "excel.document.opened" => "Open the workbook", "excel.worksheet.switched" => "Switch to another worksheet",
      "excel.rows.inserted" => "Insert rows", "excel.cells.edited" => "Enter or edit cell values",
      "excel.formula.changed" => "Enter or change a formula", "excel.data.sorted" => "Sort data",
      "word.document.opened" => "Open the document", "word.contentcontrol.added" => "Insert a form field (content control)",
      "word.paragraph.changed" => "Edit text", "word.paragraph.deleted" => "Delete paragraphs"
    }
    actors = [%w[demo-1 Analyst\ A], %w[demo-2 Analyst\ B], %w[demo-3 Analyst\ C]]
    flows.each_with_index do |((host, domain), steps), f|
      events = []
      4.times do |i|
        actor = actors[(i + f) % actors.size]
        steps.each_with_index do |(key, label), j|
          events << { action: key, label: label || labels[key], domain: domain, actor: { id: actor[0], name: actor[1] },
                      session: "demo-#{f}-#{i}", occurred_at: ((i + 1).days.ago + f.hours + (j * 3).minutes).utc.iso8601,
                      context: { app: host.downcase } }
        end
      end
      r = Capture::Ingestor.call(Source.for_office_host(host), events)
      puts "#{host}: ingested #{r.accepted} events"
    end
    Rake::Task["capture:sweep"].invoke
  end
end
