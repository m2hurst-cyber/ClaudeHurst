# AGENTS.md: Skill Capture for Microsoft Office

Brief for planning and coding agents. It records what this project is, what is built and how to verify it, the rules that must hold, and what is still open. Every claim here points at a file or a command, so it can be cross-checked.

> Status as of 2026-11-23, branch `claude/skill-capture-institutional-memory-b7ksev`, directory `skill-capture/`.
> The sibling Rails app at the repository root (a beverage copacker CRM-ERP) is a **separate, unrelated project**. Do not modify it, import from it, or reuse its accounts.

---

## 1. Product in one paragraph

An **Office add-in for Excel, Word and PowerPoint** that turns how a team works into reviewed, reusable procedures ("skills"). From a **Skills** button on the Home tab, people open a task pane where they can:
- browse the skill library, filtered by area, and insert a skill's steps into the document
- **record a procedure** (steps Office reports, plus steps they type)
- opt in to **passive capture** of step *types*
- as reviewers, approve or reject drafts

The server detects workflows repeated across people and drafts them with Claude, or with a template when Claude isn't configured. Published skills are versioned Agent Skills `SKILL.md` files. The Rails app hosts the add-in, serves its API, and is the admin and review web console.

This is **Step 1 (Skill Capture & Institutional Memory)** of a larger program. Later steps (for example a routing engine that uses skills) are not defined in this repository.

## 2. Stack and layout

- **Server:** Ruby 3.3, Rails 7.2, PostgreSQL, Hotwire, Tailwind v4, Devise, Pundit, Pagy, Solid Queue (in the main database), `anthropic` gem 2.12.
- **Add-in front end:** vanilla ES modules served through importmap (`app/javascript/addin/*`). Office.js is loaded from Microsoft's CDN. There is no bundler.
- **Node:** used only for the Office dev tooling and the JavaScript unit tests (`package.json`).

| Path | What it is |
|---|---|
| `app/views/addin/manifest.xml.erb` | Add-in-only XML manifest (`TaskPaneApp`; Workbook, Document and Presentation; long-lived runtime) generated for the serving origin |
| `app/controllers/addin_controller.rb`, `addin_connect_controller.rb` | Manifest, task pane and help pages; the sign-in dialog that issues tokens |
| `app/controllers/concerns/office_framing.rb` | Removes `X-Frame-Options` and allows only Office domains as `frame-ancestors`, on add-in pages only |
| `app/javascript/addin/capture.js` | Office-independent capture engine (dedupe, batching, recording). Unit-tested |
| `app/javascript/addin/office_hosts.js` | Office.js event wiring per host, gated by requirement set; dialog, insert-text and startup behavior |
| `app/javascript/addin/vocabulary.js` | Every step key the add-in can emit, with its label |
| `app/javascript/addin/taskpane.js` | Task pane UI (Library, Record, Review, Settings) |
| `app/controllers/api/v1/addin/*` | Add-in API (per-person bearer token) |
| `app/controllers/api/v1/*` (not `addin/`) | Optional integration API (per-integration token) |
| `app/services/capture/*` | Config, Ingestor, WorkflowDetector, DraftGenerator, ClaudeDrafter, TemplateDrafter, Publisher, SkillFile, Naming, Metrics, Addin |
| `app/models/*` | User, AddinToken, Source, ActionDefinition, UsageEvent, SkillCandidate, Skill, Notification, AuditLog |
| `app/policies/*` | SkillCandidatePolicy, SkillPolicy |
| `db/migrate/*` | Four migrations: Solid Queue tables, core tables, skill tables, add-in tokens |
| `lib/tasks/capture.rake` | `users:create`, `capture:sweep`, `capture:export`, `capture:demo` |
| `app/services/capture/route_map.rb`, `chain_detector.rb`, `route_planner.rb` | Route map: skills as roads, observed and manual links between them, branches, improvements, turn-by-turn planner |
| `app/models/skill_link.rb` | Roads between skills (by name; `observed` with traffic, or `manual`) |
| `app/services/capture/trip_matcher.rb` | Finds trips (a person doing a whole skill) with timing and the previous trip. Shared by chain detection and congestion |
| `app/services/capture/congestion.rb`, `bounties.rb`; `app/models/pricing_schedule.rb`, `skill_metric.rb`, `bounty.rb`, `credit_entry.rb` | Congestion pricing: travel time vs free-flow, the demand schedule, bounty lifecycle, credits ledger |
| `app/views/bounties/*`, `app/views/admin/pricing/*` | Bounties page; admin demand-schedule editor and chart |
| `app/models/field.rb`, `skill_classification.rb`; `app/services/capture/taxonomy.rb`, `classifier.rb`; `app/views/skill_maps/fields.html.erb` | Classification: field hierarchy and apps per skill (AI or rules, people confirm); By field view; filters |
| `app/models/promotion.rb`, `promotion_policy.rb`, `skill_vote.rb`; `app/services/capture/gates.rb`, `promotions.rb`, `voting.rb` | Gatekeeping: stages (local, firm, market), promotion gates and approvals, internal voting and Compare |
| `app/models/waypoint.rb`, `app/services/capture/directions.rb`, `map_search.rb`, `app/controllers/places_controller.rb` | Places on the map (`road:`, `junction:`, `handoff:` keys) with versioned agent directions, generated scaffolds, and search |
| `app/javascript/route_map/layout.js`, `app/javascript/controllers/route_map_controller.js` | Map layout (pure, tested) and SVG renderer (console `/map`) |
| `app/services/capture/skill_map.rb`, `app/views/skill_maps/areas.html.erb` | By-area view: where skills live, per area, with gaps (console `/map/areas`) |
| `docs/design.md` | Full design: architecture, data model, detection, privacy, tests |

## 3. Commands (run from `skill-capture/`)

```bash
bundle install && bin/rails db:prepare
bin/rails test                      # expected: 88 runs, 0 failures
npm install && npm test             # expected: 18 pass, 0 fail
bin/rails users:create EMAIL=a@example.org NAME="A" ROLE=admin   # prints a one-time password; no accounts are seeded
bin/addin-dev                       # https://localhost:3000 with Office dev cert (web + Tailwind + jobs)
bin/rails capture:demo              # development only: chained skills, a branch, an improvement, unpaved roads, 2 months of traffic with a jammed and a heavy skill (2 bounties)
npm run manifest && npm run validate   # Microsoft's online manifest validation (NOT yet run; see §8)
```

Database settings: `DATABASE_HOST`, `DATABASE_USER` and `DATABASE_PASSWORD` (defaults: localhost, postgres, postgres).

## 4. Invariants (must hold; tests enforce most)

1. **Privacy at capture.** Passive capture is **off until the person opts in** (Settings checkbox). Events carry only a step key, a label, a random session id, a timestamp and `context.app`. Never file names, sheet names, cell values or document text. Remote (co-author) changes are ignored. See `office_hosts.js` (`local()`) and `capture.test.mjs`.
2. **Privacy at the server.** `Capture::Ingestor` keeps only allowlisted context keys whose values are short tokens. It drops values that look like emails, including actor names, and caps batches at 500. See `ingestor_test.rb`.
3. **Attribution.** Add-in events are attributed server-side to the token's user (`actor_key = "user:<id>"`); any actor in the payload is ignored. See `office_addin_test.rb`.
4. **Tokens.** Add-in and integration tokens are stored only as SHA-256 digests and shown once.
   - Add-in tokens are per person per Office install. They are revocable, and they stop working when the user is deactivated.
   - The two token types are **not interchangeable**. Built-in Office sources can never authenticate the integration API.
5. **Framing.** Only add-in pages (`/addin/*`) may be framed, and only by Office domains. Console pages keep `X-Frame-Options: SAMEORIGIN`.
6. **No seeded credentials.** Every account comes from an admin (People page or `users:create`) with a generated one-time password.
7. **Published skills are immutable.**
   - Revising a skill under the same name creates version N+1 and marks the old version `superseded`.
   - Revising under a new name creates a fork with `parent_skill_id`.
   - Approving a candidate that reuses a published name creates the next version.
8. **Review routing.**
   - Reviewers act only on their `domains` (areas). Admins can act on everything.
   - Members can see only candidates they requested.
   - Only admins can deprecate skills, manage people or integrations, or read the audit log.
9. **What Claude receives.** The model request contains only step keys and labels, counts, dates and requester or reviewer notes. No actor ids or names, resource refs or context. The default model is `claude-opus-5-5`, with structured JSON output and the server-side refusal fallback. Any failure falls back to the template drafter.
10. **Manifest correctness.** HTTPS URLs on one origin, every `resid` resolves, icons exist, three hosts, a long-lived runtime per host. See `office_addin_test.rb`.
11. **Sandbox isolation.** Local skills never reach agents or people outside their area, contributors and admins. Every query that returns skills goes through `Skill.visible_to(user)`; `nil` means agents (firm and market only). New code that lists skills, places or links must do the same.
12. **People win over AI.** A classification a person set or confirmed (`confirmed: true`) is never overwritten by inference, except through an explicit "Re-infer".
13. **Promotion integrity.** No one approves their own request. A non-admin reviewer can't approve a skill they published. Only admins waive gates, and only with a written reason. Promotion is one stage at a time.
14. **Restricted resources stay restricted.** `ResourceFolder#visible_to?` walks the chain; restricted folders are never visible to agents (`nil` viewer) and never bundled for them. Resource downloads check the folder for the caller.
15. **Commands respect visibility.** `POST /map/send` refuses skills the target can't see; agents receive firm and market skills only. A command has exactly one target and expires after a day.
16. **Fields are many.** Classification writes go through `SkillClassification#set_fields!`, which keeps `field_id` equal to the primary field. Don't write `field_id` directly.
17. **History is never rewritten.** Reverting a rest stop publishes a new version; the state before the revert is saved (pinned) first. Manual, pinned and branch-point rest stops are never pruned. New code that changes a skill's content, directions, resources or fields should take a rest stop (`Capture::RestStops.capture!`, which skips unchanged states).
18. **Skills meet the Agent Skills format.** `Publisher` refuses names, descriptions or instructions that break `SkillStandard`'s required rules; drafts go through `SkillStandard.normalize`. `SKILL.md` metadata stays a flat map of strings.
19. **Prompts are judged before they're shown.** Triggers run at most every `evaluation.interval_minutes` per person in `PromptCheckJob`; nothing reaches a person until the evaluator opens it.
20. **Prompts only read a person's own events** (`actor_key = user:<id>`), never other people's, and only propose: every accepted prompt goes through review. A dismissed prompt is never raised again.
21. **Playbooks are files.** Content changes go in `playbooks/<key>/` (skills, `documents.yml`, `legs.yml`) and reach the app through `install!` (new versions, never edits); never hand-edit installed playbook skills in code.
22. **Return documents are protected.** `ReturnDocument` file, filename, payer and figures are encrypted (ActiveRecord encryption; production refuses to boot without the three `SKILL_CAPTURE_ENCRYPTION_*` keys). A return and its documents are visible only to the filer and the reviewer they chose; only the filer changes them. Identifiers (SSN/ITIN, EIN, account numbers) are never stored as figures or sent back from the AI: the catalog has no field for them and `ReturnDocument::IDENTIFIER` strips look-alikes. Document parameters are filtered from logs. The run reference refuses SSN/EIN/email look-alikes.
23. **A leg is done only when it verifies.** `Capture::Legs#verify_all!` runs after every change to documents, inputs, answers or attestations; progress counts verified legs. The review leg needs a second person's sign-off, invalidated by later document changes. The AI never marks anything done; it prepares figures, memos and issues, and blocking issues hold the leg until resolved.
24. **Isolation from the sibling app.** Nothing under `skill-capture/` references the repository-root application.

## 5. Spec cross-check (original Step 1 spec → status)

Legend: ✅ built and tested · 🟡 partial · ⛔ not built

| Spec item | Status | Evidence / notes |
|---|---|---|
| Activity monitor (Office add-in) | ✅ | Task pane plus Office.js wiring (`office_hosts.js`), opt-in, background capture via the shared runtime and `setStartupBehavior` |
| Activity monitor (Slack, email, IDE, browser) | ⛔ by decision | Product is positioned as an Office add-in. An optional integration API exists (`POST /api/v1/events`) |
| Trigger detection (repeated tasks) | ✅ | `WorkflowDetector`: sessions, collapsed duplicates, maximal sequences, long workflows stitched back together. `workflow_detector_test.rb`: 5/5 scripted workflows found with no extras (spec requires ≥ 80%) |
| Capture & summarize with AI | ✅ / 🟡 | `ClaudeDrafter` is tested only against a stubbed client. **Never called against the live API** (no key in the build environment) |
| Skill metadata (Agent Skills frontmatter) | ✅ | `skills` table, `SkillFile.render`, download and export |
| Inputs, outputs, source (who and when) | ✅ | `draft_inputs/outputs`; `skills.source` provenance (contributors, workflow, counts, dates, drafter) |
| User review workflow and notifications | ✅ | Console Review page plus the pane's Review tab; in-app notifications to area reviewers |
| Tagging and categorization | ✅ | Tags and area (domain) |
| Linking to related documentation | ⛔ | Not modeled |
| Visual map of how skills connect (journeys, branches, improvements) | ✅ | Console **Map → Routes** (`/map`, `/map.json`, `/map/route`), skill-page "On the map" panel, add-in "people usually continue with". `route_map_test.rb`, `route_map.test.mjs` |
| Filterable hierarchy by app and by field (Finance › Accounting …), set by people and inferred by AI | ✅ | `Field`, `SkillClassification`, `Classifier`; library, map filters, **By field** view, add-in host filter, `?app=&field=` and `/api/v1/fields`. `classification_test.rb` |
| Gatekeeping (sandbox → firm → market) | ✅ | `skills.stage`, `Skill.visible_to`, `Promotion`, `Gates`, Promotions queue, Admin → Gates, `/api/v1/market`. `gatekeeping_test.rb` |
| Internal voting on which process is better | ✅ | `SkillVote`, `Voting.comparison`, `/skills/:id/compare`, add-in vote. `gatekeeping_test.rb` |
| Searchable roads and intersections with their own agent Markdown directions | ✅ | `Waypoint`, `Directions`, `MapSearch`; map search and intersection nodes, `/map/places/<key>`, `/api/v1/search`, `/api/v1/places/<key>.md`, route directions. `directions_test.rb` |
| Demand-schedule (congestion) pricing with incentives to fix bottlenecks | ✅ | `Congestion`, `PricingSchedule`, `Bounties`; Bounties page, map Traffic view, Admin → Pricing. `congestion_pricing_test.rb`, `pricing_ui_test.rb` |
| Visual of where skills live (by area) | ✅ | **Map → By area** (`/map/areas`) and add-in area chips. `skill_map_test.rb` |
| Institutional memory (discoverable, origin preserved) | ✅ | Library (console and pane), `GET /api/v1/skills`, provenance, contributors notified when published |
| Data storage | ✅ | PostgreSQL. No knowledge graph (not needed at MVP scale) |
| Version control and forks | ✅ | Versions, forks, lineage view |
| API | ✅ | Add-in API plus integration API (§6) |
| Enterprise SSO | ⛔ | Devise email and password; the add-in uses dialog sign-in. Next step: Microsoft Entra SSO (`Office.auth.getAccessToken`) |
| Data privacy, retention, masking | ✅ | §4.1–4.2; 90-day retention purge in `CaptureSweepJob` |
| Access control and audit | ✅ | Pundit policies; `AuditLog` covers detection, drafts, review, publishing, tokens, people and sources |
| IP / licensing | 🟡 | Default `license: Proprietary - internal use only`. No contributor agreement flow |
| Governance (knowledge council) | ⛔ | Only per-area reviewers |
| Metrics | ✅ | `Capture::Metrics` (detected, open, approval rate, median hours to approval, events in 7 days) |
| Misuse alerts | ✅ | Publish rate per user; ingest volume per integration |
| Precision and coverage metrics from real use | ⛔ | Reject notes are stored; no reporting yet |
| Definition of Done: end-to-end demo | ✅ (simulated) | `capture_flow_test.rb`, `office_addin_test.rb`, plus a manual browser run against a simulated Excel host |
| Definition of Done: stakeholder security sign-off | ⛔ | Requires humans |

## 6. API contracts (summary)

**Add-in API** (`Authorization: Bearer sca_…`, issued by `POST /addin/connect` after Devise sign-in in an Office dialog):

| Method & path | Purpose |
|---|---|
| `GET /api/v1/addin/me` | `{name, role, domains, reviewer, capture_enabled, console_url, open_reviews}` |
| `DELETE /api/v1/addin/me` | Revoke this token |
| `POST /api/v1/addin/events` | Body `{host: "Excel" \| "Word" \| "PowerPoint", events: [{action, label, session, occurred_at, domain?, context?}]}`. Returns 202 with `{accepted, rejected[], dropped_fields}` |
| `GET /api/v1/addin/skills?q=&domain=` and `GET /api/v1/addin/skills/:name` | Library search, optionally filtered by area; current published version with its body |
| `GET /api/v1/addin/areas` | Areas that have published skills: `[{name, published}]` |
| `GET /api/v1/addin/candidates` and `GET /api/v1/addin/candidates/:id` | Open review items for the caller |
| `POST /api/v1/addin/candidates/:id/approve` and `/reject` | Review actions |
| `POST /api/v1/addin/procedures` | Body `{host, title, domain?, description?, steps: [{action, label}]}` (at most 40 steps). Creates a manual candidate |

**Integration API** (`Authorization: Bearer sc_…`):

| Method & path | Purpose |
|---|---|
| `POST /api/v1/events` | Same event shape plus `actor: {id, name?}` |
| `GET /api/v1/skills` and `GET /api/v1/skills/:name` | Same library data; `:name` returns the current version with `skill_md` |

**Places and search** (integration token):
- `GET /api/v1/search?q=` returns `[{key, kind, label, title, subtitle, written}]`.
- `GET /api/v1/places/<key>` returns `{key, kind, title, written, version, markdown, …}`; add `.md` for raw Markdown.
- Keys are `road:<skill>`, `junction:<skill>` and `handoff:<from>><to>`. URL-encode `>` as `%3E`.

**Route API** (integration token): `GET /api/v1/route?from=<skill>&to=<skill>` returns `{skills: [...names], legs: [{from, to, traffic, manual}], directions: [{key, kind, title, written, markdown}]}`, where directions run road → intersection → handoff → … → road, or 404 when there is no known road. Published skills only.

**Resources, commands and bundles:**

| Method & path | Token | Purpose |
|---|---|---|
| `GET /api/v1/addin/commands?host=&platform=` | add-in | Pending commands for this person; marks them delivered; returns `{commands: [{id, kind, from, bundles: [...]}]}` |
| `GET /api/v1/addin/bundles/:name` | add-in | One bundle: `{name, version, title, stage, fields, apps, skill_md, directions: [{key, kind, markdown}], resources: [{key, name, url}]}` |
| `GET /api/v1/addin/resources/:id/download` | add-in | The file, if its folder is visible to the person |
| `GET /api/v1/commands` | integration | Pending commands routed to this agent, with bundles |
| `GET /api/v1/bundles/:name` | integration | Bundle (firm or market skills only) |
| `GET /api/v1/resources` and `GET /api/v1/resources/<folder path>/<slug>` | integration | Firm resources; the file itself for a key |

**Prompts and rest stops:**

| Method & path | Token | Purpose |
|---|---|---|
| `GET /api/v1/addin/prompts` | add-in | Open save/extend/branch prompts: `[{id, kind, headline, skill, skill_title, occurrences, steps: [{action, label}], added, removed, choices}]` |
| `POST /api/v1/addin/prompts/:id/respond` | add-in | `{choice: save\|extend\|branch\|snooze\|dismiss, title?}` → `{status, candidate?: {id, title, name, url}}` |
| `POST /api/v1/addin/events` | add-in | Response carries `prompt_check: queued\|not_due` (triggers run in the background, at most every 10 minutes per person) |
| `GET /api/v1/skills/:name/rest_stops`, `GET /api/v1/rest_stops/:id` | integration | Rest stops of shared skills; `:id` includes the snapshot |

**Action keys** match `^[\w.:\-/#]{1,160}$`. Add-in keys come from `vocabulary.js`. Typed steps are `<host>.step:<slug>`.

## 7. Configuration (env vars)

| Variable | Default | Purpose |
|---|---|---|
| `SKILL_CAPTURE_PUBLIC_URL` | request origin | HTTPS origin written into the manifest (set this behind a proxy) |
| `SKILL_CAPTURE_ADDIN_ID` | fixed GUID | Use a different GUID per environment (dev, test, prod) |
| `SKILL_CAPTURE_ADDIN_VERSION` | `1.0.0.0` | Bump when the manifest changes |
| `SKILL_CAPTURE_ADDIN_PROVIDER` | `Skill Capture` | Provider name in the manifest |
| `SKILL_CAPTURE_ENABLED` | `true` | Global capture kill switch |
| `SKILL_CAPTURE_MIN_OCCURRENCES` / `_MIN_ACTORS` | 3 / 1 | Detection thresholds |
| `SKILL_CAPTURE_MIN_STEPS` / `_MAX_STEPS` | 2 / 6 | Step window for detection |
| `SKILL_CAPTURE_SESSION_GAP_MINUTES` | 30 | Idle gap that ends a session |
| `SKILL_CAPTURE_LOOKBACK_DAYS` / `_RETENTION_DAYS` | 30 / 90 | How far back detection looks; how long raw events are kept |
| `SKILL_CAPTURE_CONTEXT_KEYS` | see `config.rb` | Context keys the server keeps |
| `SKILL_CAPTURE_MAX_BATCH` | 500 | Maximum events per request |
| `SKILL_CAPTURE_PUBLISH_ALERT_PER_HOUR` / `_INGEST_ALERT_PER_HOUR` | 10 / 50000 | Misuse alert thresholds |
| `ANTHROPIC_API_KEY` (or `ANTHROPIC_AUTH_TOKEN`) | unset | Enables Claude drafting |
| `SKILL_CAPTURE_AI_DOCUMENTS` | on (when an AI key is set) | `off` keeps uploaded return documents away from the AI: filers enter the boxes by hand |
| `SKILL_CAPTURE_ENCRYPTION_PRIMARY_KEY`, `_DETERMINISTIC_KEY`, `_KEY_DERIVATION_SALT` | dev/test defaults | Encryption of return documents; **required in production** (`bin/rails db:encryption:init`) |
| `SKILL_CAPTURE_PLAYBOOK_DIR` | `playbooks/` | Where playbooks are read from |
| `SKILL_CAPTURE_LLM=off` | unset | Disables Claude even when a key is set |
| `SKILL_CAPTURE_MODEL` | `claude-opus-5-5` | Drafting model |
| `SKILL_CAPTURE_EXPORT_DIR` | unset | Write `SKILL.md` on every publish |
| `SKILL_CAPTURE_CHAIN_GAP_HOURS` | 24 | Maximum gap between two skills for them to count as one journey |
| `SKILL_CAPTURE_MIN_CHAIN_TRAFFIC` | 2 | Trips needed before an observed road appears |
| `SECRET_KEY_BASE` | none | Required in production (there is no credentials file) |

The full list is in `app/services/capture/config.rb` and `app/services/capture/addin.rb`.

## 8. Known gaps and risks (verify before planning on them)

1. **Never run in real Office.** Office.js (`appsforoffice.microsoft.com`) and Microsoft Learn were unreachable from the build environment. Task pane behavior was verified only in Chromium against a simulated Excel host. Required next: sideload into Excel, Word and PowerPoint (web and desktop) and exercise every tab.
2. **Manifest not validated by Microsoft's service.** `office-addin-manifest info` and `office-addin-manifest-converter` both parsed it, but `npm run validate` (online) has not run. Note: the converter mapped the task pane action to a separate short-lived runtime. Confirm that the pane and the background capture share one runtime in real Office.
3. **Office.js API names come from `@types/office-js@1.0.522`**, not from live documentation. The requirement sets used are ExcelApi 1.7–1.13, WordApi 1.5–1.6, PowerPointApi 1.2 and SharedRuntime 1.1. Word support for the shared runtime is assumed; the code is guarded by `isSetSupported`.
4. **Claude drafting is untested live** (stubbed only). Validate output quality, latency and refusal handling with a real key.
5. **Capture granularity.** Office.js exposes document events, not ribbon commands or macro runs. Passive capture therefore sees coarse steps ("Enter or edit cell values"). Recorded procedures with typed steps carry the real know-how. The planner should treat recording as the primary capture path.
6. **PowerPoint** slide add and delete are inferred from the slide count on selection change, so they are heuristic.
7. **Outlook is not supported** (it needs a mail add-in manifest or the unified JSON manifest).
8. **No SSO.** Dialog sign-in with Devise. Third-party cookie restrictions don't affect the API (it uses bearer tokens), but sign-in happens in the dialog window.
9. **Detection runs in memory** over the lookback window (`WorkflowDetector#sessions` loads all events). Fine for MVP volumes; will need batching or SQL at scale.
10. **Route map limits.**
    - Chains are inferred only from *published or open* workflows matched exactly in event streams. A fork with steps identical to its parent's can't be told apart from it.
    - Chain detection, like workflow detection, runs in memory.
    - The layout is built for tens of skills per network. Hundreds will need clustering by area, or zoom levels.
11. **Template drafts are generic.** For real use, Claude or a human edit is expected.
12. **Classification limits.**
    - Rule-based inference is keyword matching and makes plausible mistakes. In the demo it put "Prepare the customer contract" under Sales, and a person corrected it to Legal › Contracts.
    - Claude inference is tested only with a stub.
    - Each skill has one field; there's no multi-field tagging, so use tags for that.
13. **Gatekeeping assumptions.**
    - The thresholds are first-pass defaults.
    - The sandbox usage gate counts trips over retained activity (90 days).
    - Votes are per skill name, so a heavily revised skill keeps its old votes.
    - Alternatives are defined by lineage (forks). Unrelated skills that do the same job won't appear in Compare unless one is branched from the other.
    - "Market" is a stage and an API or export; there's no external marketplace integration yet.
14. **Directions are only as good as what people write.** Generated scaffolds give structure and live numbers, but intersections need human decision rules before an agent can choose exits reliably. Search is keyword and full-text (Postgres), not semantic.
15. **Congestion pricing assumptions.**
    - Free-flow is each skill's own 20th-percentile travel time over 90 days, so a skill that has always been slow reads as free-flowing.
    - The index needs at least 5 trips in the 7-day window.
    - Credits are internal points; nothing converts them to money.
    - The payout formula, tiers and accrual rules are first-pass defaults, all admin-tunable, and need validating against real traffic.

## 9. Decisions the planner needs to make

- **Identity.** Microsoft Entra SSO, plus whether to drop email and password entirely.
- **Manifest format.** Stay on the XML manifest, or move to the unified JSON manifest (needed for Outlook, Teams and Copilot surfaces).
- **Distribution.** Centralized deployment only, or also AppSource.
- **Background capture default.** Is per-person opt-in enough, or should admins be able to turn it on for everyone (with notice)?
- **Taxonomy ownership.** Who curates the field tree, and should it align with an existing enterprise taxonomy (HR job families, process classification frameworks like APQC PCF)? Should a skill be allowed several fields?
- **What "market" means.** Another business unit, partners, a public marketplace, or selling skills? It decides the license gate, the review (legal or IP), and where `/api/v1/market` publishes.
- **Voting weight.** One person, one vote today. Should reviewers', frequent users' or bounty solvers' votes count more, and should votes expire when a skill changes materially?
- **Who owns directions.** Should every intersection with more than one exit require written decision rules before agents may drive it unattended, and who signs off on them (the area reviewer, or the owners of both ends)?
- **What credits are worth.** Recognition only, redeemable (training, time off, budget), or linked to compensation? And who funds them: is the pool notional, or charged to the teams that use the congested skill (a true toll)?
- **Pricing levers.** Should Step 2 routing actively divert work, people or agents to cheaper parallel branches (like Waze rerouting), and should prices ever be shown to the people doing the work, or only to process owners?
- **Journeys.** Should end-to-end processes become first-class (named journeys such as "Procure to pay", with owners and target routes), or stay emergent from traffic? This affects how Step 2 routes work.
- **Area taxonomy.** Areas are free text today (set on reviewers, events and requests). Should they become a managed list, a hierarchy (for example Finance → AP / AR), or come from Entra groups?
- **Governance.** Is there a knowledge-council review on top of per-area reviewers? What is the licensing or contributor agreement for published skills?
- **Hand-off to Step 2.** How does the routing engine consume skills (`GET /api/v1/skills`, the exported `SKILL.md` directory, or something else)?
- **Hosting.** Where it runs, the HTTPS domain, and the backup and retention policy.

## 10. Suggested next steps (ordered; dependencies in brackets)

1. Deploy to an HTTPS staging host. Run `npm run validate`. Sideload into Excel, Word and PowerPoint (web and desktop). Fix any API or manifest issues. [none]
2. Run with a real `ANTHROPIC_API_KEY` on recorded procedures, and review draft quality with two or three subject-matter experts. [1]
3. Add Entra SSO (`Office.auth.getAccessToken` plus server-side token validation), keeping per-install revocation. [decision: identity]
4. Pilot with one team (for example finance month-end). Measure procedures recorded, approval rate, time to approval and reuse (library opens and inserts). [1, 2]
5. Add usage metrics for skills (opens and inserts per skill) to feed the Step 2 routing engine. [decision: hand-off to Step 2]
6. Outlook support through the unified manifest. [decision: manifest format]
7. Move detection to SQL or batched processing before large rollouts. [4]

## 11. Rules for agents working in this directory

- Work only inside `skill-capture/`. Don't touch the repository-root application.
- Keep every invariant in §4. If a change affects one, update its test in the same change.
- Run `bin/rails test` and `npm test` before committing. Both must pass.
- Rails URL helpers treat a `domain:` option as a hostname. To filter by area, pass `params: { domain: … }` (see `skill_maps/show.html.erb`).
- New add-in step keys go in `vocabulary.js` with a human label, and must match the action-key format.
- Gate any new Office.js API with `Office.context.requirements.isSetSupported` and degrade gracefully.
- Never add seeded users, default passwords or committed secrets (`config/master.key` and `.env*` are git-ignored; credentials files are not used).

## Changelog: multi-field, resources, bridges, map → add-in

- Skills carry unlimited fields; people can create fields and subfields from the skill card.
- Resource library (`/resources`) with firm/restricted folders and `resource:` keys.
- Bridges: cross-app and cross-domain skills and roads, a ⇄ Bridges map filter.
- The map panel sends a skill or route to my add-in, a colleague's add-in, or an agent; the add-in keeps it in local memory (Memory tab, `window.SkillCaptureMemory`).
- The demo "Hex key worksheet" is the brand palette (hex codes, Office theme slots, chart series order, per-app usage, contrast checks), firm-wide in Design › Brand and attached to the chart and deck skills.
- `capture:demo` seeds journeys once; re-running keeps them (it used to invent backward roads).

## Changelog: protocols and rest stops

- Save / extend / branch protocols (`Protocol`, `SkillPrompt`, `Capture::Prompter`), answered in the add-in or on `/prompts`; admin thresholds at `/admin/protocols`.
- Candidates carry `proposal_kind` and `base_skill`; publishing an extend makes the next version, a branch a linked sandbox variant.
- Rest stops (`RestStop`, `Capture::RestStops`): automatic and manual snapshots, revert as a new version, branch start points, disk mirror with `capture:rest_stops:verify`, daily `RestStopSweepJob`. The map panel links each skill's rest stops.
- Add-in: prompt card, autosaved recordings, a fix for a library render race.

## Changelog: AI-evaluated prompts and the Agent Skills format

- Triggers run in the background at most every 10 minutes per person (`PromptCheckJob`, Protocol `evaluation`); Claude judges each pattern (worthwhile, kind, title, description, confidence) before it is shown; rules without an AI key.
- `Capture::SkillStandard`: Anthropic Agent Skills rules enforced at publish/revise, drafts normalized, checklist in review, badge on skills; `SKILL.md` metadata is a flat string map.

## Changelog: playbooks and the individual income tax return

- `Capture::Playbook` installs curated linear workflows from `playbooks/`; `Situation`, `PlaybookRun`, `Capture::SituationAdvisor`, `Capture::Situations`.
- The individual income tax playbook (10 mainline skills, 11 situation branches, 5 resource files); `/playbooks`, `/returns/:id`; `capture:playbooks:install|list`.
- Map layout: branches without their own inbound road sit beside their parent.

## Changelog: document upload and AI-prepared legs

- Returns take uploaded documents (PDF or image, encrypted); the AI reads each one into the catalog's boxes (`Capture::DocumentReader`), the filer confirms.
- Each leg is prepared by `Capture::LegPreparer` (Claude, or rules) following its skill, with figures from `legs.yml` totals, and verified by `Capture::Legs` checks (documents, ties, inputs, attestations, AI issues, prior legs, reviewer sign-off).
- Admin/env: `SKILL_CAPTURE_AI_DOCUMENTS=off` keeps documents away from the AI (manual entry); encryption keys required in production.
- Tests: 121 Rails runs, 23 JavaScript tests.
