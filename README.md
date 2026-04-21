# Great Southern Beverages — Beverage Copacker CRM-ERP

Single-tenant, internally-hosted CRM-ERP for a mid-market beverage copacker.
Covers customer relationships, sales documents (quotes/contracts/invoices),
production with BOMs/runs/lot traceability, reminders, and admin/audit.

## Stack

- Ruby on Rails 7.1, PostgreSQL 16, Hotwire (Turbo + Stimulus), Tailwind
- Devise (auth), Pundit (roles), AASM (state machines), PaperTrail (audit), Discard (soft delete)
- Solid Queue (Postgres-backed jobs + recurring), letter_opener_web (dev mail), Prawn (PDFs)
- Pagy, Ransack, money-rails, FactoryBot

## Quick start (local)

Prereqs: Ruby 3.3.6, Postgres 16 running locally with a `hurst` user (see `config/database.yml`).

```bash
bundle install
bin/rails db:setup   # create, migrate, seed
bin/dev              # runs web + tailwind watcher + Solid Queue worker
```

Sign in at <http://localhost:3000>:

| Email                                  | Password      | Role    |
| -------------------------------------- | ------------- | ------- |
| admin@greatsouthernbeverages.test                | password123   | admin   |
| sally.sales@greatsouthernbeverages.test          | password123   | sales   |
| omar.ops@greatsouthernbeverages.test             | password123   | ops     |
| fred.finance@greatsouthernbeverages.test         | password123   | finance |

Mail preview: <http://localhost:3000/letter_opener>
Job console (admin only): <http://localhost:3000/jobs>

## Quick start (Docker)

```bash
docker compose up --build
# in another shell:
docker compose exec web bin/rails db:seed
```

## Verification walkthrough

1. Sign in as admin → sidebar renders with all sections.
2. Admin → Users → create ops user → sign in as them → Admin section is hidden.
3. Create a Company + Contact.
4. Create a Deal → drag across pipeline stages.
5. Create a Product + BOM for that brand.
6. Receive raw-material lots for each BOM ingredient.
7. From a Deal → New Quote → send → PDF + email delivered to letter_opener.
8. New Contract with pricing tier → mark_signed.
9. Schedule Production Run → Release (reserves lots) → Start → Complete with actual units.
   FG lot is created, raw lots decremented, movement logged.
10. From completed run, Create Invoice (pre-filled from contract tier) → Send → record Payment → status=paid.
11. Create a Reminder due in 2 minutes → wait → bell badge increments, email appears in letter_opener.
12. Admin → Audit Log → see sensitive actions.
13. From any FG Lot show page → "Trace backward" → run → consumptions → raw-material lots (recall traceability).

## Scripts

- `bin/dev` — run web + Tailwind + worker
- `bin/reset-dev` — drop/recreate/migrate/seed dev DB
- `bin/jobs` — run Solid Queue worker standalone
- `bin/rails test` / `bin/rails test:system` — test suite

## Domain model highlights

- **CRM**: Company → Contact, Deal (AASM pipeline), Activity (polymorphic), Task, Reminder.
- **Sales**: Quote, Contract (+ pricing tiers), Invoice (+ payments). Numbers via `NumberSequence`.
- **ERP**: Product → BOM → BomItem → RawMaterial → RawMaterialLot. ProductionRun (AASM: planned→released→in_progress→completed→closed) snapshots BOM on release, consumes lots on complete, produces FinishedGoodLot + FinishedGoodMovement. Full backward traceability from FG lot → run → raw lots.
- **Admin**: User roles (admin/sales/ops/finance), AuditLog (via `AuditLogger` service), PaperTrail versions.
- **Reminders**: `RemindersSweepJob` runs every minute via Solid Queue recurring config; fires due reminders, creates in-app Notifications, sends mail, schedules next occurrence.
