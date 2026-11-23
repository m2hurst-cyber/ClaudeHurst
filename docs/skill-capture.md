# Skill Capture & Institutional Memory (Step 1)

Spots work that people in the CRM-ERP keep repeating, drafts it as a documented
**skill** (an Agent Skills `SKILL.md`), sends it to the right process owner for
review, and publishes it to a searchable library that people and agents can use.

```
 user actions ──► Collector ──► usage_events ──► WorkflowDetector (hourly) ──► skill_candidates
 (POST/PATCH/      (after_action,  (structure only,     (sessions → repeated            │
  PUT/DELETE)       no values)      90-day retention)    multi-step sequences)          ▼
                                                                          DraftGenerator (Claude → template fallback)
                                                                                         │
                       skills library ◄── Publisher ◄── review UI (domain owner approves / edits / rejects)
                       + SKILL.md export     (versions, forks, audit, notifications)
```

## This MVP and the original spec

| Spec item | MVP implementation |
|---|---|
| Activity monitor | `SkillCapture::Collector` runs as an `after_action` on every controller. It covers this app only. Office, Slack and IDE collectors would write the same `usage_events` rows. |
| Trigger detection | `SkillCapture::WorkflowDetector`: repeated contiguous step sequences per work session, with tunable thresholds |
| Capture & summarize | `SkillCapture::DraftGenerator` → `ClaudeDrafter` (Claude Opus 5.5, structured JSON output). Falls back to `TemplateDrafter` |
| Skill metadata | `skills` table that maps 1:1 to Agent Skills frontmatter (`name`, `description`, `license`, `metadata`) |
| Review workflow | `/skill_candidates`: generate/edit the draft, approve & publish, reject, dismiss. Process owners get in-app notifications |
| Institutional memory | `/skills` library (search, domain filter, versions, lineage, `SKILL.md` download, JSON API), plus optional export to a Git directory |
| Knowledge base | Postgres (`usage_events`, `skill_candidates`, `skills`). No separate graph store is needed at this scale |
| Auth | The existing Devise session plus Pundit policies (`SkillCandidatePolicy`, `SkillPolicy`) |

## Data model

**`usage_events`**: one row per successful state-changing request.

```yaml
user_id: 6
session_key: 3f9c…            # our own random per-session key (not the Rails session id)
workflow_key: production_runs#release
http_method: POST
resource_type: ProductionRun
resource_id: 42
context: { production_line_id: 2, status: released }   # *_id integers + allowlisted enums only
occurred_at: 2026-11-20T14:03:00Z
```

**`skill_candidates`**: a detected (or manually requested) workflow and its draft.

```yaml
signature: production_runs#release>production_runs#start_run>production_runs#complete
steps: [production_runs#release, production_runs#start_run, production_runs#complete]
domain: ops                    # decides who reviews it
status: drafted                # detected → drafted → approved | rejected | dismissed
origin: detected               # or manual
occurrence_count: 4
distinct_user_count: 3
contributor_ids: [4, 6, 9]
example_traces: [[{step: production_runs#release, resource: ProductionRun#42, at: …}, …]]
draft_name / draft_title / draft_description / draft_body / draft_tags / draft_inputs / draft_outputs
draft_generator: claude        # claude | template | human
reviewer_id / reviewed_at / review_notes / skill_id
```

**`skills`**: one row per published *version*.

```yaml
name: run-a-production-batch   # Agent Skills name: kebab-case, ≤ 64 chars
version: 2
parent_skill_id: 17            # previous version, or the skill this one was forked from
status: published              # published | superseded | deprecated
title, description (≤ 1024), body (Markdown), domain, tags[], inputs[], outputs[], license
published_by_id, published_at
source:                        # provenance, preserved across versions
  candidate_id: 3
  workflow: [...]
  contributors: [Omar Ops, Olive Ops]
  occurrences: 4
  first_seen_at / last_seen_at
  draft_generator: claude
  revised_from: run-a-production-batch@1
  change_note: "new line layout"
```

Lineage rules: editing a published skill **never overwrites it**.
- Saving under the same name creates the next version and marks the old one `superseded`.
- Saving under a new name creates a **fork** at v1. Its `parent_skill_id` points at the original, which stays published.
- Approving a new candidate whose name matches a published skill also creates the next version.

## Detection algorithm

1. Split each user's events into work sessions. A session ends at a different session key or an idle gap longer than `SKILL_CAPTURE_SESSION_GAP_MINUTES` (default 30).
2. Collapse consecutive duplicate steps (five lots received in a row count as one step).
3. Enumerate contiguous sequences of 2–6 steps in which no step appears twice. Occurrences are counted without overlap.
4. Keep sequences seen at least `MIN_OCCURRENCES` times (default 3) by at least `MIN_USERS` people (default 1).
5. Keep only maximal sequences: drop `A>B` when `A>B>C` occurs just as often.
6. Never re-propose a fragment of a workflow that was already captured or rejected.

The thresholds are environment variables (see `app/services/skill_capture/config.rb`).
For *Trigger Sensitivity*, frequency (occurrences) and breadth (distinct people) are separate knobs. Complexity sets a floor of 2 steps.

## Drafting with Claude

`ClaudeDrafter` calls Claude only when `ANTHROPIC_API_KEY` (or `ANTHROPIC_AUTH_TOKEN`) is set and `SKILL_CAPTURE_LLM` is not `off`.

- **Model:** `claude-opus-5-5` (override with `SKILL_CAPTURE_MODEL`), effort `medium`.
- **Output:** structured JSON (`output_config.format` with a strict schema): name, title, description, tags, inputs, outputs and body.
- **Server-side refusal fallback:** enabled (`fallbacks: :default`, beta `server-side-fallback-2026-07-01`).
- **What is sent:** only step keys, the catalog's plain-English description of each step (`SkillCapture::Catalog`), counts, dates and reviewer notes. No record contents, names or emails.
- **Fallback:** any API error, refusal, truncation or unparseable reply falls back to the deterministic template. A skill can always be drafted.

## API (session-authenticated JSON)

| Method & path | Purpose |
|---|---|
| `GET /skill_candidates.json?status=open` | Pending suggestions visible to the caller |
| `GET /skill_candidates/:id.json` | Candidate with draft and evidence |
| `POST /skill_candidates.json` | Request a skill manually (`skill_candidate[draft_title, domain, draft_description, draft_body, steps[]]`) |
| `POST /skill_candidates/:id/approve.json` | Publish (domain owner / admin) |
| `GET /skills.json?q=&domain=` | Published skills (for agents and the routing engine) |
| `GET /skills/:id.json` | Skill plus rendered `skill_md` |
| `GET /skills/:id/download` | `SKILL.md` file |

## Security & governance

- **Data minimization:** the collector stores controller, action, resource type and id, integer `*_id` params, and a short enum allowlist (`status`, `channel`, …). It stores no free text, names, emails, amounts or notes. A test (`skill_capture_flow_test.rb`) asserts this.
- **Request scope:** GETs, failed and unauthorized requests, sign-in, admin pages and the review UI are never captured.
- **Retention:** raw events are purged after `SKILL_CAPTURE_RETENTION_DAYS` (default 90) by the hourly sweep. Exported `SKILL.md` files leave out internal user ids.
- **Kill switch:** `SKILL_CAPTURE_ENABLED=false` stops both capture and sweeps.
- **Access control:**
  - Ops workflows are reviewed by ops and admin.
  - Sales workflows (CRM, quotes, contracts, tasks) are reviewed by sales and admin.
  - Finance workflows are reviewed by finance and admin.
  - Contributors and requesters can view a candidate but cannot approve it.
  - Only domain owners and admins can revise a skill. Only admins can deprecate one.
  - Everyone signed in can read the library.
- **Audit:** `skill_candidate.detected|drafted|requested|edited|approved|rejected|dismissed` and `skill.published|revised|forked|deprecated` go to the existing Audit Log.
- **Misuse alert:** more than `SKILL_CAPTURE_PUBLISH_ALERT_PER_HOUR` (default 10) publishes by one user in an hour writes `skill_capture.alert` and notifies admins.
- **IP:** skills default to `license: Proprietary - internal use only`.

## Observability

The Skill review page shows:
- candidates detected and open
- approval rate (approved ÷ decided)
- median hours from detection to approval
- published skill count

`SkillCapture::Metrics.summary` returns the same numbers plus the event volume for the last 7 days. The sweep logs pattern, new and updated counts.

## Operating it

```bash
bin/rails db:migrate
bin/rails skill_capture:simulate          # dev only: script a repeated workflow and sweep
bin/rails skill_capture:sweep             # run detection + drafting now (also runs hourly via Solid Queue)
bin/rails "skill_capture:export[skills]"  # write published skills to skills/<name>/SKILL.md
SKILL_CAPTURE_EXPORT_DIR=/srv/skill-repo  # also export automatically on every publish
```

`skills/` in this repo holds sample skills that the system produced from scripted workflows (template drafter, no LLM).

## Testing (spec §8 / Definition of Done)

- **Simulation and accuracy** (`test/services/skill_capture/workflow_detector_test.rb`): 5 scripted workflows plus noise. All 5 are captured (100%, against a ≥ 80% requirement) with no extra fragments or noise patterns (precision 100%). There are also tests for session gaps, duplicate collapsing, the people threshold, notifications and fragment suppression.
- **Drafting and publishing** (`test/services/skill_capture/draft_and_publish_test.rb`): template draft validity; the Claude request shape and the privacy of its payload (stubbed client); refusal fallback; provenance; versioning, forks and lineage; role enforcement; `SKILL.md` frontmatter and export.
- **End to end** (`test/integration/skill_capture_flow_test.rb`):
  1. A user repeats a task through the real controllers.
  2. The sweep proposes and drafts it.
  3. The wrong role cannot publish it; the domain owner edits and publishes it.
  4. Another user finds it through `/skills.json` and downloads the `SKILL.md`.

  The same file tests that the collector stores no submitted values.

## Open questions: MVP answers and what's next

- **Trigger sensitivity:** 3 occurrences, 1+ person, 2–6 steps, all set by env vars. Reviewer reject notes are kept so thresholds can be tuned from real precision data.
- **Contributor attribution:** every person whose sessions matched is recorded on the candidate and copied into the skill's `source.contributors`, and they are notified when it is published. Forks and revisions keep a parent link and `revised_from`.
- **Privacy:** only structure is captured, so skills never contain record data. Sending drafts to an LLM sends no user content.
- **MVP scope:** approval is manual. Automatic classification is limited to the domain (from the controllers involved), which routes the review.
- **Fallbacks for stale skills:** revise creates a new version and the old one stays in history. Deprecate retires a skill. A later candidate that reuses the name becomes the next version.
- **Not built yet:**
  - collectors outside this app (Office/Graph, Slack, IDE)
  - SSO (the app uses Devise logins)
  - indexing and routing hooks beyond the JSON API and the file export
  - a separate knowledge-council review cadence
