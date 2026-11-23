# Skill Capture for Microsoft Office: design

Step 1 of the knowledge program: Skill Capture & Institutional Memory, delivered as an Office add-in.

```
 Excel / Word / PowerPoint
 ┌──────────────────────────────────────────────┐
 │ Skills task pane (Office.js)                  │
 │  • Library: search, read, insert steps        │
 │  • Record: observed steps + typed notes       │──► POST /api/v1/addin/procedures
 │  • Review: approve / reject (reviewers)       │──► /api/v1/addin/candidates
 │  • Capture my workflow (opt-in, background)   │──► POST /api/v1/addin/events
 └──────────────────────────────────────────────┘        (Bearer sca_… per person)
        ▲ sign-in via Office dialog (/addin/connect)
        │
 Rails app (this repo): hosts the add-in (manifest, pane, icons) + API + web console
        │
 Ingestor ─► usage_events ─► WorkflowDetector (hourly) ─► skill_candidates ─► DraftGenerator (Claude / template)
                                                                   │
                                     review (pane or console) ─► Publisher ─► skills (versions, forks) ─► SKILL.md
```

## The add-in

| Piece | Where |
|---|---|
| Manifest (add-in-only XML, `TaskPaneApp`, hosts Workbook/Document/Presentation) | `GET /addin/manifest.xml`, generated for the serving origin (`app/views/addin/manifest.xml.erb`) |
| Ribbon | A **Skills** button in a *Skill Capture* group on the Home tab of each host, opening the task pane |
| Shared runtime | `<Runtime lifetime="long">` on each host, so when the person turns capture on, `Office.addin.setStartupBehavior(load)` keeps capturing while the pane is closed |
| Task pane | `GET /addin/taskpane` loads Office.js from Microsoft's CDN, then `app/javascript/addin/taskpane.js` |
| Capture engine | `addin/capture.js`: no Office dependency, unit-tested with `npm test` |
| Office wiring | `addin/office_hosts.js`: each event is registered only if its requirement set is supported, and remote (co-author) changes are ignored |
| Sign-in | The pane opens `/addin/connect` with `displayDialogAsync`. The person signs in and confirms, and the page `messageParent`s a personal token. Tokens are stored hashed (`addin_tokens`) and can be revoked from the pane or from *Connected Office apps* in the console |
| Framing | Add-in pages drop `X-Frame-Options` and send `frame-ancestors` limited to Office domains. Console pages remain `SAMEORIGIN` |

### What the add-in can observe

Office.js exposes document events, not ribbon clicks or macro runs. So a recorded procedure combines **observed steps** with the expert's own **typed steps**.

| Host | Steps captured (requirement set) |
|---|---|
| Excel | worksheet added, deleted or switched (1.7); cell edits and row, column and cell inserts or deletes (1.9 `onChanged`); format changes (1.9); sorts (1.10); hidden rows (1.11); formula changes (1.13); tables added or deleted (1.9) |
| Word | paragraphs added, edited or deleted (1.6); content controls added (1.5) |
| PowerPoint | slides added or deleted, inferred from the slide count on selection change (1.2) |

Noise control in the client:
- Consecutive duplicate steps are dropped.
- A formula change replaces the generic cell edit fired by the same keystroke.
- Events are sent in batches (every 15 seconds, at 50 events, and when the pane closes), with a bounded retry queue.

### Privacy

Capture is **off until the person turns it on**, and an admin can disable it for everyone (`SKILL_CAPTURE_ENABLED=false`).

Events carry only:
- the step key and label
- a random session id
- a timestamp
- `context.app`

Add-in events are always attributed server-side to the connected person; any actor in the payload is ignored. Typed steps in a recorded procedure are sent as written, because the person submits them deliberately.

## How the spec maps to this build

| Spec | Implementation |
|---|---|
| Activity monitor (Office add-in) | The task pane plus the shared runtime, per-person, opt-in |
| Trigger detection | `Capture::WorkflowDetector` (detects repeats across people), plus explicit recording |
| Capture & summarize | `DraftGenerator` → Claude (structured output) or the template |
| Skill metadata | Agent Skills frontmatter on `skills` |
| User review workflow | The pane's Review tab and the console's Review page, routed by area |
| Institutional memory | The pane's Library, the console Library, `SKILL.md` download and export, and the API |
| Auth | Devise sign-in (console and add-in dialog), per-person add-in tokens, per-integration tokens, Pundit |

## Data model

- **sources**: where events come from. There is one built-in source per Office app (`Skill Capture for Excel`, and so on), plus optional server-side integrations, each with its own hashed token.
- **addin_tokens**: one row per connected Office install. Holds the user, `token_digest`, host, platform, `last_used_at` and `revoked_at`.
- **action_definitions**: what each action key means (`label`) and which area it belongs to (`domain`). Collectors can register labels. Admin edits are never overwritten by a collector.
- **usage_events**:

  | Field | Meaning |
  |---|---|
  | `source_id` | The collector that sent the event |
  | `actor_key` | `user:<id>` for the add-in; pseudonymous ids for integrations |
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
5. Keep only maximal sequences. Join overlapping windows of a workflow longer than the window into one workflow. Never re-propose a fragment of a workflow that was already reviewed.

Recorded procedures skip detection and go straight to review.

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
- **Add-in auth:** each person gets a token per Office install, issued only after they sign in and confirm in the Office dialog. Tokens are stored hashed and revocable. They stop working when the person is deactivated, and they can't be used on the integration API.
- **Integration auth:** each integration has its own revocable token, stored hashed. Batches are capped at 500 events. An unusual event volume from one source alerts admins.
- **People auth:** accounts are created by an admin, with a generated one-time password. No credentials are seeded. Inactive users can't sign in.
- **Authorization:**
  - Reviewers publish and revise only in their own areas. Admins can do so anywhere.
  - Members can see only their own requests.
  - Only admins can deprecate skills, manage sources and people, or read the audit log.
- **Audit:** detection, drafting, requests, edits, approvals, rejections, publishes, revisions, forks, deprecations, and source and user changes are all logged.
- **Misuse alert:** more than 10 publishes by one person in an hour notifies admins.
- **IP:** skills default to `Proprietary - internal use only`.

## Tests

- `test/integration/office_addin_test.rb`:
  - the manifest: well-formed XML, `TaskPaneApp`, the three hosts, a long-lived runtime per host, every `resid` resolves, every URL is HTTPS on the serving origin, and the icons exist
  - Office framing headers
  - the connect flow and token lifecycle
  - attribution of add-in events
  - recorded procedures
  - pane library and review, with role checks
- `test/javascript/capture.test.mjs` (`npm test`): batching, dedupe, formula-over-edit replacement, retry, recording, the key format and Markdown escaping.
- `test/services/*`: detection (five scripted workflows plus noise, all captured with no extras, and long workflows stitched), ingest minimization, drafting (with a stubbed Claude client), publishing, versions and forks.
- `test/integration/capture_flow_test.rb`: the console and integration API end to end.
- **Manual browser check during development:** the real task pane in Chromium at 350 px wide, with Office.js replaced by a simulated Excel host (Microsoft's CDN isn't reachable from the build environment). It covered dialog sign-in, opting in (startup behavior set to `Load`), local versus remote events, recording and submitting, approving in the pane, and inserting steps.
- **Not yet done:** the manifest has been parsed by Microsoft's `office-addin-manifest` and `office-addin-manifest-converter`, but not run through Microsoft's online validation service. Run `npm run validate` before deploying, then sideload into real Excel, Word and PowerPoint.

## Open questions: current answers

- **Trigger sensitivity:** set by frequency, by number of people, and by a minimum step count. All three can be tuned per deployment. Reject notes are kept so the thresholds can be tuned later.
- **Attribution:** contributors are recorded on the candidate and copied into the skill's provenance. Forks and revisions keep parent links.
- **Privacy trade-offs:** capture is opt-in per person, and only step types are captured, so skills can't leak document content. Integrations should send pseudonymous actor ids.
- **MVP scope:** approval is manual. Areas route review automatically. Experts can also skip detection by recording a procedure in the add-in.
- **Stale skills:** handled by revising (which creates a new version), deprecating, or a later candidate that reuses the name.

## Not yet built

- Microsoft Entra single sign-on (`Office.auth.getAccessToken`) in place of the dialog sign-in.
- Outlook. It needs a separate mail add-in manifest, or a move to the unified JSON manifest.
- Teams and Copilot surfaces through the unified manifest. The converter output shows that the XML manifest converts cleanly.
- Push notifications outside Office and the console.
