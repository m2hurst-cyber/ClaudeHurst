module Capture
  # The checks a skill must pass to move to the next stage. Evaluated live; snapshotted on decision.
  class Gates
    Check = Struct.new(:key, :label, :passed, :detail, keyword_init: true) do
      def to_h = { "key" => key, "label" => label, "passed" => passed, "detail" => detail }
    end

    def self.for(skill, to_stage) = new(skill, to_stage).checks

    def initialize(skill, to_stage, policy: PromotionPolicy.current)
      @skill = skill
      @to = to_stage
      @policy = policy
    end

    def checks
      case @to
      when "firm" then firm_checks
      when "market" then market_checks
      else []
      end
    end

    def self.passed?(checks) = checks.all? { |c| c.respond_to?(:passed) ? c.passed : c["passed"] }

    private

    def score = SkillVote.tallies([@skill.name])[@skill.name][:score]

    def firm_checks
      trips, people = usage
      steps = Array(@skill.source["workflow"]).size
      numbered = @skill.body.to_s.scan(/^\s*\d+\.\s+\S/).size
      [
        Check.new(key: "describes_use", label: "Says what it does and when to use it",
                  passed: @skill.description.to_s.strip.length >= 40, detail: "#{@skill.description.to_s.strip.length} characters (needs 40)"),
        Check.new(key: "has_steps", label: "Has clear steps", passed: [steps, numbered].max >= 2,
                  detail: "#{[steps, numbered].max} steps"),
        Check.new(key: "has_outputs", label: "Says what it produces",
                  passed: Array(@skill.outputs).any? || @skill.body.to_s.match?(/^#+\s*(outputs|done when)/i),
                  detail: Array(@skill.outputs).any? ? Array(@skill.outputs).first(2).join("; ") : "No outputs listed"),
        Check.new(key: "used_in_sandbox", label: "Used in the sandbox",
                  passed: trips >= @policy.firm_min_trips && people >= @policy.firm_min_people,
                  detail: "#{trips} trips by #{people} #{'person'.pluralize(people)} (needs #{@policy.firm_min_trips} by #{@policy.firm_min_people})"),
        Check.new(key: "votes", label: "Colleagues vote for it", passed: score >= @policy.firm_min_score,
                  detail: "Net #{format('%+d', score)} (needs #{format('%+d', @policy.firm_min_score)})")
      ]
    end

    def market_checks
      days = @skill.stage_changed_at ? ((Time.current - @skill.stage_changed_at) / 1.day).floor : 0
      metric = SkillMetric.for(@skill.name)
      schedule = PricingSchedule.current
      max_rank = schedule.rank(@policy.market_max_tier).to_i
      rank = metric&.tier && schedule.rank(metric.tier)
      checks = [
        Check.new(key: "proven_at_firm", label: "Proven at firm level", passed: @skill.stage == "firm" && days >= @policy.market_min_days,
                  detail: "#{days} days at Firm (needs #{@policy.market_min_days})"),
        Check.new(key: "votes", label: "Strong internal support", passed: score >= @policy.market_min_score,
                  detail: "Net #{format('%+d', score)} (needs #{format('%+d', @policy.market_min_score)})"),
        Check.new(key: "traffic", label: "Runs smoothly", passed: rank.present? && rank <= max_rank,
                  detail: rank ? "#{schedule.tier(metric.tier)['label']} (no worse than #{schedule.tier(@policy.market_max_tier)['label']})" : "Not enough traffic to judge"),
        Check.new(key: "license", label: "Licensed for sharing", passed: @skill.license.present? && !@skill.license.match?(/internal|proprietary/i),
                  detail: @skill.license)
      ]
      if @policy.market_requires_directions
        checks << Check.new(key: "directions", label: "Has written agent directions", passed: Waypoint.exists?(key: "road:#{@skill.name}"),
                            detail: Waypoint.exists?(key: "road:#{@skill.name}") ? "Road directions written" : "Write the road's directions first")
      end
      checks
    end

    def usage
      trips = TripMatcher.call([[@skill.name, Array(@skill.source["workflow"])]], since: Config.retention.ago)
      [trips.size, trips.map(&:actor).uniq.size]
    end
  end
end
