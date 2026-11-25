# The front door: one question, answered across everything — and when there's no question, the work
# that is actually waiting on you.
class FindController < ApplicationController
  def show
    @result = Capture::Find.call(params[:q], viewer: current_user)
    @centre = params[:centre].presence || (@result[:best]&.group == "skills" ? @result[:best].key : nil)
    @map = @centre ? Capture::Find.neighbourhood(@centre, current_user) : nil
    @desk = desk unless @result[:empty] && params[:q].present?
    AuditLog.record("find.search", user: current_user, query: @result[:query], hits: @result[:total]) if @result[:total].to_i.positive?
  end

  private

  # What is waiting on you, in the order you would want to be asked about it.
  def desk
    runs = FlowRun.where(status: "running").includes(:flow).order(updated_at: :desc).limit(50)
    {
      tasks: runs.select { |r| r.doer?(user: current_user) }.first(5).map do |r|
        { title: r.current["title"], flow: r.flow.name, app: r.current["app"], url: flow_run_path(r),
          split: Flow.split?(r.current), engine: r.current["engine"] }
      end,
      jobs: PlaybookRun.where(user: current_user).or(PlaybookRun.where(reviewer: current_user)).where(status: "open")
                       .order(updated_at: :desc).limit(5).map do |r|
        name = r.route.map { |s| s[:name] }.find { |n| r.legs.dig(n, "status") != "verified" }
        state = name && r.legs[name]
        { reference: r.reference, called: r.playbook.wording["run"], playbook: r.playbook.title, url: playbook_run_path(r),
          verified: r.legs.count { |_, v| v["status"] == "verified" }, of: r.legs.size,
          next: name && (Skill.current(name)&.title || name),
          blocking: Array(state&.dig("checks")).reject { |c| c["ok"] }.map { |c| c["label"] }.first(2) }
      end,
      prompts: current_user.skill_prompts.live.limit(3).map { |p| { title: p.title, url: prompts_path } },
      transfers: current_user.received_transfers.pending.limit(3).map { |t| { label: t.label, from: t.sender.name, url: transfer_path(t) } },
      reviews: (SkillCandidate.open.select { |c| c.reviewable_by?(current_user) }.first(3).map { |c| { title: c.display_title, url: skill_candidate_path(c) } } if current_user.reviewer? || current_user.admin?),
      mine: Skill.published.at_level("mine", current_user).recent.limit(4).map { |s| { title: s.title, url: skill_path(s) } }
    }.compact
  end
end
