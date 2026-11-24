# Agent guide: reading and capturing Bloomberg BQL worksheets

You turn an Excel worksheet built on Bloomberg data into a reviewed skill. Work in four passes and
never skip one: **Observe → Interpret → Document (pieces and structures, as files) → Write the skill.**
You see the sheet's labels and formulas, never its numbers.

## 1. Observe

Record what is on the sheet before deciding what it means.

- **Extent:** the used range, the sheet name, and every block of filled cells (a block is a run of
  rows separated by blank rows).
- **Labels:** text in the first column (row labels), text across a row above formulas (column
  headers such as `FY-4 … FY0`, `Q1`, dates, tickers), and a title in the top rows.
- **Formulas:** every formula with its address. Group cells whose formulas are the same pattern
  once cell references are made relative (a row of `=BQL($B$3,"sales_rev_turn(fpt=A, fpo=-4)")` …
  `fpo=0` is one pattern whose `fpo` varies by column).
- **Inputs:** constants that formulas point at with absolute references (`$B$3`, `$B$4`): a
  security, a universe, a WACC, a date. Note the label beside each.
- **Bloomberg functions you will meet:**
  - `=BQL(universe, "data item(params)", [optional params])`: one item for one universe.
  - `=BQL.Query("get(items) for(universe) with(params)")`: a full query string; results spill.
  - `=BDP(security, field, [overrides])`: legacy point-in-time field.
  - `=BDH(security, field, start, end, [options])`: legacy history; spills.
  - `=BDS(security, field)`: legacy bulk data (lists); spills.
- **BQL parameters to read precisely:**
  - `fpt` fiscal period type: `A` annual, `Q` quarterly, `S` semi-annual, `LTM`.
  - `fpo` fiscal period offset: `0` latest reported, `-1` the one before, `1` next (estimates).
  - `ae=E` consensus estimate, `ae=A` actual. `dates=-1Y`, `dates=range(-1Y,0D)` for history.
  - `currency=USD`, `fill=prev`, `per=W` (periodicity); universe functions `members('SPX Index')`,
    `peers('AAPL US Equity')`, `filter(...)`.

## 2. Interpret

Say what the sheet is attempting, in one sentence a colleague would recognise, then justify it.

- **Task type:** financial analysis (statements, ratios), macro analysis (economic index
  tickers ending `Index`), intrinsic valuation (forecast free cash flow, discount factors, a
  terminal value, WACC and growth inputs), relative valuation (several securities × multiples
  such as `pe_ratio`, `ev_to_ebitda`, a median row), ESG (`esg_disclosure_score` and its pillars),
  charting (a chart over the table), sensitivity (a grid of one formula over two input ranges).
- **Shape:** a *table* (rows of items × period columns), a *grid* (rows of securities × columns of
  fields, usually with median/mean), a *sensitivity grid*, or a *chart*.
- **Dependencies:** cells that read another sheet (`'Financials'!C6`) mean this sheet is a later
  step on a route; name the sheet it depends on.
- **Assumptions and risks:** hard-coded tickers, dates or currencies; mixed units (millions vs
  units, % vs decimal); `fpo` offsets that don't line up with the column headers; estimates mixed
  with actuals in one row; spilled results that can collide.

## 3. Document the pieces and structures (files)

Produce three files; a reviewer must be able to rebuild the sheet from them alone.

- **STRUCTURE.md:** purpose; the blocks with their ranges and roles (title, inputs, header,
  rows, summary); every input (cell, label, meaning, default); the column headers and what varies
  across them; dependencies on other sheets.
- **FORMULAS.md:** one line per formula pattern: range, an example formula, the pattern, the
  command-library key it matches (`revenue`, `fcf_est`, …) with its verified status, or "new"
  with a proposed command (key, name, category, syntax with `{security}`, `{fpt}`, `{fpo}`, …
  placeholders), and what it returns in plain words, including the unit.
- **blueprint.json:** the worksheet blueprint (inputs, columns with their params, rows with a
  command key or a computed formula using `{row:key}`, `{input:key}`, summary cells) that the
  add-in builds from.

## 4. Write the skill

Write the SKILL.md in Anthropic's Agent Skills format: a name (lowercase, hyphens, under 64
characters, no "anthropic"/"claude"), a third-person description that says what the skill
builds and when to use it, then `# Title`, `## When to use`, `## Inputs`, `## Steps` (numbered:
enter the inputs, build the sheet, check the results), `## Outputs` (the sheet and its rows),
and `## Checks` (units, periods, unverified commands, assumptions you found).

Never invent a Bloomberg field. If a formula uses a field you don't recognise, keep it exactly as
written and mark the command **new, unverified** for someone with terminal access to check.
