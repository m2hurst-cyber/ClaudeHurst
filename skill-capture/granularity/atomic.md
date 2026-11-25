# Writing skills at ATOMIC granularity

You are writing for a firm that collects **building blocks**. Many small skills that
compose; the map joins them up. A long procedure here is a failure, not thoroughness.

## Size and shape

- **2–3 steps.** If it needs four, it is two skills.
- **Body under 60 lines.** One screen. No phases, no sub-headings beyond the standard ones.
- One input set, one output. If the outputs are unrelated to each other, split it.

## What counts as a skill here

A block only qualifies if it is **used in more than one situation**. The test is not "is
this repeated" — it is "would someone reach for this inside a job I have not thought of".

- Good: *unlever a set of comp betas*. Used in a DCF, in a WACC refresh, in a sector screen.
- Good: *tie a trial-balance account to its subledger*. Used at close, in an audit request,
  in a diligence pack.
- Bad: *open the valuation workbook and refresh the data tab*. Only ever happens inside one
  larger job. That is a fragment of that job, not a block.

## Steps that belong to a neighbour

When the observed work continues past the block, **stop at the block**. Do not absorb the
next steps to make the skill feel complete. Name the neighbour in `## Outputs` instead:
"Produces the unlevered beta column that `equity.dcf.wacc-build` reads."

That sentence is what lets the map compose them. It is the most important line you write.

## Naming

Name the operation, not the context it was seen in. `unlevering-comp-betas`, not
`preparing-the-acme-dcf`. A block named after one job will never be found for another.

## Save, extend or branch

- **Save** is the common answer. Most blocks are new.
- **Extend** only when the added steps are part of the same operation — a validity check on
  the same numbers, not the next thing the person did.
- **Branch** when the same input and output are reached by a genuinely different method
  (pulling betas from FactSet rather than BQL is a branch; both are legitimate).

## Worked example

Observed: `open comps workbook → pull betas → unlever betas → relever at target → write
discount row → refresh DCF → export summary`.

At this level that is **three skills, not one**: *unlevering comp betas*, *relevering at a
target structure*, *writing the discount row*. The opening and the export are not skills —
they are what happened around the work. Each of the three names the next in its outputs.
