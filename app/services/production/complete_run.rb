module Production
  class CompleteRun
    def initialize(run, actual_units:)
      @run = run
      @actual_units = actual_units.to_i
    end

    def call
      ActiveRecord::Base.transaction do
        @run.update!(actual_units: @actual_units)
        consume_lots
        fg_lot = create_finished_good_lot
        create_produce_movement(fg_lot)
        @run.complete!
      end
      AuditLogger.record(user: @run.owner, action: "production_run.completed", subject: @run, metadata: { actual_units: @actual_units })
      @run
    end

    private

    def consume_lots
      @run.consumptions.includes(:raw_material_lot).each do |c|
        planned = c.quantity_planned
        c.update!(quantity_actual: planned)
        c.raw_material_lot.consume!(planned)
      end
    end

    def create_finished_good_lot
      FinishedGoodLot.create!(
        product: @run.product,
        production_run: @run,
        lot_code: "#{@run.batch_code}-#{@run.product.sku}",
        produced_on: Date.current,
        best_by_on: 1.year.from_now.to_date,
        quantity_produced: @actual_units,
        quantity_on_hand: @actual_units
      )
    end

    def create_produce_movement(lot)
      FinishedGoodMovement.create!(
        finished_good_lot: lot,
        user: @run.owner,
        reference: @run,
        kind: "produce",
        quantity: @actual_units,
        occurred_at: Time.current,
        notes: "Produced from run #{@run.number}"
      )
    end
  end
end
