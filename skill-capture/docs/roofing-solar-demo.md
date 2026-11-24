# Skill Capture for a roofing and solar contractor

A demo built for a local roofing and solar company of roughly 150–200 people. **Nobody here has
spoken to them.** Every step, document, check and rate below comes from how the trade generally works,
not from their process, and that is the point: the demo is the starting draft their own people correct
in the first week.

## What the company gets

**One place the job actually lives.** A job (J-2041 in the demo) carries its own jacket: signed
contract, measurement report, permit, certificates of insurance, change orders, daily logs, inspection
reports, pay applications, lien waivers, warranty registration, interconnection approval. Each leg of
the job has to verify before the next counts as ready, and the checks are the ones that cost money
when they are missed:

- no material ordered against a verbal acceptance
- no cover-up before a required inspection
- a subcontractor with no current certificate of insurance can't start
- billed no more than the contract plus **signed** change orders (the demo catches an over-billing)
- no final payment released to a sub before their final waiver is in hand
- the manufacturer warranty registered before its deadline, or the system warranty doesn't exist

**Estimating and billing that tie to each other.** A job costing formula library (33 commands:
squares, pitch factor, waste, crew days, burdened rate, overhead, price from margin, percent complete,
retainage, payment due, aging bucket, days left to file a lien, over/under billing, kW DC, production,
price per watt, payback). Four worksheets build from it:

| Worksheet | What it answers |
|---|---|
| Estimate: cost to price | Same roof, three ways: simple gable, hips and valleys, complex cut-up, each with its own waste and production rate |
| Price per square to hold the margin | What the job must charge as production and material price move |
| Pay application with retainage | Completed and stored, percent complete, retainage, payment due, balance, and whether the job is billed ahead of the work |
| Array size, production and payback | Three array sizes: kW DC, production, net cost after incentive, payback, price per watt |

**The RFP, start to finish, as a process map.** Lanes for Outlook, Excel, Word, PowerPoint and agents.
The takeoff is read off the drawings by an agent; pricing and the sensitivity are the estimator's; the
bid package is a split task (a macro fills the forms, bonds and insurance while an agent writes the
scope narrative); then a pause until the award, then contract, monthly pay application, statement and
the month's report. The map shows which task is running now, and what the run has cost so far against
what it was anticipated to cost.

**Nine branches for the things that actually happen:** solar array and interconnection, insurance
claim and supplement, commercial RFP, subcontractors, hidden damage found at tear-off, prevailing wage
and certified payroll, maintenance agreements, and collections with the lien deadlines in view.

## Why it is different from software they already have

Most contractor software stores what happened. This captures **how your people do it** and makes that
repeatable: your estimator's way of pricing a cut-up roof becomes a skill the new estimator follows,
your office manager's pay application becomes a sheet anyone can build, and the mechanical parts
(copying charts into the appendix, filling the bid forms, building the schedule of values) become
macros that run with no AI tokens at all.

## What to correct in the first week

1. **The rates.** Waste, burden, overhead, margin, production rates, sun hours, derate: all placeholders.
   Replace them, then mark each command verified. Nothing should be quoted off an unverified formula.
2. **The checks.** Lien and notice deadlines, waiver forms, prevailing wage filings, permits and
   interconnection rules differ by state, utility and jurisdiction, and they change. Each one is a
   prompt to confirm yours, not a statement of law.
3. **The steps.** If the survey is done differently here, change the step and the people who do it will
   use it. If a whole job type is missing (service calls, re-sheets, metal retrofit), it becomes a branch.

## How a pilot would run

- **Week 1:** install the two playbooks, set the rates, correct the steps with one estimator and one job manager.
- **Week 2:** run one real job through the jacket end to end, and one real bid through the process map.
- **Week 3:** look at what the AI actually spent per task, approve the first macros, and decide what
  goes to a small model and what needs a deep one.
- **After that:** every job that is done differently becomes a prompt to save, extend or branch the skill,
  which is how the company's own way of working gets written down instead of leaving with people.
