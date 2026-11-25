---
title: "Micro or macro: the granularity slider"
summary: Decide whether the firm collects small reusable blocks or whole end-to-end runs.
section: admin
order: 1
tags: [granularity, settings, detection, protocols, admin]
---

The most consequential setting in the system. It decides what counts as "a skill" here.

Granularity is not one threshold, so the slider moves five things together:

- **how long** a skill may be, from two steps to fourteen;
- **which pattern wins** when one sits inside another — the small reusable unit, or the
  longest whole story;
- **how much evidence** is needed, because short sequences recur by chance and long ones
  repeat rarely;
- **how varied the surroundings must be** — a building block appears inside several
  different jobs; a fragment only ever appears inside one;
- **what the AI is told to prefer** when it judges a pattern.

## The settings

| | Length | Nesting | Evidence | Surroundings |
| --- | --- | --- | --- | --- |
| Atomic | 2–3 | smallest unit wins | double | 3 different contexts |
| Small | 2–4 | smallest unit wins | half again | 2 different contexts |
| Balanced | 2–6 | current behaviour | normal | any |
| Broad | 3–9 | longest wins | slightly less | any |
| End to end | 4–14 | longest wins | least | any |

Balanced is exactly what the system did before the slider existed, so nothing changes until
you move it.

## Before you choose

The slider shows what each setting **would have found** in the events already collected —
how many patterns, how long they typically are, and an example. Move it and read that line
before saving.

## Per area and per person

Tax may want whole returns where equity research wants reusable blocks, so areas can
override the firm default, and a person can override their area — useful for someone who
simply wants fewer prompts. Detection still runs in one pass; each pattern is judged at its
own area's setting.

## What the agents are told

Each setting has written directions for the agents that draft and judge skills — how big a
skill should be, what to do with steps that belong to a neighbour, and when to save, extend
or branch, with worked examples. The same text goes into the drafter's instructions, so what
you read is what it is told. They are at [/agents/granularity](/agents/granularity), and
each has a `.md` form.

## A caution

Changing this does not re-cut skills that already exist. Move the firm to Atomic and the
large skills you have stay large while new ones arrive small.
