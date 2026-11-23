# From the map: send a skill (or a whole route) to a running add-in, a colleague's add-in,
# or an agent integration.
class SkillCommandsController < ApplicationController
  # POST /map/send  skills[]=a&skills[]=b  target=me | user:<id> | source:<id>
  def create
    names = Array(params[:skills]).map(&:to_s).uniq.first(20)
    skills = names.filter_map { |n| (s = Skill.current(n)) && s.visible_to?(current_user) && s }
    return render(json: { error: "Choose at least one skill you can see" }, status: :unprocessable_entity) if skills.empty?

    target_user, target_source = resolve_target(params[:target].to_s)
    return render(json: { error: "Unknown recipient" }, status: :unprocessable_entity) unless target_user || target_source
    if target_user && skills.any? { |s| !s.visible_to?(target_user) }
      return render(json: { error: "#{target_user.name} can't see #{skills.reject { |s| s.visible_to?(target_user) }.map(&:title).to_sentence} (sandbox)" }, status: :unprocessable_entity)
    end
    if target_source && skills.any? { |s| !s.shared? }
      return render(json: { error: "Agents only receive firm or market skills" }, status: :unprocessable_entity)
    end

    cmd = AddinCommand.create!(sender: current_user, target_user: target_user, target_source: target_source,
                               kind: skills.size > 1 ? "load_route" : "load_skill",
                               payload: { "skills" => skills.map(&:name), "titles" => skills.map(&:title), "note" => params[:note].presence }.compact)
    AuditLog.record("skill.sent", user: current_user, subject: cmd, to: cmd.target_label, skills: cmd.skill_names)
    if target_user && target_user != current_user
      Notification.create!(user: target_user, subject: cmd, kind: "skill_sent",
                           title: "#{current_user.name} sent you #{skills.size > 1 ? "a route of #{skills.size} skills" : "“#{skills.first.title}”"}. Open Skills in Office to load it.")
    end
    render json: command_json(cmd), status: :created
  end

  # GET /map/sent?ids[]=: delivery status for commands I sent
  def index
    cmds = AddinCommand.where(sender: current_user).recent.limit(20)
    cmds = cmds.where(id: params[:ids]) if params[:ids].present?
    render json: cmds.map { |c| command_json(c) }
  end

  private

  def resolve_target(t)
    case t
    when "me", "" then [current_user, nil]
    when /\Auser:(\d+)\z/ then [User.active.find_by(id: $1), nil]
    when /\Asource:(\d+)\z/ then [nil, Source.active.where.not(token_prefix: "builtin").find_by(id: $1)]
    else [nil, nil]
    end
  end

  def command_json(c)
    { id: c.id, kind: c.kind, status: c.status, to: c.target_user == current_user ? "your add-in" : c.target_label,
      skills: c.payload["titles"], delivered_to: c.delivered_to, delivered_at: c.delivered_at&.iso8601 }
  end
end
