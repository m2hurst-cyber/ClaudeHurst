module Capture
  # The first-run tour. Not a slideshow: every step is a real thing to do, and each one
  # ticks itself off when the person has actually done it. Nobody is asked to click
  # "next" through screens they will not remember.
  #
  # Steps appear only if they are the person's to do — reviewers get the review step,
  # admins get the settings step — so the list is never longer than their job.
  class Onboarding
    Step = Struct.new(:key, :title, :blurb, :action, :path, :done, :optional, :role, keyword_init: true) do
      def done? = done
    end

    def self.for(user) = new(user)

    def initialize(user)
      @user = user
    end

    def steps
      @steps ||= all_steps.select { |s| s.role.nil? || @user.send(:"#{s.role}?") || @user.admin? }
    end

    def done_count = steps.count(&:done?)
    def total = steps.size
    def complete? = steps.reject(&:optional).all?(&:done?)
    def percent = total.zero? ? 100 : ((done_count * 100.0) / total).round
    def next_step = steps.reject(&:done?).first
    def dismissed? = @user.tour_dismissed_at.present?
    # Worth nudging: they have not finished and have not told us to stop.
    def nudge? = !dismissed? && !complete?

    private

    def routes = Rails.application.routes.url_helpers

    def all_steps
      [
        Step.new(key: "look", title: "Find your way around",
                 blurb: "Everything starts with one box. Ask it for a skill, a client, a schedule or a job and it answers with the thing itself, plus where that thing sits in the work.",
                 action: "Open the front door", path: routes.root_path, done: @user.tour_seen_at.present?),

        Step.new(key: "addin", title: "Put the add-in in Excel",
                 blurb: "The add-in is what notices the work. Without it the system has nothing to learn from — nothing you do in Office reaches it.",
                 action: "Get the add-in", path: routes.addin_connect_path, done: addin_connected?),

        Step.new(key: "capture", title: "Capture a worksheet",
                 blurb: "Open a workbook you built and capture a sheet. It reads the formulas, works out what the sheet is doing, documents the pieces, and writes the skill from that — in that order.",
                 action: "How capture works", path: routes.help_guide_path("capture-a-worksheet"), done: WorksheetCapture.where(user_id: @user.id).exists?),

        Step.new(key: "prompt", title: "Answer your first prompt",
                 blurb: "When you repeat something often enough, you get asked whether to save it, extend an existing skill, or branch your own version. Answering — including saying no — is what teaches it your judgement.",
                 action: "See your prompts", path: routes.prompts_path, done: @user.skill_prompts.where.not(responded_at: nil).exists?),

        Step.new(key: "published", title: "Get a skill published",
                 blurb: "A draft goes to the reviewers for your area. Once published it starts in the sandbox, where only your area can see it.",
                 action: "Browse the library", path: routes.skills_path, done: published_something?),

        Step.new(key: "run", title: "Use one on real work",
                 blurb: "Start a job from a playbook, or run a flow. This is also where the cost tracking starts to mean something: anticipated against actual, per task.",
                 action: "Open the playbooks", path: routes.playbooks_path, done: ran_something?),

        Step.new(key: "share", title: "Send one to a colleague",
                 blurb: "Skills move sideways, not only upward. A transfer holds both the skill and any payment until the two cross.",
                 action: "Send a skill", path: routes.transfers_path, done: SkillTransfer.where(sender_id: @user.id).exists?, optional: true),

        Step.new(key: "review", title: "Review something", role: "reviewer",
                 blurb: "You are a reviewer for your area. Candidates wait for you: read the draft, fix the wording, then publish or send it back with a reason.",
                 action: "Open the review queue", path: routes.skill_candidates_path,
                 done: SkillCandidate.where(reviewer_id: @user.id).exists?),

        Step.new(key: "tune", title: "Set how finely work is cut", role: "admin",
                 blurb: "The granularity slider decides whether this firm collects small reusable blocks or whole end-to-end runs. It shows what each setting would have found before you choose.",
                 action: "Open protocols", path: routes.admin_protocols_path,
                 done: GranularityOverride.exists? || Protocol.where(key: "granularity").where.not(updated_at: nil).where("updated_at > created_at").exists?)
      ]
    end

    def addin_connected?
      AddinToken.where(user_id: @user.id).exists? || UsageEvent.where(actor_key: "user:#{@user.id}").exists?
    end

    def published_something?
      Skill.where(published_by_id: @user.id).exists? ||
        SkillCandidate.where(requested_by_id: @user.id, status: "approved").exists?
    end

    def ran_something?
      FlowRun.where(user_id: @user.id).exists? || PlaybookRun.where(user_id: @user.id).exists?
    end
  end
end
