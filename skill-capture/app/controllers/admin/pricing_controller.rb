module Admin
  class PricingController < BaseController
    def show
      @schedule = PricingSchedule.current
      load_chart
    end

    def update
      @schedule = PricingSchedule.current
      p = params.require(:pricing_schedule).permit(:currency, :base_price, :window_days, :min_trips, :pool_share,
                                                   :bounty_tier, :measure_min_trips, :measure_max_days,
                                                   tiers: %i[key label min_index multiplier])
      tiers = Array(p.delete(:tiers)).filter_map do |t|
        next if t[:label].blank?
        { "key" => (t[:key].presence || t[:label].parameterize), "label" => t[:label].strip,
          "min_index" => t[:min_index].to_f, "multiplier" => t[:multiplier].to_f }
      end
      if @schedule.update(p.merge(tiers: tiers))
        AuditLog.record("pricing.updated", user: current_user, tiers: tiers, base_price: @schedule.base_price.to_s)
        redirect_to admin_pricing_path, notice: "Demand schedule saved. Prices update at the next sweep."
      else
        load_chart
        render :show, status: :unprocessable_entity
      end
    end

    private

    def load_chart
      @priced = SkillMetric.where.not(congestion_index: nil).order(:congestion_index).to_a
      @titles = Skill.published.where(name: @priced.map(&:name)).pluck(:name, :title).to_h
    end
  end
end
