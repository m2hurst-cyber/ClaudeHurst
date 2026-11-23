module Capture
  # Measures how congested each published skill is and prices it on the demand schedule.
  #
  #   travel time  = wait before starting (after the previous skill) + time doing it
  #   free-flow    = 20th percentile travel time over the baseline (all retained activity)
  #   index        = median travel time in the pricing window / free-flow
  #   delay        = time above free-flow, summed over the window's trips
  #   price        = base price × the multiplier of the index's tier (the demand schedule)
  class Congestion
    FREEFLOW_PERCENTILE = 0.2
    MIN_FREEFLOW_MINUTES = 1.0

    Result = Struct.new(:metrics, :trips, keyword_init: true)

    def self.call(schedule: PricingSchedule.current, now: Time.current) = new(schedule, now).call

    def initialize(schedule, now)
      @schedule = schedule
      @now = now
    end

    def call
      routes = Skill.published.pluck(:name, :source).map { |n, s| [n, Array(s["workflow"])] }
      trips = TripMatcher.call(routes, since: Config.retention.ago).select { |t| t.ended_at <= @now }
      by_name = trips.group_by(&:key)
      window_start = @now - @schedule.window_days.days

      metrics = routes.map do |name, _|
        all = by_name.fetch(name, [])
        recent = all.select { |t| t.ended_at >= window_start }
        measure(name, all, recent)
      end
      SkillMetric.where.not(name: routes.map(&:first)).delete_all
      Result.new(metrics: metrics, trips: by_name)
    end

    def self.minutes(trip) = (trip.duration + trip.wait(Config.chain_gap)) / 60.0

    def self.median(values)
      return nil if values.empty?
      s = values.sort
      s.size.odd? ? s[s.size / 2] : (s[s.size / 2 - 1] + s[s.size / 2]) / 2.0
    end

    def self.percentile(values, p)
      return nil if values.empty?
      s = values.sort
      s[[(p * (s.size - 1)).round, s.size - 1].min]
    end

    private

    def measure(name, all, recent)
      totals = all.map { |t| self.class.minutes(t) }
      freeflow = totals.size >= @schedule.min_trips ? [self.class.percentile(totals, FREEFLOW_PERCENTILE), MIN_FREEFLOW_MINUTES].max : nil
      recent_totals = recent.map { |t| self.class.minutes(t) }
      median = self.class.median(recent_totals)
      index = freeflow && median && recent.size >= @schedule.min_trips ? (median / freeflow).round(2) : nil
      tier = @schedule.tier_for(index)

      m = SkillMetric.find_or_initialize_by(name: name)
      history = Array(m.history).reject { |h| h["date"] == @now.to_date.iso8601 }
      history << { "date" => @now.to_date.iso8601, "index" => index, "trips" => recent.size }
      m.update!(
        trips: recent.size,
        people: recent.map(&:actor).uniq.size,
        median_minutes: median&.round(1),
        median_wait_minutes: self.class.median(recent.map { |t| t.wait(Config.chain_gap) / 60.0 })&.round(1),
        freeflow_minutes: freeflow&.round(1),
        congestion_index: index,
        delay_hours: freeflow ? (recent_totals.sum { |v| [v - freeflow, 0].max } / 60.0).round(1) : 0,
        tier: tier&.dig("key"),
        price: index ? @schedule.price_for(index) : nil,
        history: history.last(30),
        computed_at: @now
      )
      m
    end
  end
end
