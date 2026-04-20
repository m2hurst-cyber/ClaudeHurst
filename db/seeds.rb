# ClaudeHurst seed data — creates a demo-able dataset for the full verification walkthrough.
# Idempotent: safe to run multiple times.

require "securerandom"

puts "Seeding ClaudeHurst..."

# ----- Users -----
admin = User.find_or_create_by!(email: "admin@claudehurst.test") do |u|
  u.first_name = "Ada"
  u.last_name = "Hurst"
  u.role = "admin"
  u.active = true
  u.password = "password123"
  u.password_confirmation = "password123"
end

staff_specs = [
  { email: "sally.sales@claudehurst.test",   first: "Sally",  last: "Sales",   role: "sales" },
  { email: "omar.ops@claudehurst.test",      first: "Omar",   last: "Ops",     role: "ops" },
  { email: "fred.finance@claudehurst.test",  first: "Fred",   last: "Finance", role: "finance" },
  { email: "sam.sales@claudehurst.test",     first: "Sam",    last: "Sales",   role: "sales" },
  { email: "olive.ops@claudehurst.test",     first: "Olive",  last: "Ops",     role: "ops" }
]
staff = staff_specs.map do |spec|
  User.find_or_create_by!(email: spec[:email]) do |u|
    u.first_name = spec[:first]; u.last_name = spec[:last]; u.role = spec[:role]
    u.active = true; u.password = "password123"; u.password_confirmation = "password123"
  end
end
sally, omar, fred, sam, olive = staff
puts "  users: #{User.count}"

# ----- Companies (customer brands) -----
sunray = Company.find_or_create_by!(name: "Sunray Seltzer") do |c|
  c.slug = "sunray-seltzer"; c.industry = "Beverage"; c.status = "active"
  c.owner = sally; c.website = "https://sunrayseltzer.test"
  c.notes = "Flagship hard seltzer client. Onboarded 2024."
end
moonfizz = Company.find_or_create_by!(name: "Moonfizz Sodas") do |c|
  c.slug = "moonfizz-sodas"; c.industry = "Beverage"; c.status = "active"
  c.owner = sam; c.website = "https://moonfizz.test"
end
brightbrew = Company.find_or_create_by!(name: "BrightBrew Kombucha") do |c|
  c.slug = "brightbrew-kombucha"; c.industry = "Beverage"; c.status = "prospect"
  c.owner = sally; c.website = "https://brightbrew.test"
end

# ----- Contacts -----
[
  [sunray, "Priya", "Patel", "priya@sunrayseltzer.test", "Head of Ops"],
  [sunray, "Jordan", "Kim", "jordan@sunrayseltzer.test", "Procurement"],
  [moonfizz, "Alex", "Rivera", "alex@moonfizz.test", "Founder"],
  [brightbrew, "Dana", "Shaw", "dana@brightbrew.test", "COO"]
].each do |co, fn, ln, em, title|
  Contact.find_or_create_by!(email: em) do |c|
    c.company = co; c.first_name = fn; c.last_name = ln; c.title = title
    c.phone = "+1-555-#{rand(1000..9999)}"
  end
end
puts "  companies: #{Company.count}, contacts: #{Contact.count}"

# ----- Production lines -----
line_a = ProductionLine.find_or_create_by!(code: "L1") { |l| l.name = "Can Line A"; l.hourly_capacity = 3600; l.active = true }
line_b = ProductionLine.find_or_create_by!(code: "L2") { |l| l.name = "Can Line B"; l.hourly_capacity = 2400; l.active = true }
line_c = ProductionLine.find_or_create_by!(code: "L3") { |l| l.name = "Bottle Line";  l.hourly_capacity = 1800; l.active = true }

# ----- Raw materials -----
rm_specs = [
  %w[RM-CAN-12   can             each],
  %w[RM-LID-12   lid             each],
  %w[RM-TRAY-24  tray            each],
  %w[RM-CONC-CT  concentrate     L],
  %w[RM-WATER    water           L],
  %w[RM-CO2      co2             kg],
  %w[RM-LBL-SR   label           each],
  %w[RM-CONC-MF  concentrate     L],
  %w[RM-LBL-MF   label           each],
  %w[RM-BOT-32   bottle          each],
  %w[RM-CAP-32   cap             each],
  %w[RM-SUG      sugar           kg],
  %w[RM-CONC-KB  concentrate     L]
]
rm_specs.each do |code, cat, uom|
  RawMaterial.find_or_create_by!(code: code) do |r|
    r.name = code.gsub("RM-", "").tr("-", " ").titleize
    r.category = cat; r.uom = uom; r.reorder_point = 500; r.owned_by = "copacker"
  end
end
RawMaterial.kept.each do |rm|
  next if rm.lots.any?
  3.times do |i|
    rm.lots.create!(
      lot_code: "#{rm.code}-L#{Date.current.strftime('%y%m')}-#{(i+1).to_s.rjust(2,'0')}",
      received_on: (i * 14).days.ago.to_date,
      expires_on:  (12 - i).months.from_now.to_date,
      quantity_received: 50_000, quantity_on_hand: 50_000,
      supplier: ["Acme Supply", "GlobalPack Co", "Midwest Ingredients"].sample
    )
  end
end
puts "  raw materials: #{RawMaterial.count}, lots: #{RawMaterialLot.count}"

# ----- Products + BOMs -----
def upsert_product(company, sku, name, fmt)
  p = company.products.find_or_initialize_by(sku: sku)
  if p.new_record?
    p.assign_attributes(name: name, format: fmt, case_pack: 24, active: true)
    p.save!
  end
  p
end

sunray_can = upsert_product(sunray, "SR-CAN-12", "Sunray Lemon Seltzer 12oz", "12oz Sleek Can")
moon_can   = upsert_product(moonfizz, "MF-CAN-12", "Moonfizz Cola 12oz", "12oz Standard Can")
moon_btl   = upsert_product(moonfizz, "MF-BOT-32", "Moonfizz Cola 32oz", "32oz PET Bottle")
bb_kom     = upsert_product(brightbrew, "BB-KOM-16", "BrightBrew Ginger Kombucha 16oz", "16oz Can")

def upsert_bom(product, items)
  return if product.boms.any?
  bom = product.boms.build(version: 1, active: true, yield_units: 10_000)
  items.each do |code, qty, uom|
    rm = RawMaterial.find_by!(code: code)
    bom.items.build(raw_material: rm, quantity_per_unit: qty, uom: uom)
  end
  bom.save!
end

upsert_bom(sunray_can, [
  ["RM-CAN-12", 1, "each"], ["RM-LID-12", 1, "each"], ["RM-TRAY-24", 0.042, "each"],
  ["RM-CONC-CT", 0.02, "L"], ["RM-WATER", 0.34, "L"], ["RM-CO2", 0.008, "kg"], ["RM-LBL-SR", 1, "each"]
])
upsert_bom(moon_can, [
  ["RM-CAN-12", 1, "each"], ["RM-LID-12", 1, "each"], ["RM-CONC-MF", 0.03, "L"],
  ["RM-WATER", 0.32, "L"], ["RM-CO2", 0.009, "kg"], ["RM-SUG", 0.03, "kg"], ["RM-LBL-MF", 1, "each"]
])
upsert_bom(moon_btl, [
  ["RM-BOT-32", 1, "each"], ["RM-CAP-32", 1, "each"], ["RM-CONC-MF", 0.08, "L"],
  ["RM-WATER", 0.9, "L"], ["RM-SUG", 0.08, "kg"]
])
upsert_bom(bb_kom, [
  ["RM-CAN-12", 1, "each"], ["RM-LID-12", 1, "each"],
  ["RM-CONC-KB", 0.05, "L"], ["RM-WATER", 0.43, "L"]
])
puts "  products: #{Product.count}, boms: #{Bom.count}"

# ----- Deals -----
deal_specs = [
  ["Sunray Winter Launch", sunray, sally, "negotiation", 120_000_00],
  ["Moonfizz 32oz Rollout", moonfizz, sam, "proposal", 85_000_00],
  ["BrightBrew Q3 Pilot", brightbrew, sally, "qualified", 22_000_00],
  ["Sunray Variety Pack", sunray, sally, "lead", 45_000_00],
  ["Moonfizz Fountain Sampler", moonfizz, sam, "proposal", 15_000_00],
  ["Sunray Spring '26", sunray, sally, "closed_won", 260_000_00],
  ["Generic Tea RFP", brightbrew, sally, "closed_lost", 50_000_00],
  ["Brightbrew Co-pack", brightbrew, sally, "negotiation", 75_000_00]
]
deal_specs.each do |name, co, owner, stage, amt|
  Deal.find_or_create_by!(name: name, company: co) do |d|
    d.owner = owner; d.stage = stage; d.amount_cents = amt; d.currency = "USD"
    d.closed_at = Time.current if %w[closed_won closed_lost].include?(stage)
  end
end

# ----- Activities on companies -----
Company.kept.each do |co|
  next if co.activities.any?
  co.activities.create!(user: co.owner || admin, kind: "note", occurred_at: 3.days.ago,
                        body: "Intro call — great fit.")
  co.activities.create!(user: co.owner || admin, kind: "email", occurred_at: 1.day.ago,
                        body: "Sent onboarding packet.")
end

# ----- Tasks -----
if Task.none?
  Task.create!(title: "Send Sunray MSA", assignee: sally, due_on: 2.days.from_now.to_date,
               subject: sunray, priority: "high")
  Task.create!(title: "Review Moonfizz lab specs", assignee: omar, due_on: 5.days.from_now.to_date,
               subject: moonfizz, priority: "normal")
  Task.create!(title: "Chase overdue AR for BrightBrew", assignee: fred, due_on: Date.current,
               subject: brightbrew, priority: "high")
end

# ----- Contracts + pricing tiers -----
signed_contract = Contract.find_or_create_by!(title: "Sunray MSA 2026") do |ct|
  ct.company = sunray; ct.payment_terms = "net_30"
  ct.start_on = 60.days.ago.to_date; ct.end_on = 305.days.from_now.to_date
  ct.pricing_tiers.build(product: sunray_can, min_quantity: 1,     unit_price_cents: 85)
  ct.pricing_tiers.build(product: sunray_can, min_quantity: 5_000, unit_price_cents: 78)
end
signed_contract.mark_signed! if signed_contract.may_mark_signed?
signed_contract.activate!    if signed_contract.may_activate?

mf_contract = Contract.find_or_create_by!(title: "Moonfizz Supply Agreement") do |ct|
  ct.company = moonfizz; ct.payment_terms = "net_45"
  ct.start_on = 30.days.ago.to_date; ct.end_on = 335.days.from_now.to_date
  ct.pricing_tiers.build(product: moon_can, min_quantity: 1, unit_price_cents: 92)
  ct.pricing_tiers.build(product: moon_btl, min_quantity: 1, unit_price_cents: 135)
end
mf_contract.mark_signed! if mf_contract.may_mark_signed?

# ----- Production runs -----
def build_run(product, line, owner, scheduled_at, planned_units)
  ProductionRun.create!(product: product, production_line: line, owner: owner,
                        scheduled_start: scheduled_at, scheduled_end: scheduled_at + 6.hours,
                        planned_units: planned_units)
end

if ProductionRun.none?
  4.times do |i|
    r = build_run(sunray_can, line_a, omar, (30 - i*7).days.ago, 5_000)
    Production::ReleaseRun.new(r).call
    r.start_run!
    Production::CompleteRun.new(r, actual_units: 4_800 + i * 50).call
  end

  wip = build_run(moon_can, line_b, omar, 1.hour.ago, 3_000)
  Production::ReleaseRun.new(wip).call
  wip.start_run!

  build_run(moon_btl, line_c, olive, 3.days.from_now, 2_000)
  build_run(sunray_can, line_a, omar, 7.days.from_now, 6_000)
end
puts "  runs: #{ProductionRun.count}, fg lots: #{FinishedGoodLot.count}"

# ----- Invoices / Quotes -----
if Quote.none?
  q = Quote.new(company: sunray, deal: Deal.find_by(name: "Sunray Winter Launch"),
                contact: sunray.contacts.first, expires_on: 30.days.from_now.to_date)
  q.line_items.build(description: "Sunray Lemon Seltzer 12oz", quantity: 10_000, unit_price_cents: 85, tax_rate: 0.0)
  q.save!
  q.send_out!
end

completed_run = ProductionRun.where(status: "completed").first
if completed_run && Invoice.none?
  inv_paid = Invoice.new(company: sunray, contract: signed_contract, production_run: completed_run,
                         issued_on: 20.days.ago.to_date, due_on: 10.days.from_now.to_date)
  inv_paid.line_items.build(description: "Sunray Lemon Seltzer 12oz — run #{completed_run.number}",
                             quantity: completed_run.actual_units, unit_price_cents: 85, tax_rate: 0.0)
  inv_paid.save!
  inv_paid.send_out!
  inv_paid.payments.create!(amount_cents: inv_paid.total_cents, received_on: 2.days.ago.to_date,
                            method: "ach", reference: "ACH-#{SecureRandom.hex(4)}")

  inv_sent = Invoice.new(company: moonfizz, contract: mf_contract, issued_on: 5.days.ago.to_date,
                         due_on: 25.days.from_now.to_date)
  inv_sent.line_items.build(description: "Moonfizz Cola 12oz", quantity: 4_000,
                             unit_price_cents: 92, tax_rate: 0.0)
  inv_sent.save!
  inv_sent.send_out!

  inv_over = Invoice.new(company: brightbrew, issued_on: 60.days.ago.to_date,
                         due_on: 30.days.ago.to_date)
  inv_over.line_items.build(description: "BrightBrew Kombucha 16oz", quantity: 1_200,
                             unit_price_cents: 110, tax_rate: 0.0)
  inv_over.save!
  inv_over.send_out!

  inv_draft = Invoice.new(company: sunray, issued_on: Date.current, due_on: 30.days.from_now.to_date)
  inv_draft.line_items.build(description: "Variety pack prep", quantity: 500,
                             unit_price_cents: 150, tax_rate: 0.0)
  inv_draft.save!
end
puts "  quotes: #{Quote.count}, invoices: #{Invoice.count}, payments: #{Payment.count}"

# ----- Reminders -----
Reminder.find_or_create_by!(user: admin, message: "Verify reminder sweep firing end-to-end") do |r|
  r.remind_at = 2.minutes.from_now
  r.channel = "both"; r.recurrence = "none"
  r.subject = sunray
end
Reminder.find_or_create_by!(user: sally, message: "Follow up with Priya at Sunray") do |r|
  r.remind_at = 3.days.ago; r.fired_at = 3.days.ago + 5.minutes
  r.channel = "in_app"; r.recurrence = "none"; r.subject = sunray
end
Reminder.find_or_create_by!(user: sam, message: "Quarterly QBR with Moonfizz") do |r|
  r.remind_at = 5.days.from_now
  r.channel = "email"; r.recurrence = "monthly"; r.subject = moonfizz
end
puts "  reminders: #{Reminder.count}"

AuditLogger.record(user: admin, action: "seeds.loaded", subject: admin,
                   metadata: { at: Time.current.iso8601 })

puts "Done. Sign in as admin@claudehurst.test / password123"
