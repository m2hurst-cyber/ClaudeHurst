---
name: create-quote-through-mark-signed-contract
description: Step-by-step procedure to create quote and carry it through to mark signed
  contract in the Great Southern Copacker CRM-ERP (6 steps, sales area). Use when
  you need to create quote through mark signed contract; captured from a workflow
  staff repeated 4 times.
license: Proprietary - internal use only
metadata:
  title: Create quote through mark signed contract
  version: '1'
  domain: sales
  tags:
  - sales
  - quotes
  - contracts
  - contract-pricing-tiers
  inputs:
  - Existing or new quote record
  outputs:
  - 'Contract updated by: mark the contract signed'
  status: published
  published_at: '2026-11-23T14:45:04Z'
  published_by: Sally Sales
  source:
    origin: detected
    workflow:
    - quotes#create
    - quotes#send_out
    - quotes#mark_accepted
    - contracts#create
    - contract_pricing_tiers#create
    - contracts#mark_signed
    application: great-southern-copacker-crm-erp
    occurrences: 4
    candidate_id: 2
    contributors:
    - Sally Sales
    - Sam Sales
    last_seen_at: '2026-11-22T16:15:04Z'
    first_seen_at: '2026-11-19T15:45:04Z'
    distinct_users: 2
    draft_generator: template
---

# Create quote through mark signed contract

## When to use

Use this procedure when you need to create quote through mark signed contract. It was performed 4 times by 2 people (2026-11-19 to 2026-11-22) before being captured as a skill.

## Inputs

- Existing or new quote record

## Steps

1. Create a quote from the deal  
   _App action: `quotes#create`_
2. Send the quote (generates the PDF and emails the contact)  
   _App action: `quotes#send_out`_
3. Mark the quote accepted  
   _App action: `quotes#mark_accepted`_
4. Create the contract  
   _App action: `contracts#create`_
5. Add a pricing tier to the contract  
   _App action: `contract_pricing_tiers#create`_
6. Mark the contract signed  
   _App action: `contracts#mark_signed`_

## Outputs

- Contract updated by: mark the contract signed

## Checks

- Confirm each step shows a success notice before moving on.
- If a step is rejected (validation or permission), fix the record and repeat that step only.
