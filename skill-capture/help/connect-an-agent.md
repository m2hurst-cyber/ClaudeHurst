---
title: Connect an agent
summary: Reach the library over MCP from Claude, an IDE, or your own code.
section: agents
order: 1
tags: [mcp, agents, api, integration, claude]
---

Skill Capture speaks MCP, so an agent can search the library, read a skill, follow a route
and report what a run cost — without a person in the loop.

## Connecting

Point your client at `POST /mcp` with a token in the `Authorization` header. Admins issue
tokens under **Admin → Sources**, which also shows the exact connection snippet to paste.

Two kinds of token, and the difference matters:

- **A person's token** acts as that person: it sees their sandbox skills and may start jobs
  and complete tasks on their behalf.
- **An agent token** sees only firm and market skills, and cannot do anything that needs a
  person's judgement.

## What an agent can do

Find anything, search skills, read one in full, find the route between two points, list
playbooks, start a job, add a document to it, list and complete tasks, and report usage.

That last one matters more than it sounds: when agents report the tokens, time and model
they actually used, model suggestions for everyone improve.

## Reading as Markdown

Every page in the console has a `.md` form — add `.md` to the URL, or use **Copy for LLM**.
Agents and people read the same text, which means the help and the skills cannot drift
apart from what the agent is told.
