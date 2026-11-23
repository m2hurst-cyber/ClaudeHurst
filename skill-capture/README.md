# Skill Capture

This app captures institutional know-how. Collectors in the tools people already use (Office add-ins, Slack bots, IDE plugins, browser agents) report *which steps* people take, never the content they work on. Skill Capture spots multi-step workflows that people keep repeating. It drafts each one as an Agent Skills `SKILL.md` and routes it to a reviewer for that area of work. Approved skills go into a versioned library that people can search and agents can fetch over an API.

The full design is in [docs/design.md](docs/design.md).

## Stack

Ruby 3.3, Rails 7.2, PostgreSQL, Hotwire, Tailwind, Devise, Pundit, Solid Queue (in the main database), and the Anthropic Ruby SDK.

## Run it locally

Prerequisites: Ruby 3.3 and Postgres. The database settings come from `DATABASE_HOST`, `DATABASE_USER` and `DATABASE_PASSWORD`, which default to localhost, postgres and postgres.

```bash
bundle install
bin/rails db:prepare
bin/rails users:create EMAIL=you@example.org NAME="Your Name" ROLE=admin   # prints a one-time password
bin/dev                                                                   # web + Tailwind + job worker
```

No accounts are seeded. Every account is created by an admin, either with the task above or on the **People** page, and each new account gets a generated one-time password.

**Demo data.** `bin/rails capture:demo` (development only) registers a demo collector and feeds it two repeated workflows, a finance month-end close and a support escalation. It then runs detection. Open **Review** to see the result.

**Drafting with Claude.** Set `ANTHROPIC_API_KEY` to have Claude draft the skills. Without it, a built-in template writes the drafts.

## Connect a collector

1. As an admin, open **Sources → Register source**. Copy the token; it is shown only once.
2. Send batches of events to `POST /api/v1/events` with `Authorization: Bearer <token>`:

```json
{ "events": [ {
    "action": "excel.run_macro:month_end",
    "label": "Run the month-end macro",
    "domain": "finance",
    "actor": { "id": "u-7f3a", "name": "Sam" },
    "session": "b1c2",
    "occurred_at": "2026-11-20T14:03:00Z",
    "resource": { "type": "workbook", "ref": "wb-381" },
    "context": { "app": "excel" }
} ] }
```

`examples/collector.js` is a batching browser/Office collector, and `examples/send_events.sh` sends a single event with curl.

## Commands

| Command | What it does |
|---|---|
| `bin/rails test` | Run the test suite |
| `bin/rails capture:sweep` | Detect and draft now (also runs hourly through Solid Queue) |
| `bin/rails "capture:export[dir]"` | Write published skills to `dir/<name>/SKILL.md` |
| `SKILL_CAPTURE_EXPORT_DIR=/path` | Also export each skill automatically when it is published |

## Roles

| Role | Can do |
|---|---|
| member | Browse and download skills, request new ones, follow their own requests |
| reviewer | Everything a member can, plus review, publish and revise skills in their **areas** (for example `finance`, `support`) |
| admin | Everything, plus manage people, sources and action labels, deprecate skills, and read the audit log |
