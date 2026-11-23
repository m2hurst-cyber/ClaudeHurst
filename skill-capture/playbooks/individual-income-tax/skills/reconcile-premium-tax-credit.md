---
name: reconcile-premium-tax-credit
description: Reconciles advance payments of the premium tax credit on Form 8962 from the Marketplace Form 1095-A. Use when the client bought health insurance through the Marketplace (Form 1095-A).
metadata:
  title: Reconcile the premium tax credit (Form 8962)
---

# Reconcile the premium tax credit (Form 8962)

## When to use

Branch after "Claim deductions and credits" when the client has a Form 1095-A. A return with a 1095-A can't be e-filed without Form 8962.

## Inputs

- Form 1095-A for each policy, household size and income

## Steps

1. Enter the monthly amounts from each 1095-A (premium, benchmark premium, advance credit).
2. Allocate policies shared with someone outside the tax household.
3. Let the software compute the allowed credit; compare with the advance payments.
4. Explain to the client any repayment (or extra credit) before review.
5. Rejoin the mainline.

## Outputs

- Form 8962 reconciling the credit

## Checks

- Every 1095-A is entered; a missing one blocks e-file.
- Household income and size match the return.
