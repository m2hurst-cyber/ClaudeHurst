---
name: create-production-run-through-create-invoice
description: Step-by-step procedure to create production run and carry it through
  to create invoice in the Great Southern Copacker CRM-ERP (5 steps, ops area). Use
  when you need to create production run through create invoice; captured from a workflow
  staff repeated 4 times.
license: Proprietary - internal use only
metadata:
  title: Create production run through create invoice
  version: '1'
  domain: ops
  tags:
  - ops
  - production-runs
  inputs:
  - Existing or new production run record
  outputs:
  - 'Production run updated by: create the invoice from the completed run (pre-filled
    from the contract tier)'
  status: published
  published_at: '2026-11-23T14:45:04Z'
  published_by: Omar Ops
  source:
    origin: detected
    workflow:
    - production_runs#create
    - production_runs#release
    - production_runs#start_run
    - production_runs#complete
    - production_runs#create_invoice
    application: great-southern-copacker-crm-erp
    occurrences: 4
    candidate_id: 3
    contributors:
    - Olive Ops
    - Omar Ops
    last_seen_at: '2026-11-22T15:09:04Z'
    first_seen_at: '2026-11-19T14:45:04Z'
    distinct_users: 2
    draft_generator: template
---

# Create production run through create invoice

## When to use

Use this procedure when you need to create production run through create invoice. It was performed 4 times by 2 people (2026-11-19 to 2026-11-22) before being captured as a skill.

## Inputs

- Existing or new production run record

## Steps

1. Schedule a production run (product, BOM, line, planned units)  
   _App action: `production_runs#create`_
2. Release the run — snapshots the BOM and reserves raw-material lots  
   _App action: `production_runs#release`_
3. Start the run on the line  
   _App action: `production_runs#start_run`_
4. Complete the run with actual units — consumes lots and creates the finished-good lot  
   _App action: `production_runs#complete`_
5. Create the invoice from the completed run (pre-filled from the contract tier)  
   _App action: `production_runs#create_invoice`_

## Outputs

- Production run updated by: create the invoice from the completed run (pre-filled from the contract tier)

## Checks

- Confirm each step shows a success notice before moving on.
- If a step is rejected (validation or permission), fix the record and repeat that step only.
