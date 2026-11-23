# Skill Capture: design (Step 1, Skill Capture & Institutional Memory)

```
collectors (Office, Slack, IDE, browser, chat exports)
      │  POST /api/v1/events (bearer token per source; structure only)
      ▼
Ingestor ──► usage_events (90-day retention) + action_definitions (step labels)
      │
      ▼  hourly (Solid Queue)
WorkflowDetector ──► skill_candidates ──► DraftGenerator (Claude → template fallback)
      │                                          │
      ▼                                          ▼
reviewers for the area get notified ──► Review UI: edit / approve / reject
                                                 │
                                                 ▼
                         Publisher ──► skills (versions, forks, provenance)
                                         ├─ Library UI + SKILL.md download
                                         ├─ GET /api/v1/skills (agents, routing)
                                         └─ optional export to a Git skill repo
```

## How the spec maps to this build

| Spec | Implementation |
|---|---|
| Activity monitor | External collectors send events to the ingest API. `examples/collector.js` is a reference client. |
| Trigger detection | `Capture::WorkflowDetector` |
| Capture & summarize | `Capture::DraftGenerator` → `ClaudeDrafter` / `TemplateDrafter` |
| Skill metadata | `skills` table that maps 1:1 to Agent Skills frontmatter |
| User review workflow | Review pages, routing by area, notifications |
| Institutional memory | Library, JSON API, `SKILL.md` export |
| Knowledge base | PostgreSQL |
| API | `POST /api/v1/events`, `GET /api/v1/skills[/:name]` |
| Auth | Devise sessions for people, hashed bearer tokens for collectors, Pundit policies |

## Data model

- **sources**: registered collectors. Holds name, kind, `token_digest` (SHA-256; the raw token is shown once), active flag and `last_seen_at`.
- **action_definitions**: what each action key means (`label`) and which area it belongs to (`domain`). Collectors can register labels. Admin edits are never overwritten by a collector.
- **usage_events**:

  | Field | Meaning |
  |---|---|
  | `source_id` | The collector that sent the event |
  | `actor_key` | Pseudonymous id of the person |
  | `actor_name` | Optional display name, used only for attribution |
  | `session_key` | The collector's work-session id |
  | `action_key` | The step |
  | `domain` | Area of work |
  | `resource_type`, `resource_ref` | What the step acted on |
  | `context` | Allowlisted short tokens only |
  | `occurred_at` | When the step happened |

- **skill_candidates**: one detected or requested workflow.

  | Field | Meaning |
  |---|---|
  | `signature`, `steps` | The step sequence |
  | `domain` | Area, which decides who reviews it |
  | `status` | `detected → drafted → approved \| rejected \| dismissed` |
  | `origin` | `detected` or `manual` |
  | `occurrence_count`, `distinct_actor_count` | How often, by how many people |
  | `contributors` | `[{key, name}]` |
  | `example_traces` | Sample runs of the workflow |
  | `draft_*` | The draft skill |
  | Review fields | Reviewer, date and notes |

- **skills**: one row per published version.

  | Field | Meaning |
  |---|---|
  | `name` (Agent Skills, kebab-case ≤ 64), `version` | Identity |
  | `title`, `description` (≤ 1024), `body` (Markdown) | Content |
  | `domain`, `tags`, `inputs`, `outputs`, `license` | Metadata |
  | `status` | `published \| superseded \| deprecated` |
  | `parent_skill_id` | Previous version or fork origin |
  | `published_by`, `published_at` | Who approved it and when |
  | `source` | Provenance: workflow, sources, contributors, counts, dates, drafter, `revised_from`, `change_note` |

- **notifications** and **audit_logs**.

## Lineage rules

Nothing published is ever overwritten:
- Revising a skill under the same name creates the next version, and the old version becomes `superseded`.
- Revising under a new name creates a **fork** at v1, with a parent link to the original. The original stays published.
- Approving a candidate that reuses a published name also creates the next version of that skill.
- Only the current version can be revised.

## Detection

1. Group each person's events into sessions. A session ends at a new session key or after an idle gap of more than 30 minutes.
2. Collapse consecutive duplicate steps.
3. Enumerate contiguous sequences of 2–6 steps that never repeat a step. Count occurrences without overlap.
4. Keep sequences that meet both thresholds: at least 3 occurrences, by at least 1 person.
5. Keep only maximal sequences. Never re-propose a fragment of a workflow that was already reviewed.

A candidate's area is the most common `domain` on its events. Failing that, it is taken from the action definitions. The thresholds, gap, lookback, retention, batch size and context allowlist can all be set with `SKILL_CAPTURE_*` environment variables (see `app/services/capture/config.rb`).

## Drafting with Claude

`ClaudeDrafter` is used when `ANTHROPIC_API_KEY` (or `ANTHROPIC_AUTH_TOKEN`) is set and `SKILL_CAPTURE_LLM` is not `off`.
- **Model:** `claude-opus-5-5` (override with `SKILL_CAPTURE_MODEL`), effort `medium`.
- **Output:** structured output with a strict JSON schema.
- **Refusals:** the server-side refusal fallback is on (`fallbacks: :default`), so a declined request is retried on a substitute model.
- **What Claude sees:** the step keys and labels, counts, dates, and requester or reviewer notes. It never sees actor ids or names, resource refs or context.
- **Fallback:** any error, refusal, truncation or bad JSON falls back to the template drafter.

## Security & governance

- **Data minimization at ingest:**
  - The server keeps only an action key, an actor id, a session id, a timestamp, an optional area, an optional resource type and ref, and allowlisted context.
  - Every stored value must be a short token, so free text cannot get through.
  - Values that look like email addresses are discarded, including actor names.
  - Unknown fields are dropped, and the response reports how many were dropped.
- **Retention:** raw events are purged after 90 days. Exported `SKILL.md` files leave out actor ids.
- **Collector auth:** each source has its own revocable token, stored hashed. Batches are capped at 500 events. An unusual event volume from one source alerts admins.
- **People auth:** accounts are created by an admin, with a generated one-time password. No credentials are seeded. Inactive users can't sign in.
- **Authorization:**
  - Reviewers publish and revise only in their own areas. Admins can do so anywhere.
  - Members can see only their own requests.
  - Only admins can deprecate skills, manage sources and people, or read the audit log.
- **Audit:** detection, drafting, requests, edits, approvals, rejections, publishes, revisions, forks, deprecations, and source and user changes are all logged.
- **Misuse alert:** more than 10 publishes by one person in an hour notifies admins.
- **IP:** skills default to `Proprietary - internal use only`.

## Tests

- `test/services/workflow_detector_test.rb`: five scripted workflows mixed with noise. All five are captured (100%, against a ≥ 80% bar) and nothing else is proposed. Also covers session gaps, duplicate collapsing, the people threshold, routing and fragment suppression.
- `test/services/ingestor_test.rb`: what is kept and what is dropped, plus validation and label precedence.
- `test/services/draft_and_publish_test.rb`: the template draft, the Claude request shape and what it leaves out (using a stub client), fallbacks, provenance, versions and forks, role checks, `SKILL.md` and the alerts.
- `test/integration/capture_flow_test.rb`: the full path from collector to API, through detection, review, publishing and discovery. Also covers access control, one-time source tokens, admin-created accounts, and the absence of default logins.

## Open questions: current answers

- **Trigger sensitivity:** set by frequency, by number of people, and by a minimum step count. All three can be tuned per deployment. Reject notes are kept so the thresholds can be tuned later.
- **Attribution:** contributors are recorded on the candidate and copied into the skill's provenance. Forks and revisions keep parent links.
- **Privacy trade-offs:** only structure is captured, so skills can't leak content. Collectors should send pseudonymous actor ids.
- **MVP scope:** approval is manual. Areas route review automatically.
- **Stale skills:** handled by revising (which creates a new version), deprecating, or a later candidate that reuses the name.

## Not built yet

- Production collectors for specific tools. Only a reference collector exists.
- SSO.
- A knowledge-council review cadence.
- Push notifications outside the app.
