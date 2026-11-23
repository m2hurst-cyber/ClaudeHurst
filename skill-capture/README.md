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
- **Skill map by area.** The **By area** tab shows every area (finance, legal and so on). For each area it shows how many skills are published, awaiting review or only detected, who reviews it, who contributed, and which Office apps the work happens in. Areas with no reviewer, or with repeated work that hasn't been captured yet, are flagged as gaps. In the add-in, the Library tab filters by the same areas.
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
