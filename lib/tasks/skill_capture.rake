namespace :skill_capture do
  desc "Mine usage events for repeated workflows and draft new skill candidates now"
  task sweep: :environment do
    result = SkillCapture::WorkflowDetector.call
    result.created.each { |c| SkillCapture::DraftGenerator.call(c) }
    puts "#{result.patterns.size} repeated workflows; #{result.created.size} new candidates, #{result.updated.size} updated"
    result.patterns.each { |p| puts "  #{p.occurrences}x by #{p.user_ids.size} people: #{p.steps.join(' → ')}" }
  end

  desc "Write every published skill to DIR/<name>/SKILL.md (default: ./skills)"
  task :export, [:dir] => :environment do |_, args|
    dir = Pathname.new(args[:dir] || Rails.root.join("skills"))
    Skill.published.find_each do |s|
      puts "wrote #{SkillCapture::SkillFile.export(s, dir: dir)}"
    end
  end

  desc "Demo: script a repeated production workflow for the seeded users, then sweep (development only)"
  task simulate: :environment do
    abort "Refusing to run outside development" unless Rails.env.development?
    users = User.active.where(role: %w[ops admin]).limit(3).to_a
    abort "Seed the database first (bin/rails db:seed)" if users.empty?
    steps = %w[production_runs#create production_runs#release production_runs#start_run production_runs#complete production_runs#create_invoice]
    4.times do |i|
      user = users[i % users.size]
      session = SecureRandom.hex(12)
      steps.each_with_index do |key, j|
        UsageEvent.create!(user: user, session_key: session, workflow_key: key, http_method: "POST",
                           resource_type: "ProductionRun", occurred_at: (i + 1).days.ago + (j * 7).minutes)
      end
    end
    Rake::Task["skill_capture:sweep"].invoke
  end
end
