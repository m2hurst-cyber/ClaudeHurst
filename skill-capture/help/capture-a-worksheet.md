---
title: Capture a worksheet
summary: Turn a spreadsheet you built into a documented, reviewable skill — in the right order.
section: how-to
order: 1
tags: [excel, worksheet, formulas, capture]
---

Capture reads a sheet the way a careful colleague would, and in the same order. It does
not start by writing.

1. **Observe.** Every cell, every formula, every reference between them.
2. **Interpret.** What is an input, what is a calculation, what is a result. Absolute
   references pointing at formulas are summaries, not inputs — a distinction most tools miss.
3. **Document the pieces.** Each block gets written down: what it takes, what it produces,
   the formula in words.
4. **Write the skill.** Only then, and from the documentation rather than the cells.

## Doing it

1. Open the workbook in Excel with the add-in loaded.
2. Choose the sheet and press **Capture this worksheet**.
3. Read what it says the sheet is doing. This is the part worth your attention — if it has
   misread a block, fix it here, before the skill is written.
4. Send it for review.

## What makes a sheet capture well

- **Named inputs in one place.** A block of assumptions at the top reads as inputs; the
  same numbers typed into the middle of a formula read as magic.
- **Consistent rows.** A row where the formula changes halfway across is described as two
  things, because that is what it is.
- **A clear result.** Capture looks for what the sheet produces. If the answer is buried
  three tabs away, say so in the description.

## What it never records

Cell values, client names, identifiers. The formulas and the structure are the skill; the
numbers are yours. A captured worksheet carries the shape of the model, not the model's data.
