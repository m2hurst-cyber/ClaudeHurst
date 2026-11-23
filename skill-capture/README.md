# Skill Capture for Microsoft Office

Skill Capture is an **Office add-in for Excel, Word and PowerPoint** that turns how your team works into reusable, reviewed procedures ("skills").

- **Find and follow skills.** The **Skills** button on the Home tab opens a task pane with your team's skill library. You can read a skill there, insert its steps into the document, or open it in the browser.
- **Record a procedure.** An expert starts recording and does the task once. The add-in lists each step Office reports, such as "Insert rows", "Sort data" or "Add a slide". The expert adds their own notes for the parts Office can't see, such as checks, decisions and where data comes from, then submits the procedure for review.
- **Capture repeated workflows (opt-in).** Anyone can turn on *Capture my workflow*. The add-in then shares the *types* of steps they take, never file names, sheet names, values or text, and changes made by co-authors are ignored. When several people repeat the same sequence, Skill Capture proposes it as a skill.
- **Review inside Office.** Reviewers see drafts for their areas in the pane and can approve or reject them there. Drafts are written by Claude when `ANTHROPIC_API_KEY` is set, otherwise by a built-in template.
- **Route map.** The web console's **Map** shows skills as a road network, like a navigation app:
  - each published skill is a stretch of road, colored by area
  - roads connect skills that people do one after another end to end, drawn thicker the more people take them
  - variants branch off their parent and run beside it, and improved skills carry an "improved ×N" badge
  - workflows still in review appear as unpaved roads
  - **Find route** gives turn-by-turn directions from one skill to another, and clicking a skill shows where people go next
  - reviewers can also draw a road by hand
  - in the add-in, each skill ends with "people usually continue with…"
- **Searchable roads and intersections, each with agent directions.** Every place on the map has its own Markdown directions:
  - each **road** (a skill): how to drive it, including tools, guardrails and when it's done
  - each **intersection** (the end of a skill): which exit to take, as decision rules
  - each **handoff** (the connector between two skills): what to pass on and who to notify

  Until a reviewer writes them, directions are generated from live data. Search covers titles and the full text of written directions. Agents read any place as Markdown (`GET /api/v1/places/<key>.md`), and routes come back with the full sequence of directions.
- **Classification and filterable hierarchy.** Every skill card shows:
  - **Field:** a place in an admin-editable hierarchy, for example *Finance › Accounting › Reconciliation*, *Data analysis › Statistics*, *Design › Presentation design*.
  - **Apps:** Excel, Word, PowerPoint, Outlook, Teams, Power BI, SharePoint.

  **How they're set:**
  - Inferred automatically on publish: by Claude choosing from the taxonomy as a closed list, or by keyword rules when Claude isn't configured. Shown as ✨ Inferred with a confidence and a reason.
  - Set or confirmed by the skill's area reviewers, publisher or contributors (shown as ✓). AI never overwrites a person's choice.
  - Apps seen in the skill's steps are always included.

  **Where you can filter by app, field (including subfields) and stage:**
  - the library
  - the routes map (with a field tree and counts, and hide-or-dim for non-matching roads; filters live in the URL)
  - a new **Map → By field** hierarchy view
  - the agent API
  - the Office add-in, which by default shows skills for the app it's running in
- **Gatekeeping: sandbox → firm → market.** Every skill has a stage:
  - **Local** (sandbox): visible to its authors, contributors, its area's people and admins; never to agents.
  - **Firm:** everyone in the firm, and agents through the API.
  - **Market:** promoted beyond the firm, through `GET /api/v1/market` and export.

  New skills and branches start Local, and a revision of a live skill keeps its stage. To move up, anyone who can see the skill requests a **promotion**, which shows live **gates**:
  - **To Firm:** says when to use it, has steps and outputs, used in the sandbox (3 trips by 2 people), net votes of at least +2. Approved by an area reviewer who didn't publish or request it.
  - **To Market:** 14 days at Firm, net votes of at least +5, traffic no worse than Slow, a shareable license, written road directions. Approved by an admin.

  Only admins can waive gates, with a reason. Thresholds are set at **Admin → Gates**.
- **Internal voting: which process is better.** Anyone who can see a skill votes 👍/👎 with an optional reason, though not on their own skill, in the console or the Office add-in. **Compare** puts a skill and its branches side by side with votes and evidence (travel time, traffic, trips, improvements), marks the colleagues' preferred one, and lets it be proposed for promotion, optionally **replacing** the incumbent (deprecated on approval).
- **Congestion pricing and bounties.**
  - Each skill is priced on a **demand schedule**: the slower it has become compared with its own free-flow time (counting the wait before it starts), the higher its price per trip.
  - On the map's **Traffic** view, roads turn green, yellow, orange or red, Waze-style.
  - The premium above the base price funds a **bounty** for that skill. Anyone can **Fix this** by proposing a faster version, a reviewer revision, or a faster branch.
  - After the fix, traffic is measured again, and the payout is the share of congestion actually removed. A reviewer approves it, and it can't be the solver.
  - Credits go to a ledger with a leaderboard.
  - The route planner steers around jammed skills when an equally short road exists.
  - Admins tune the schedule on **Pricing**.
- **Skill map by area.** The **By area** tab shows every area (finance, legal and so on). For each area it shows how many skills are published, awaiting review or only detected, who reviews it, who contributed, and which Office apps the work happens in. Areas with no reviewer, or with repeated work that hasn't been captured yet, are flagged as gaps. In the add-in, the Library tab filters by the same areas.
- **Many fields per skill, user-made fields.** A skill card holds as many fields and subfields as fit; people can add or create them, and AI inference proposes up to three.
- **Resource library.** Customer contracts, NDAs, the brand hex key worksheet (brand colors for Excel, PowerPoint and Word), workbooks and decks sit in callable folders (firm-wide or restricted to areas), each with a key like `resource:legal/templates/mutual-nda-template` that agents and the add-in fetch. Attach them to skills.
- **Bridges.** Skills and roads that cross apps (collect the charts from an Excel workbook into a PowerPoint appendix or a Word report) or domains (Finance → Legal) are drawn as ⇄ bridges and have their own map filter.
- **Click a road, send it to the AI.** From the map, send a skill or a whole route to your running Office add-in, a colleague's, or an agent. The add-in loads it, with its directions and resources, into its local memory (Memory tab, "Copy for AI").
- **Playbooks.** Curated, linear workflows kept as files in `playbooks/` and installed as skills, roads, directions and resources. The first is the **individual income tax return**, written the way a CPA runs it: engage the client → collect documents → organize the financial information → report income → deductions and credits → prepare → review (Form 8879) → e-file → pay → plan next year. Each tax situation (self-employment, investment sales, rentals, K-1s, HSA, education, Marketplace insurance, multi-state, foreign, extension, payment plan) is a branch that leaves after its step and rejoins the mainline. Work a return on **Playbooks**: answer the situation questions, follow the route with the CPA instructions and templates, send it to your Office add-in. On each return the filer **uploads the client's documents** (W-2s, 1099s, 1098s, the prepared 1040, the signed 8879, acknowledgments, payment confirmations); the AI reads each one into its boxes for the filer to confirm, then **prepares each leg** of the road following that leg's skill and lists issues, and every leg must **verify** (documents confirmed, figures that tie, inputs and attestations, a second preparer's sign-off) before it counts as done. Documents are encrypted and private to the filer and their reviewer. Describe anything the questions didn't cover and the AI advisor either matches an existing situation or proposes a **new branch** for the tax reviewers; once published, every later return is asked about it.
- **Agent Skills format.** Every skill is a `SKILL.md` in Anthropic's Agent Skills format: a valid name, a third-person description that says what it does and when to use it, and concise instructions with standard sections. Drafts are formatted automatically, reviewers see a checklist, and publishing refuses anything that breaks the required rules.
- **Save · Extend · Branch prompts.** Every 10 minutes at most per person, in the background, protocols look at that person's own work in the add-in, and the AI judges each pattern (is it a real skill, which kind, what to call it) before asking: *save* a workflow you keep repeating, *extend* a skill you keep adding the same steps to (its next version), or *branch* a skill you keep doing your own way (a variant that starts in the sandbox). Answer in the add-in or on **Prompts**; accepted prompts go to the area's reviewers. Admins tune the triggers on **Admin → Protocols**.
- **Rest stops.** Every skill gets restorable snapshots (text, steps, directions, resources, fields): before and after every change, when a branch starts, daily, and on demand. Revert to any rest stop (it publishes as the next version, never rewriting history), and branches can always go back to where they started. Each rest stop is checksummed and mirrored to disk; `bin/rails capture:rest_stops:verify` repairs either copy from the other. The add-in also autosaves unfinished recordings.
- **Output.** Every published skill is a versioned Agent Skills `SKILL.md`. People can download it, and agents can fetch it over the API.

The add-in is a set of web pages plus a manifest, all hosted by this Rails app. The same app is the **web console** for admins: people, add-in deployment, the full review workflow and the audit log. The design is in [docs/design.md](docs/design.md).

## Requirements

- **Office:** Microsoft 365 or Office 2021+ on Windows or Mac, or Office on the web.
- **What each feature needs:** capture of Excel events needs ExcelApi 1.7–1.13, Word events need WordApi 1.5–1.6, and PowerPoint needs PowerPointApi 1.2. Background capture (the add-in loading with the document) needs SharedRuntime 1.1. On older clients the pane still works; it captures less, and *Settings → What this version can see* shows exactly what.
- **Server:** Ruby 3.3, PostgreSQL, Node 18+ (Node is needed only for the Office dev tooling). The app must be served over **HTTPS**, because Office won't load add-ins over plain HTTP.

## Run it and sideload the add-in

```bash
bundle install && bin/rails db:prepare
bin/rails users:create EMAIL=you@example.org NAME="Your Name" ROLE=admin   # prints a one-time password
bin/addin-dev            # https://localhost:3000 with Office's trusted dev certificate (+ Tailwind + jobs)
```

Then add the add-in to Office:

- **Office on the web:** open a workbook and go to **Home → Add-ins → More add-ins → My add-ins → Upload my add-in**. Upload the manifest from <https://localhost:3000/addin/manifest.xml>.
- **Desktop:** `npm run manifest && npm run start:excel` (or `start:word`, `start:powerpoint`).

Next:
1. Click **Skills** on the Home tab and sign in. Sign-in opens in an Office dialog, and the pane then keeps its own revocable token.
2. To see detection and review with sample data, run `bin/rails capture:demo` (development only). It feeds sample Excel and Word workflows into the built-in sources and runs detection.

No accounts are seeded. Admins create people on **People** in the web console, and each new person gets a one-time password.

## Deploy to your organization

1. Serve the app over HTTPS. Behind a proxy, set `SKILL_CAPTURE_PUBLIC_URL=https://your-host`.
2. In the web console, open **Add-in**, download `manifest.xml`, and upload it in the **Microsoft 365 admin center → Settings → Integrated apps → Upload custom apps**.
3. Assign it to the users or groups who should get it. **Skills** then appears on their Home tab in Excel, Word and PowerPoint.

To run separate dev, test and production add-ins side by side, give each its own `SKILL_CAPTURE_ADDIN_ID` (a GUID) and bump `SKILL_CAPTURE_ADDIN_VERSION` when the manifest changes.

## Commands

| Command | What it does |
|---|---|
| `bin/rails capture:playbooks:install[individual-income-tax]` | Install or update a playbook as skills (an admin performs it; `ADMIN=email` to choose). `capture:playbooks:list` shows status |
| `bin/rails capture:rest_stops:verify` | Check every rest stop against its checksum and disk mirror; repair (`DRY_RUN=1` to report only) |
| `bin/rails test` | Rails tests (API, manifest, detection, publishing, privacy) |
| `npm test` | Tests for the add-in's JavaScript capture engine (Node) |
| `bin/addin-dev` | HTTPS dev server for sideloading |
| `npm run validate` | Validate `manifest.xml` with Microsoft's online validator |
| `bin/rails capture:sweep` | Detect repeated workflows and draft them now (also runs hourly) |
| `bin/rails "capture:export[dir]"` | Write published skills to `dir/<name>/SKILL.md` |

## Roles

| Role | Can do |
|---|---|
| member | Use the library, record procedures, opt in to capture, follow their own requests |
| reviewer | Everything a member can, plus approve, reject and revise skills in their **areas** (for example `finance`, `legal`) |
| admin | Everything, plus manage people and integrations, deploy the add-in, deprecate skills, and read the audit log |

## Integrations (optional)

Server-side tools such as Power Automate flows can also report steps. They send them to `POST /api/v1/events` with their own token (web console → **Integrations**). See `examples/integration_send_events.sh`.
