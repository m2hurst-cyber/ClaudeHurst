---
title: Proving what a skill is
summary: Content hashes, the provenance chain, and how a skill can be trusted outside this firm.
section: concepts
order: 3
tags: [provenance, security, hash, audit, trust]
---

A skill is only worth sharing if the person receiving it can tell what they received.

## Every version has a content hash

A SHA-256 of the fields that make the skill what it is: name, title, description, body,
tags, inputs, outputs, workflow and licence. Deliberately **not** the stage, the votes or
the timestamps — promoting a skill does not change the skill.

Two firms holding the same skill compute the same hash. That is what lets a skill be
referred to, transferred and checked by someone with no access to our database.

## History cannot be quietly rewritten

Every publication, revision, branch, promotion and transfer appends an entry to a chain
where each entry commits to the one before it. Change or delete any past entry and every
hash after it stops matching; verification reports exactly where.

Each day the chain is committed to with a Merkle root, written outside the database.
Publish that root anywhere we do not control and the history beneath it is fixed.

## Why not a blockchain

The three ideas worth having — content addressing, append-only hash-linked history, and
external anchoring — do not require one. A chain would only be another place to put the
root, and that choice can be made later without changing anything here.

## What this gives you today

A transfer can be proved after the fact. An audit question has an answer that does not rely
on trusting whoever administers the database. And a skill sent outside the firm arrives
with a manifest a stranger can check.
