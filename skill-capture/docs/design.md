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

## Route map (how skills connect end to end)

Like a navigation map: skills are roads, and journeys are the sequences people actually travel.

| Map element | Source |
|---|---|
| **Road (skill)** | Each current published skill, colored by area. Hue slots are assigned by sorted area name, so a color never changes on filtering. Past 8 areas the rest share "Other" gray |
| **Road between skills** | `SkillLink` (`from_node` → `to_node`), by skill *name*, so links survive new versions |
| Observed traffic | `Capture::ChainDetector` (runs in the hourly sweep and in `capture:sweep`). It lines up each person's events, finds where each skill's or open workflow's steps occur contiguously, and counts consecutive different skills no more than `SKILL_CAPTURE_CHAIN_GAP_HOURS` (24) apart. A road needs `SKILL_CAPTURE_MIN_CHAIN_TRAFFIC` (2) trips. Observed links are recomputed each run |
| Manual links | Reviewers add or remove them on the skill page ("Add what comes next…") |
| **Branch** | A fork (`parent_skill` with a different name), drawn as a dotted side road. The variant runs parallel to its parent (same column) |
| **Improvement** | The number of earlier versions of the same name, shown as "improved ×N" |
| **Unpaved road** | An open (detected or drafted) workflow, visible only to people allowed to see it (policy scope) |
| **Route planner** | `Capture::RoutePlanner`: Dijkstra over "next" roads. Fewest hops wins, and among equal hops the busiest roads win. Served at `GET /map/route` (console) and `GET /api/v1/route` (integration token, published skills only, for agents and the Step 2 routing engine) |

The layout is `app/javascript/route_map/layout.js`. Each connected network is laid out on its own: a skill's column is the longest chain of roads leading to it (loops broken), rows are ordered by barycenter sweeps, networks are stacked biggest first, and unconnected skills go in a final grid. Rendering is SVG (`route_map_controller.js`) with:
- pan and zoom, and a minimum readable scale on small screens
- hover and focus tooltips
- click to see "where people go next / come from"
- legend chips that focus one area
- a "Show as list" text alternative

A known limit: a fork whose steps are identical to its parent's can't be told apart from activity. Its traffic is credited to one of the two. A real variant usually adds or changes steps.

## Places and agent directions (roads, intersections, handoffs)

Every place on the route map is addressable by a key and carries its own Markdown directions for agents (and people):

| Key | Place | Directions answer |
|---|---|---|
| `road:<skill>` | A skill's road | How to drive it: before you start, drive, watch for, done when |
| `junction:<skill>` | The intersection at the end of a skill | Which exit to take: decision rules, default exit, and what to do if no exit fits |
| `handoff:<from>><to>` | The connector between two skills | What to hand over, who to notify, typical wait |

How it works:
- **Written directions:** stored in `Waypoint` (title, body, tags, version) with a `WaypointRevision` per save, audited.
- **Generated scaffolds:** `Capture::Directions` builds directions from live data for any place nobody has written yet: exits with their traffic share and price, predecessors, inputs and outputs, congestion and bounty, and reviewer names. It says plainly that it was generated.
- **Who can write:** reviewers of the skill's area (for a handoff, either end) and admins. Everyone signed in can read.
- **Search:** `Capture::MapSearch` matches skill titles, names, descriptions and tags (for roads, their intersections and their handoffs). It also runs Postgres full-text over written directions, using a GIN index on title and body, plus exact tag matches.
- **On the map:** a search box finds and centers a place. Intersections are drawn as ringed nodes at the end of each road that has exits (filled when directions are written). Clicking a road, intersection or handoff opens its rendered directions, with Edit and `.md` links.
- **Console pages:**
  - `/map/places/<key>`: rendered directions, history and links
  - `/map/places/<key>/edit`
  - `/map/places/<key>.md`: raw Markdown
  - `/map/search`
- **API** (integration token):
  - `GET /api/v1/search?q=`
  - `GET /api/v1/places/<key>(.md)`
  - `GET /api/v1/route` now includes `directions`: road → intersection → handoff → road … → arrival, each with its Markdown
- **Add-in:** a skill shows its road directions (if written) and "At the end of this road: which way next" (the intersection).
- **Export:** `capture:export` writes `<skill>/ROAD.md`, `<skill>/INTERSECTION.md` and `handoffs/<from>--<to>.md` next to each `SKILL.md`.

## Classification: field hierarchy and apps

**Taxonomy.** `Field` is a tree with `path` (slugs joined by `/`, re-computed for the whole branch on rename or move), `keywords` and `position`. It ships with Finance, Data analysis, Design, Legal, Sales and Operations, each with subfields (`Capture::Taxonomy`). Admins edit it at **Admin → Fields**: add, rename, move, keywords, remove. A field with subfields can't be removed; removing a field un-sets the classifications that weren't confirmed by a person.

**Classification** (`SkillClassification`, by skill name, so it carries across versions):

| Column | Meaning |
|---|---|
| `fields` | Any number of fields, ordered (`skill_field_assignments`); the first is the primary, mirrored in `field_id` |
| `apps` | The apps the skill uses |
| `source` | `ai`, `rules` or `user` |
| `confidence`, `rationale` | How sure the inference was, and why |
| `confirmed` | Whether a person set or confirmed it |

**Inference** (`Capture::Classifier`):
- **Apps:** apps seen in the workflow's step keys (`excel.*`, `word.*`, `powerpoint.*`, `outlook.*`, …), plus apps named in the text.
- **Field with Claude:** Claude gets the skill's title, description, area and step labels plus the taxonomy, and must answer with structured output whose `field_path` is an enum of the taxonomy's paths (or `none`), with apps, confidence and rationale. It uses effort low and the server-side refusal fallback.
- **Field with rules:** keyword hits (title weighted ×2), plus the ancestors' evidence, plus a bonus when the skill's area matches a top-level field. Confidence is 0.35 + 0.08 × score, capped at 0.85.
- **When it runs:** on every publish (rules inline; Claude through `ClassifySkillJob`) and in the hourly sweep for unclassified skills.
- **People win:** inference never overwrites a confirmed classification (it only merges in newly observed apps). "Re-infer" unlocks it explicitly.

**Many fields, user-made fields.** A skill can sit in as many fields as it really belongs to (Finance › FP&A *and* Design › Presentation design). Inference proposes up to three (rules keep matches scoring at least 60% of the best and drop ancestors/descendants of a match; Claude answers a `field_paths` array restricted to the taxonomy enum). On the skill card, anyone who can classify can tick fields off, add an existing field, or **create a new field or subfield** under any node; it's stored with `created_by` and is immediately usable by everyone. Admins still curate the tree.

**Who can change it:** the skill's area reviewers, its publisher, its contributors and admins (`SkillPolicy#classify?`). They can set the field and apps (`source: user`), confirm an inference, or re-infer. Every change is audited.

**Where it's used:**
- **Skill cards:** the library, the By field view and Compare show the field breadcrumb, app chips and the source badge (✨ Inferred · confidence, or ✓ Set or Confirmed by a name).
- **Filters:**
  - `Skill.classified_as(app:, field:)`, where a field includes its subfields
  - library (`?app=&field=&stage=&domain=`)
  - routes map (app chips, a field tree with counts, stage chips, dim or "Hide non-matching" which redraws the map; state lives in the URL)
  - **Map → By field** (`/map/fields`): the hierarchy with skills at each node, filters for app and stage, and "Routes" links into the filtered map
  - add-in (`?app=`; defaults to the host app)
  - integration API (`?app=&field=`)
- **API:** `GET /api/v1/fields` returns the taxonomy. Skills in every API carry `field`, `field_label`, `apps` and `classified_by`.

## Bridges (skills and roads that cross)

A **bridge** is where work crosses from one domain or app to another, like "collect the charts from the Excel workbook and deploy them as an appendix in PowerPoint, or as a report in Word".

- **Bridge skill:** a skill whose fields have more than one root (Finance and Design), or that runs in more than one app. Its label lists apps in **step order** (`Excel → PowerPoint`, from the observed step keys); fields only when no app is crossed.
- **Bridge road:** a road between two skills where
  - the app the first skill **ends in** differs from the app the next **starts in** (Excel → PowerPoint), or
  - the two skills' fields part at the field or sub-field level (Finance → Legal, Accounting → Treasury). Two specialties of the same sub-field are neighbours, not a crossing.
- **On the map:** bridge roads are drawn as rails with a ⇄ marker; the **⇄ Bridges** filter shows only them and switches markers to their labels. Cards and the library show a "⇄ Bridge" badge.

## Resource library

Templates, worksheets and decks that skills use (customer contract, NDA, hex key worksheet…) live in **callable folders**.

- `ResourceFolder` is a tree. A folder is **firm** (everyone and agents) or **restricted** to areas (its people and admins; never agents). Restriction is inherited down the tree.
- `Resource` is a file (stored in the database, 15 MB max, checksum, versioned on replace) or an https link. Every resource has a stable key, `resource:<folder path>/<slug>`, that agents and the add-in call.
- `SkillResource` attaches resources to skills by name (so it carries across versions). The skill page has a Resources panel; resources appear in the map panel, in bundles and in the add-in memory.
- Who manages: reviewers of the folder's areas and admins; anyone who can see a firm folder can upload into it.

## Map → add-in: send a skill to local AI memory

Click a road (or an intersection, or a planned route) and the panel offers **Send to my add-in** or **Route to…** a colleague's add-in or an agent (integration source).

1. `POST /map/send` creates `AddinCommand`s (`load_skill` / `load_route`) for the target. It checks the target can see each skill; agents get shared stages only.
2. The add-in polls `GET /api/v1/addin/commands` every few seconds while connected (agents poll `GET /api/v1/commands`). Delivery marks the command delivered and returns **bundles**.
3. A bundle (`Capture::Bundle`) is `SKILL.md` + its road and intersection directions + its resources (with download URLs the receiver is allowed to fetch).
4. The add-in stores bundles in its local memory (`window.SkillCaptureMemory`, localStorage, newest first, max 50) and shows them on the **Memory** tab: insert steps, **Copy for AI** (the skill, directions and resources as one context block), open resources, forget.
5. The sender's panel polls `/map/sent` and shows "✓ Delivered to … now in its memory". Commands expire after a day.

## Gatekeeping: stages, promotions and voting

**Stages** (`skills.stage`):

| Stage | Who can see it | Agents |
|---|---|---|
| `local` (sandbox) | The publisher, contributors (`source.contributor_keys` includes `user:<id>`), people whose `domains` include the skill's area, and admins | No |
| `firm` | Everyone signed in | Yes |
| `market` | Everyone signed in | Yes, plus `GET /api/v1/market` (skill, `SKILL.md`, road directions) for a marketplace or partner catalog |

- **Starting stage:** new skills and new branches start at `PromotionPolicy.initial_stage` (`local`). A new version of a skill keeps its stage, so fixes go live, which keeps bounty measurement working. Existing skills were migrated to `firm`.
- **Visibility everywhere:** `Skill.visible_to(user)` (`nil` = agents = firm and market) is applied across the library, skill pages, map, area view, search, directions (including exits and predecessors inside generated scaffolds), bounties, the add-in and the integration API. Automatic `SKILL.md` export and `capture:export` write firm and market skills only.

**Promotions** (`Promotion`, `Capture::Promotions`, `Capture::Gates`):
- **Request:** anyone who can see a skill can request the next stage, with an optional pitch and an incumbent to replace from the same lineage. Only one open request per skill is allowed.
- **Gates:** evaluated live and snapshotted on decision:

  | To | Gates |
  |---|---|
  | Firm | Description of at least 40 characters (what and when); at least 2 steps; outputs stated; sandbox use of `firm_min_trips` trips by `firm_min_people` people (lifetime trips over retained activity); net votes of at least `firm_min_score` |
  | Market | `market_min_days` at Firm; net votes of at least `market_min_score`; traffic tier no worse than `market_max_tier`; a license that isn't internal or proprietary; written road directions (optional) |

- **Approvers:**
  - Firm: a reviewer of the skill's area who is neither the requester nor the publisher (admins may approve their own published skills).
  - Market: an admin who isn't the requester.
  - Declining needs a reason.
- **Waivers:** failed gates can be waived only by an admin, with a written reason (`waived: true`).
- **Replacing an incumbent:** approving a promotion that replaces an incumbent deprecates it (history is kept).
- **Notifications:** approvers are notified on request; contributors and the publisher on approval, and the requester on rejection.

**Voting** (`SkillVote`, `Capture::Voting`):
- One +1 or −1 per person per skill *name*, so it carries across versions, with an optional reason. It can be changed or cleared.
- You can't vote on a skill you published or contributed to, or one you can't see.
- **Compare** (`/skills/:id/compare`) shows a skill's *family*: every current skill sharing its lineage root (the skill and its branches). Each alternative is shown with its net votes, travel time, traffic tier, trips, steps, improvements and recent reasons.
- **Preferred:** the alternative with the highest net vote; ties go to the faster road, then the busier one. It can be proposed for the next stage, replacing the incumbent, in one click.

## Congestion pricing (demand schedule) and bounties

The goal is to price congested skills higher, so there's a visible incentive to fix the bottleneck.

**Measurement** (`Capture::Congestion`, runs in the hourly sweep after chain detection). `Capture::TripMatcher` finds each *trip* (a person doing a whole skill). Then:

| Measure | Definition |
|---|---|
| Travel time | Wait before starting (since the person's previous, different skill ended, within the chain gap) plus time doing it. Waits matter because handoffs, such as waiting on legal, are typical bottlenecks |
| Free-flow time | The 20th percentile of travel time over all retained activity (90 days), with a floor of 1 minute |
| Congestion index | Median travel time over the pricing window (7 days) ÷ free-flow |
| Delay | The excess over free-flow, summed over the window |
| Pricing threshold | A skill isn't priced until it has `min_trips` (5) trips in the window |

**Demand schedule** (`PricingSchedule`, one row, edited at **Admin → Pricing**). The price per trip is the base price × the multiplier of the highest tier the index reaches. Defaults:

| Index | Tier | Multiplier |
|---|---|---|
| 0 and up | Free-flowing | ×1 |
| 1.25 and up | Slow | ×1.5 |
| 1.75 and up | Heavy | ×2.5 |
| 3 and up | Jammed | ×4 |

The schedule is validated: the first tier starts at 0, tier keys are unique, and multipliers never fall as congestion rises. Tiers wear the fixed status palette with an icon and a label (green ●, yellow ▲, orange ▲, red ■).

**Bounties** (`Capture::Bounties`):

| Status | What happens |
|---|---|
| `open` | The skill reached `bounty_tier` (Heavy). The pool is seeded with the window's trips × premium (price − base) × `pool_share`, then each newly *received* trip adds its premium. Accrual counts arrival time, so late uploads still count, once. If the skill returns to free-flowing before any fix, the bounty closes |
| `measuring` | A new version of the skill, or a branch of it, was published. This happens automatically through `Publisher`. The solver is the requester of a "Fix this" proposal, otherwise the reviewer who revised or branched the skill. The baseline is the index at that moment |
| `awaiting_approval` | After `measure_min_trips` (5) trips on the skill or its branch (or `measure_max_days`, 21), the new index is computed. Improvement = (baseline − new) ÷ (baseline − 1), clamped to 0–1. Payout = pool × improvement. No improvement, or no traffic, reopens the bounty |
| `paid` | A reviewer of the area who is **not the solver** approves, and a `CreditEntry` is written. If the skill is still congested, the leftover pool carries into a new open bounty. Reviewers can reject a fix (reopens), and admins can close a bounty |

**Routing.** `RoutePlanner` adds 0.3 of a hop per tier above free-flowing when entering a skill. Among equally short routes, the less congested one wins, then the busier one.

**Where it shows:**
- the **Bounties** page (open bounties, measuring and approval, leaderboard, most congested)
- the map's **Traffic** mode, tooltips and panel
- the skill page's "Traffic & price" panel
- **Admin → Pricing** (schedule editor, a step chart of price against index with each skill plotted, and a table)
- the add-in's skill detail (tier, price, bounty, "Propose a faster way")
- `GET /api/v1/skills` (a `traffic` object per skill)

**Limits:**
- Free-flow comes from the skill's own history. A skill that has always been slow looks free-flowing; comparing across similar skills is a possible next step.
- Credits are internal points with no money attached.
- The person who caused delay isn't penalized, by design: prices signal *where* to invest, not who to blame.

## Skill map by area (where skills live)

Skills, candidates and reviewers all carry an **area** (`domain`). `Capture::SkillMap` rolls them up per area:

| Field | What it holds |
|---|---|
| Stage counts | Published, awaiting review (drafted), detected (not yet drafted) |
| Reviewers | The area's reviewers |
| Contributors | How many distinct people contributed |
| Office apps | Which apps the area's steps come from |
| Latest skills | The three most recently published |
| Gaps | No reviewer · repeated work with nothing published · no area assigned |

Where it shows:
- **Console:** `GET /map` (`SkillMapsController`), as stat tiles, a "Skills by area" stacked bar, a table view and one card per area. The bar uses a one-hue ordinal blue ramp, light to dark for detected, awaiting review and published (validated: monotone lightness, the light end at 2.11:1 on white). It has a legend, hover and focus tooltips, and gap warnings carry an icon and a label.
- **JSON:** `GET /map.json`.
- **Add-in:** `GET /api/v1/addin/areas` drives the area chips in the Library tab.

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
- `test/integration/skill_map_test.rb`: per-area rollup, gaps, the map page and JSON, and the add-in area filter.
- `test/integration/route_map_test.rb`: observed roads (traffic, minimum, gap), recomputation keeping manual links, branches, improvements, unpaved visibility, the planner (busier road wins, gaps), the agent route API, reviewer-drawn links and the add-in "next up".
- `test/integration/classification_test.rb`: taxonomy paths and re-pathing a branch, auto-classification on publish (field from text, apps from steps), Claude restricted to the taxonomy enum (stubbed), people win over inference (set, re-infer, confirm), editing permissions, library and map and By field filters, the agent and add-in filters and taxonomy API, and admin taxonomy editing.
- `test/integration/gatekeeping_test.rb`: starting stages and inheritance, local visibility (people, library, search, the agent API), the Local → Firm gates and approver rules, admin-only waivers with a reason, the Firm → Market gates (days, votes, traffic, license, directions), the market API, voting rules (own skill, visibility, change and clear), the comparison's preferred choice and replacing the incumbent, and the pages (stage panel, queue, decline needs a reason, admin gates, add-in voting).
- `test/integration/directions_test.rb`: generated scaffolds (exits and their share, the default exit, reviewers, predecessors, done-when), not-found keys, reviewer-only versioned writing, empty bodies refused, raw Markdown, search (roads, intersections, handoffs, full text inside directions), the agent search, place and route-with-directions APIs, map data and the add-in intersection.
- `test/services/congestion_pricing_test.rb`: the schedule (tiers, prices, validation), travel time against free-flow, waits as handoff delay, the pricing threshold, the full bounty lifecycle (open → accrue → fix → measure → approve → credits), self-approval refusal, ineffective fixes reopening, branch fixes, self-clearing, and congestion-aware routing.
- `test/integration/pricing_ui_test.rb`: bounties page, skill traffic panel, "Fix this" proposals, map traffic data, the admin schedule editor and its validation, and the skills API traffic object.
- `test/integration/bridges_resources_commands_test.rb`: bridge labels in step order, bridge roads (ends-in vs starts-in app, field partings), card badges, folder visibility (restricted vs agents), upload/link/version/attach/detach and permissions, sending to my add-in with bundle delivery and status, routing to a colleague or agent with sandbox protection.
- `test/javascript/memory.test.mjs`: the add-in memory store (replace by name, cap, context text).
- `test/javascript/route_map.test.mjs`: layout (journey order, parallel branches, loops, separate networks, loose skills) and road geometry.
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
