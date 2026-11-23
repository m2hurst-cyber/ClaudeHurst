---
name: report-individual-income
description: Works through a Form 1040's income - wages and withholding, interest and dividends (Schedule B), retirement distributions, Social Security, unemployment and other Schedule 1 income. Use when the workpapers are tied out and you need the client's total income; situations such as self-employment, investment sales, rentals or K-1s branch off from here.
metadata:
  title: Report income
---

# Report income

## When to use

After the financial information is organized. Each income situation the client answered "yes" to is its own branch after this step.

## Inputs

- Tied-out workpapers: W-2s, 1099-INT/DIV/R/G/SSA and other income documents

## Steps

1. Wages: total every W-2 (box 1) and federal and state withholding; check for excess Social Security withholding when the client had more than one employer.
2. Interest and dividends: total them, separate qualified dividends, and complete Schedule B when the totals or foreign accounts require it.
3. Retirement distributions (1099-R): use the distribution code to decide what's taxable; check for rollovers, Roth conversions and early-withdrawal penalties.
4. Social Security benefits (SSA-1099) and unemployment (1099-G): carry them to the return; the software works out the taxable part of benefits.
5. Other income on Schedule 1: state refunds (taxable only if itemized last year), alimony under pre-2019 agreements, gambling, jury duty, prizes.
6. Note which income situations apply and take their branches before moving on.

## Outputs

- Total income by type, with withholding, ready for the return

## Checks

- Withholding in the return equals the W-2s and 1099s.
- Every 1099-R has its code reviewed; rollovers are documented.
- Income totals reconcile to the workpapers and the prior-year comparison.
