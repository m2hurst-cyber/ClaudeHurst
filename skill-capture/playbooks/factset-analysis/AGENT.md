# Agent guide: reading and capturing FactSet worksheets

You turn an Excel worksheet built on FactSet data into a reviewed skill. Work in four passes and
never skip one: **Observe → Interpret → Document (pieces and structures, as files) → Write the skill.**
You see the sheet's labels and formulas, never its numbers.

## 1. Observe

Record what is on the sheet before deciding what it means.

- **Extent:** the used range, the sheet name, and every block of filled cells (blocks are runs of
  rows separated by blank rows).
- **Labels:** row labels in the first column, column headers above formulas (`FY-4 … FY0`, quarters,
  dates, identifiers such as `AAPL-US`), and a title in the top rows.
- **Formulas:** every formula with its address. Group cells whose formulas are the same pattern
  once references are made relative (`=FDS($B$3,"FF_SALES(ANN,-4)")` … `(ANN,0)` is one pattern whose
  period offset varies by column).
- **Inputs:** constants that formulas point at with absolute references: an identifier, a
  universe, a currency, a WACC, a date. Note the label beside each.
- **FactSet Excel functions you will meet:**
  - `=FDS(id, "CODE(params)")`: one data item for one identifier (`AAPL-US`, `MSFT-US`).
  - `=FDSC(...)` / `=FDSB(...)` variants where the firm's add-in version uses them; treat like `FDS`.
- **FactSet code families to read precisely:**
  - `FF_…` FactSet Fundamentals, `FF_CODE(period, offset)`: `ANN` annual, `QTR` quarterly,
    `LTM`/`ANN_R` restated; offset `0` latest, `-1` prior.
  - `P_…` prices (`P_PRICE(date)`, `P_VOLUME`), with dates as `0` (latest), `-1AY` (a year ago),
    ranges `P_PRICE(-1AY,0,D)` that spill.
  - `FE_…` FactSet Estimates, `FE_ESTIMATE(item, statistic, period, offset, as-of, …)`: `MEAN`,
    `MEDIAN`; `ANN_ROLL` rolling fiscal years; offset `+1` next year.
  - `FG_…` derived/screening items; economics and ESG codes depend on the subscription (record
    them exactly; they are often firm-specific).

## 2. Interpret

Say what the sheet is attempting, in one sentence a colleague would recognise, then justify it.

- **Task type:** financial analysis (statements, ratios), macro analysis (economic series),
  intrinsic valuation (forecast free cash flow, discount factors, terminal value, WACC and growth
  inputs), relative valuation (identifiers × multiples, a median row), ESG (score codes), charting,
  or sensitivity (a grid of one formula over two input ranges).
- **Shape:** a *table* (items × period columns), a *grid* (identifiers × fields), a *sensitivity
  grid*, or a *chart*.
- **Dependencies:** references to other sheets mean this is a later step on a route; name them.
- **Assumptions and risks:** hard-coded identifiers or dates; currency (`FF_…` items report in the
  company's currency unless converted); units (millions); period offsets that don't match the
  column headers; mixing restated (`ANN_R`) and as-reported (`ANN`) data.

## 3. Document the pieces and structures (files)

Produce three files; a reviewer must be able to rebuild the sheet from them alone.

- **STRUCTURE.md:** purpose; the blocks with ranges and roles; every input (cell, label, meaning,
  default); the column headers and what varies across them; dependencies on other sheets.
- **FORMULAS.md:** one line per formula pattern: range, an example formula, the pattern, the
  command-library key it matches with its verified status, or "new" with a proposed command (key,
  name, category, syntax with `{security}`, `{period}`, `{fpo}` placeholders), and what it returns,
  with the unit and currency.
- **blueprint.json:** the worksheet blueprint (inputs, columns with params, rows with a command key
  or a computed formula using `{row:key}`, `{input:key}`, summary cells) that the add-in builds from.

## 4. Write the skill

Write the SKILL.md in Anthropic's Agent Skills format: a name (lowercase, hyphens, under 64
characters, no "anthropic"/"claude"), a third-person description that says what the skill builds
and when to use it, then `# Title`, `## When to use`, `## Inputs`, `## Steps` (numbered), `## Outputs`
and `## Checks` (units, currency, periods, unverified commands, assumptions you found).

Never invent a FactSet code. If a formula uses a code you don't recognise, keep it exactly as written
and mark the command **new, unverified** for someone with FactSet access to check.
