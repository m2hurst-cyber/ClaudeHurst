module Production
  class ReleaseRun
    def initialize(run)
      @run = run
    end

    def call
      ActiveRecord::Base.transaction do
        snapshot_bom
        plan_consumptions
        @run.release!
      end
      AuditLogger.record(user: @run.owner, action: "production_run.released", subject: @run)
      @run
    end

    private

    def snapshot_bom
      return if @run.bom_id.present?
      bom = @run.product.active_bom
      raise "Product has no active BOM" unless bom
      @run.update!(bom: bom)
    end

    def plan_consumptions
      bom = @run.bom
      return unless bom
      bom.items.includes(raw_material: :lots).each do |item|
        required = item.quantity_per_unit * @run.planned_units
        allocate_from_lots(item.raw_material, required, item.uom)
      end
    end

    def allocate_from_lots(material, required, uom)
      remaining = required.to_d
      material.lots.available.each do |lot|
        break if remaining <= 0
        take = [remaining, lot.quantity_on_hand].min
        ProductionRunConsumption.create!(
          production_run: @run,
          raw_material_lot: lot,
          quantity_planned: take,
          uom: uom
        )
        remaining -= take
      end
      raise "Insufficient raw material: #{material.name} (short #{remaining})" if remaining > 0
    end
  end
end
