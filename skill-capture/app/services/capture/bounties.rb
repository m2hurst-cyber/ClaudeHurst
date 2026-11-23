module Capture
  # Bounties turn congestion into an incentive.
  #
  #  open              skill reached the bounty tier; the pool is seeded with the premium of the
  #                    window's trips, then each newly received trip adds its congestion premium
  #                    (price - base) × pool share
  #  measuring         someone shipped a fix (new version, a faster branch, or a better
  #                    recorded procedure published under the same name); traffic is
  #                    measured again
  #  awaiting_approval the improvement is measured; payout = pool × share of congestion removed
  #  paid              an area reviewer (not the solver) approved; credits are paid, and any
  #                    leftover pool carries into a new bounty if the road is still jammed
  #  closed            congestion cleared on its own before any fix, or a reviewer closed it
  class Bounties
    class Error < StandardError; end

    def self.sweep(result, schedule: PricingSchedule.current, now: Time.current) = new(schedule, now).sweep(result)

    def initialize(schedule = PricingSchedule.current, now = Time.current)
      @schedule = schedule
      @now = now
    end

    def sweep(result)
      metrics = result.metrics.index_by(&:name)
      metrics.each_value { |m| open_if_congested(m, result.trips.fetch(m.name, [])) }
      Bounty.where(status: "open").find_each { |b| accrue(b, metrics[b.skill_name], result.trips.fetch(b.skill_name, [])) }
      Bounty.where(status: "measuring").find_each { |b| measure(b, metrics[b.skill_name], result.trips) }
    end

    # Called by the Publisher when a new version or a branch of a skill is published.
    def register_fix(skill, solver:, branch_of: nil)
      bounty = Bounty.find_by(skill_name: branch_of || skill.name, status: "open")
      return nil unless bounty && solver
      metric = SkillMetric.for(bounty.skill_name)
      bounty.update!(status: "measuring", fix_at: @now, fix_skill_name: skill.name, fix_version: skill.version,
                     solver: solver, baseline_index: metric&.congestion_index || bounty.opened_index)
      AuditLog.record("bounty.fix_registered", user: solver, subject: bounty, skill: skill.name, version: skill.version)
      notify_area(bounty, "A fix for “#{bounty.skill&.title || bounty.skill_name}” is being measured")
      bounty
    end

    def approve!(bounty, by:, notes: nil)
      raise Error, "Only bounties awaiting approval can be paid" unless bounty.status == "awaiting_approval"
      raise Error, "You can't approve your own bounty" if bounty.solver_id == by.id
      raise Error, "Only reviewers for this area can approve payouts" unless by.reviews?(bounty.skill&.domain)

      Bounty.transaction do
        leftover = bounty.pool - bounty.payout
        CreditEntry.create!(user: bounty.solver, bounty: bounty, amount: bounty.payout,
                            reason: "Removed #{(bounty.improvement * 100).round}% of the congestion on #{bounty.skill_name}")
        bounty.update!(status: "paid", approved_by: by, approved_at: @now, notes: notes.presence || bounty.notes)
        if leftover.positive? && @schedule.bounty_worthy?(SkillMetric.for(bounty.skill_name)&.tier)
          Bounty.create!(skill_name: bounty.skill_name, pool: leftover, accrued_until: @now,
                         opened_index: SkillMetric.for(bounty.skill_name)&.congestion_index, notes: "Carried over from bounty ##{bounty.id}")
        end
      end
      AuditLog.record("bounty.paid", user: by, subject: bounty, solver: bounty.solver&.name, amount: bounty.payout.to_s)
      Notification.create!(user: bounty.solver, subject: bounty, kind: "bounty_paid",
                           title: "You earned #{bounty.payout.to_s('F')} #{@schedule.currency} for fixing “#{bounty.skill&.title || bounty.skill_name}”",
                           url: Rails.application.routes.url_helpers.bounties_path)
      bounty
    end

    def reject!(bounty, by:, notes:)
      raise Error, "Only reviewers for this area can do that" unless by.reviews?(bounty.skill&.domain)
      raise Error, "Only a measured fix can be rejected" unless bounty.status == "awaiting_approval"
      reopen(bounty, "Fix not accepted by #{by.name}: #{notes}")
      AuditLog.record("bounty.fix_rejected", user: by, subject: bounty, notes: notes)
    end

    def close!(bounty, by:, notes:)
      raise Error, "Only admins can close a bounty" unless by.admin?
      bounty.update!(status: "closed", notes: notes)
      AuditLog.record("bounty.closed", user: by, subject: bounty, notes: notes)
    end

    private

    def open_if_congested(metric, trips)
      return unless @schedule.bounty_worthy?(metric.tier)
      return if Bounty.active_for(metric.name)
      window = trips.select { |t| t.ended_at >= @now - @schedule.window_days.days }
      bounty = Bounty.create!(skill_name: metric.name, opened_index: metric.congestion_index, accrued_until: @now,
                              pool: (@schedule.premium_for(metric.congestion_index) * window.size * @schedule.pool_share).round(2))
      AuditLog.record("bounty.opened", subject: bounty, skill: metric.name, index: metric.congestion_index, pool: bounty.pool.to_s)
      notify_area(bounty, "Bounty opened: “#{bounty.skill&.title || metric.name}” is #{@schedule.tier(metric.tier)['label'].downcase}")
    end

    def accrue(bounty, metric, trips)
      return unless metric
      if metric.tier && @schedule.rank(metric.tier).zero?
        bounty.update!(status: "closed", notes: "Traffic cleared on its own (index #{metric.congestion_index}).")
        return AuditLog.record("bounty.closed", subject: bounty, reason: "cleared")
      end
      # By arrival, not by when the trip happened, so late uploads still count (once).
      fresh = trips.count { |t| t.received_at > bounty.accrued_until && t.received_at <= @now }
      premium = metric.congestion_index ? @schedule.premium_for(metric.congestion_index) : 0
      bounty.update!(pool: (bounty.pool + premium * fresh * @schedule.pool_share).round(2), accrued_until: @now)
    end

    def measure(bounty, metric, trips_by_name)
      since = trips_by_name.values_at(bounty.skill_name, bounty.fix_skill_name).compact.flatten.uniq
                           .select { |t| t.started_at >= bounty.fix_at }
      timed_out = bounty.fix_at < @now - @schedule.measure_max_days.days
      return unless since.size >= @schedule.measure_min_trips || timed_out
      return reopen(bounty, "No traffic on the fix within #{@schedule.measure_max_days} days.") if since.empty?

      freeflow = metric&.freeflow_minutes
      return reopen(bounty, "No free-flow baseline to measure against.") unless freeflow
      result = (Congestion.median(since.map { |t| Congestion.minutes(t) }) / freeflow).round(2)
      baseline = bounty.baseline_index.to_f
      improvement = baseline > 1 ? ((baseline - result) / (baseline - 1)).clamp(0.0, 1.0).round(2) : 0.0
      if improvement.zero?
        return reopen(bounty, "The fix didn't reduce congestion (index #{baseline} → #{result}).")
      end
      bounty.update!(status: "awaiting_approval", result_index: result, improvement: improvement,
                     payout: (bounty.pool * improvement.to_d).round(2))
      AuditLog.record("bounty.measured", subject: bounty, baseline: baseline, result: result, improvement: improvement)
      notify_area(bounty, "Fix measured on “#{bounty.skill&.title || bounty.skill_name}”: #{(improvement * 100).round}% less congestion. Approve the payout.")
    end

    def reopen(bounty, note)
      bounty.update!(status: "open", fix_at: nil, fix_skill_name: nil, fix_version: nil, solver: nil,
                     baseline_index: nil, result_index: nil, improvement: nil, payout: nil, accrued_until: @now, notes: note)
      AuditLog.record("bounty.reopened", subject: bounty, notes: note)
    end

    def notify_area(bounty, title)
      domain = bounty.skill&.domain
      User.active.select { |u| u.reviews?(domain) }.each do |u|
        Notification.create!(user: u, subject: bounty, kind: "bounty", title: title,
                             url: Rails.application.routes.url_helpers.bounties_path)
      end
    end
  end
end
