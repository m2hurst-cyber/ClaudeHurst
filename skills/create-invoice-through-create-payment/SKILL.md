---
name: create-invoice-through-create-payment
description: Step-by-step procedure to create invoice and carry it through to create
  payment in the Great Southern Copacker CRM-ERP (3 steps, finance area). Use when
  you need to create invoice through create payment; captured from a workflow staff
  repeated 4 times.
license: Proprietary - internal use only
metadata:
  title: Create invoice through create payment
  version: '1'
  domain: finance
  tags:
  - finance
  - invoices
  - payments
  inputs:
  - Existing or new invoice record
  outputs:
  - 'Payment updated by: record a payment against the invoice'
  status: published
  published_at: '2026-11-23T14:45:04Z'
  published_by: Fred Finance
  source:
    origin: detected
    workflow:
    - invoices#create
    - invoices#send_out
    - payments#create
    application: great-southern-copacker-crm-erp
    occurrences: 4
    candidate_id: 4
    contributors:
    - Fred Finance
    last_seen_at: '2026-11-22T16:57:04Z'
    first_seen_at: '2026-11-19T16:45:04Z'
    distinct_users: 1
    draft_generator: template
---

# Create invoice through create payment

## When to use

Use this procedure when you need to create invoice through create payment. It was performed 4 times by 1 person (2026-11-19 to 2026-11-22) before being captured as a skill.

## Inputs

- Existing or new invoice record

## Steps

1. Create the invoice  
   _App action: `invoices#create`_
2. Send the invoice (PDF + email)  
   _App action: `invoices#send_out`_
3. Record a payment against the invoice  
   _App action: `payments#create`_

## Outputs

- Payment updated by: record a payment against the invoice

## Checks

- Confirm each step shows a success notice before moving on.
- If a step is rejected (validation or permission), fix the record and repeat that step only.
