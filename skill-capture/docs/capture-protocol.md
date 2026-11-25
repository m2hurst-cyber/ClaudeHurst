# The capture protocol

When a skill is born, when it changes, when it splits, and how any of that is
proved to someone who does not trust us. This is the design note behind the
rules and triggers; it covers what the field does today, what we have, what is
missing, and what we are building.

---

## 1. What the field already does

**Process and task mining** (Celonis, UiPath) is the closest mature analogue to
our detection layer. The settled practice is two-layer: *process mining* takes a
top-down view of an end-to-end flow from system event logs, and *task mining*
works bottom-up from desktop activity to find the automatable steps inside it.
The vendors treat them as complementary, and the recommended order is
process-first, then drill into the expensive step. The hard prerequisite in
every guide is a **stable case identifier** — without one the event log cannot
be assembled into cases and the mining is noise.

*What we take from it:* our `UsageEvent.session_key` is the case id, and it is
the weakest link in the chain. The two-layer split also maps cleanly onto what
we already have — `ChainDetector` is process-level, `WorkflowDetector` is
task-level — but we do not currently *order* them, so we mine tasks everywhere
instead of mining tasks where the process says the cost is.

**Agent Skills** (the `SKILL.md` format we emit) is built on progressive
disclosure: metadata always loaded, body loaded on trigger, bundled resources
loaded on access, with a recommended body under 500 lines. Frontmatter is
`name` (≤64 chars) and `description` (≤1024 chars). Notably, the published
best-practice material says **nothing about versioning** — the format has no
opinion on what happens when a skill changes. That is our problem to solve, not
a gap we can fill by copying.

**Software supply chain** is the mature answer to "how is this proved". The
pattern is consistent across in-toto, SLSA and Sigstore:

- the artifact is identified by a **digest of its content**, not by a name;
- claims about it are **attestations** — signed statements of the form
  *(issuer, subject digest, predicate)*, wrapped in a standard envelope;
- signatures are recorded in an **append-only transparency log** (Rekor), so
  nobody — including the registry operator — can quietly rewrite history;
- the levels framework (SLSA) grades how much the provenance is actually worth.

Two lessons matter more than the mechanics. First, **provenance records how an
artifact was built, not how it reached you** — a 2026 incident shipped malware
with a passing attestation because nobody checked the signer against the
*expected* signer. Second, SLSA L1 requires only that provenance *exists*; it
does not require anyone to verify it. An unverified attestation is decoration.

**Blockchain**, stripped of the token, contributes exactly three ideas worth
having:

1. **Content addressing** — identity is the hash, so the same skill is the same
   thing in two organisations that share no database.
2. **Append-only, hash-linked history** — each entry commits to the previous
   one, so tampering is detectable without trusting the operator.
3. **External anchoring** — periodically publishing a root commits you to a
   history you cannot later revise.

All three are available without a chain. What a chain adds is a neutral place
to put the anchor and a settlement rail — useful later, not required now.

**ERC-8004 ("Trustless Agents")** is the most directly relevant decentralized
design: three registries — **identity** (each agent an ERC-721 whose tokenURI
points at a registration file), **reputation** (feedback with mandatory
provenance: agent, client, timestamp, value), and **validation** (a validator's
pass/fail verdict on an agent's work). The structural insight is the
**separation**: who you are, what people say about you, and what an independent
checker found are three different records with three different trust models,
and the application logic stays off-chain. Empirically the ecosystem is also a
warning: a study of live ERC-8004 registrations found many are placeholders.
Registration is not quality.

**Security is the live risk, not a hypothetical.** Recent work treats
`SKILL.md` itself as a semantic supply-chain surface: a short (~20-token)
trigger added to a skill can steer which skill a registry retrieves and selects,
and the authors evaded registry scanning defences between 36.5% and 100% of the
time. A large-scale scan found 26.1% of published skills carried at least one
vulnerability — prompt injection, data exfiltration, privilege escalation. The
framing that fits our product is the **consent gap**: the distance between what
the person approved and what the skill actually does. The proposed fix in the
literature is capability-based permissions plus mandatory vetting — i.e. a
skill should have to *declare* what it touches, and the declaration should be
checked against the text.

---

## 2. What we have

Strong, and further along than the gap analysis below suggests:

| Layer | What exists |
| --- | --- |
| Ingest | `Capture::Ingestor` — allowlisted keys, no free text, no emails, retention window |
| Task mining | `WorkflowDetector` — frequent contiguous sequences, maximal patterns, min occurrences × min actors |
| Process mining | `ChainDetector` — skill-to-skill transitions with traffic, drawn as the route map |
| Triggers | `Capture::Prompter` — per-person **save / extend / branch** with thresholds in editable `Protocol` rows, per-fingerprint dedupe, snooze and permanent dismissal, `MAX_OPEN = 5` |
| Judgement | `PromptEvaluator` — a model decides *worthwhile / which kind / title / description / confidence*, gated at `min_confidence`, with a deterministic rules fallback |
| Review | `SkillCandidate` → reviewer → `Skill`, with `proposal_kind` ∈ save/extend/branch and `base_skill` |
| Lineage | `Skill#parent_skill`, `root_name`, `alternatives`, `versions` |
| Gates | `Capture::Gates` — describes-use, has-steps, has-outputs, usage, votes for firm; age, votes, traffic tier, license, directions for market |
| Promotion | `Capture::Promotions` — separation of duties (not your own skill, not your own request), admin-only waivers with a written reason |
| History | `RestStop` — full snapshots, **SHA-256 checksum over canonical JSON**, mirrored to disk, revert-as-new-version |
| Economics | `SkillTransfer` escrow with canonical hashing, `PricingSchedule`, `SkillMetric`, intensity |
| Reach | MCP server (11 tools), `.md` everywhere, `AuditLog` |

The `RestStop` checksum and the escrow's canonical hash are the important
detail: **we already independently arrived at content hashing**, just in two
places, for two narrow purposes, over two different canonicalisations.

---

## 3. Where we fall short

### 3.1 Identity is a name in our database
A skill is `name + version` in one Postgres row. Nothing binds the *content* to
an identifier. Two firms cannot refer to the same skill; a transfer cannot be
verified after the fact; an export cannot be checked against what we published.
Everything in §1 under supply chain and blockchain is downstream of this one
missing field.

### 3.2 History is editable by whoever owns the database
`AuditLog` sits in the same database as the thing it describes. That is fine for
a single-tenant internal tool and worthless the moment anyone outside the firm
is asked to rely on it. We have no hash linking, no inclusion proof, no anchor.

### 3.3 Approval, usage and verification are conflated
We store a reviewer decision, votes, and metrics in three bespoke shapes.
ERC-8004's separation is better and costs us almost nothing: one **attestation**
record — *(issuer, subject content hash, kind, payload, signature)* — from which
reputation is *derived* rather than stored. Gates then stop being bespoke code
over bespoke tables and become predicates over attestations, which is what makes
them portable across firms.

### 3.4 The trigger set is too narrow, and all of it fires on creation
Today's triggers only ever ask *should this become a skill, or a version, or a
branch*. The four most valuable triggers in a mature system are all missing:

- **Drift** — people have stopped doing it the way the skill says. We have both
  sides of this comparison already (published `source.workflow` vs. observed
  sequences) and do not compute it. This is the single highest-value update
  trigger and it is nearly free.
- **Failure** — runs that error, stall or get abandoned should raise a fix
  prompt against the step that broke.
- **Staleness** — a skill whose last verified run, or whose referenced template,
  formula or resource, has aged past a threshold.
- **Cohort** — ten people doing something twice each currently fires nothing,
  because `min_repeats` is per person. At firm scale this is where most of the
  real skills are, and it needs a k-anonymity floor so it cannot be used to
  surveil one person.

### 3.5 Nothing learns from being ignored
Dismissals are recorded and never used. At ten users prompt fatigue is an
annoyance; at ten thousand it is the product failing. We need per-kind,
per-domain **precision** (accepted ÷ raised) feeding back into the thresholds,
so a trigger that keeps being wrong in one area raises its own bar.

### 3.6 Branching is one-way and version changes have no contract
We can branch but never **merge or adopt** — a branch that proves better cannot
become the trunk, and the incumbent cannot be retired by evidence. Separately, a
new version can silently change `inputs`/`outputs` while flows and MCP callers
depend on them. Schema-registry practice applies directly: every new version
declares whether it is **compatible** or **breaking**, and the system checks the
claim rather than trusting it.

### 3.7 No safety gate on the text
Given §1, this is the most urgent gap. An LLM drafts the body and a human
approves it; nothing looks for injected instructions, exfiltration, or demands
for credentials and tools. There is also no **capability declaration** — no
machine-readable statement of what a skill may read, write or send — so there is
nothing to check the text against and nothing to show the person who approves.

### 3.8 Detection will not survive scale
`WorkflowDetector` loads every event in the lookback window with `.to_a` and
enumerates all contiguous subsequences per session; `ChainDetector` rewrites the
whole observed link table each sweep; `CaptureSweepJob` runs `PromptCheckJob`
**synchronously, in a loop, for every active user**. All three are fine at a few
hundred people and fatal at tens of thousands.

---

## 4. The design

Five pieces, in dependency order. Each is useful alone.

### A. Content identity
`content_hash` on every skill version: SHA-256 over canonical JSON of the
normative fields only — name, title, description, body, inputs, outputs,
workflow, license. Deliberately **excludes** stage, votes, metrics and
timestamps, so promoting a skill does not change its identity, and two firms
that received the same skill compute the same hash. One canonicaliser, shared
with `RestStop` and the escrow, instead of today's three.

### B. Attestations
One table, replacing nothing, generalising everything:

```
attestation: issuer (user / source / external key)
             subject_hash (what is being spoken about)
             kind   reviewed | approved | ran | verified_output | checked | priced | disputed
             payload (jsonb; kind-specific evidence)
             signature (nullable now, required for external issuers later)
```

Reputation, gate inputs and market signals all become queries over this table.
An external party receives *(skill, content hash, attestations)* and can judge
it with no access to our database.

### C. A hash-linked provenance chain
An append-only ledger where each entry commits to the previous:

```
entry_hash = SHA256(prev_hash ‖ canonical(payload))
```

Every birth, version, branch, promotion, transfer and attestation appends one
entry. Tampering with any historical row breaks every subsequent hash. A daily
**Merkle root** is computed and published — to disk and the mirror now; to a
notary, a counterparty, or a chain later, with no change to the model. This is
the whole of what a blockchain would give us, minus the chain, and it is the
thing that makes a decentralized market possible rather than merely imaginable.

### D. Trigger engine v2
Every trigger becomes a `Capture::Triggers::*` object with one interface —
`signals(scope) → [Signal]` — feeding the existing prompt pipeline, so the
evaluator, confidence gate, snooze and dismissal all keep working unchanged.
Ships with the existing three plus **drift**, **failure**, **staleness** and
**cohort**. A `TriggerStat` row per *(kind, domain)* tracks raised / accepted /
dismissed and adjusts the threshold within admin-set bounds, so precision is
governed rather than guessed.

### E. Capability manifest and the safety gate
Each skill declares what it touches — `reads`, `writes`, `sends`, `tools`,
`needs_credentials` — and a gate checks the declaration against the body before
firm and market: imperative instructions aimed at the agent rather than the
reader, external URLs and send targets, credential and tool requests, and text
that attempts to override the caller. Failures block promotion rather than
warn, and the manifest is shown to whoever approves — closing the consent gap
directly, and giving the market stage something to enforce.

### Scale changes carried alongside
Windowed, incremental counting in `WorkflowDetector` (no full materialisation);
upsert-and-decay for `SkillLink` instead of delete-all; `PromptCheckJob`
enqueued per user instead of run inline; detection partitioned by domain.

---

## 5. Order of work

1. **A + C** — content hash and the provenance chain. The spine; everything else
   references it.
2. **B** — attestations, with gates rewritten as predicates over them.
3. **E** — capability manifest and safety gate. Highest risk, smallest surface.
4. **D** — trigger engine v2, drift first (free, and the most valuable).
5. Scale changes, as the numbers demand them.

Steps 1–3 are also exactly what a decentralized market needs from us: a stable
identity, portable claims, and a reason to believe them.
