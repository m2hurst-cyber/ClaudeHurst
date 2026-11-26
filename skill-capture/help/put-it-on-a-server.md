---
title: Put it on a server
summary: Get a real web address so a colleague can try it, or the department can have it, without installing anything.
section: start
order: 3
tags: [deploy, server, render, hosting, demo, department]
---

Running it on your own laptop is fine for looking at it alone. It does not survive contact
with a colleague: Office fetches the add-in from the address inside the manifest, in *their*
browser, on *their* machine — and nobody else can reach your laptop.

So the moment a second person is involved, it needs an address of its own. That takes about
twenty minutes and nothing installed on your computer.

## What you get

An HTTPS address like `https://skill-capture.onrender.com`, a database, and a background
worker. Anyone you give an account to can use it, and the add-in can be deployed to the
whole department from the Microsoft 365 admin centre, pointing at that address.

## The steps

**1. Get the code onto GitHub.** If it is already in a repository you own, skip this.

**2. Create a Render account** at render.com and connect it to GitHub. Free to start.

**3. New → Blueprint → choose the repository**, and set two fields that do not default
correctly:

- **Branch** — the branch this code is on. It is not `main` unless you have merged it.
- **Blueprint Path** — `skill-capture/render.yaml`. Skill Capture is a subdirectory of
  this repository; another application sits at the root, and Render looks at the root by
  default. If you see *"Blueprint file render.yaml not found"*, this is why.

Render then does the rest: builds the image, creates the Postgres database, starts the
web service and the background worker, and issues the HTTPS certificate. The first build
takes about ten minutes.

It also generates the encryption keys, once, and keeps them. **Copy them out of the
dashboard and keep them somewhere safe.** Whatever they encrypted — integration tokens,
return documents — is unreadable without them, and Render will not show you them again if
the service is destroyed.

**4. Make yourself an administrator.** Open the web service in Render, go to the **Shell**
tab, and run:

```
bin/rails users:create EMAIL=you@yourfirm.com NAME="Your Name" ROLE=admin
```

It prints a one-time password. Nothing is ever seeded with a login, which is why this step
exists: an installation should never arrive with a password somebody else knows.

**5. Sign in** at the address Render gave you, and go to **Admin → Setup**. It lists what is
still missing — mail, a model key — and what each one costs you while it is missing.

## Then give it to people

**One colleague trying it:** add them under Admin → People, send them the address and the
one-time password the task prints, and have them sideload the manifest from
Admin → Deploy in Excel on the web.

**The department:** hand the manifest to whoever runs your Microsoft 365 tenant and point
them at [Deploy the Office add-in](/help/deploy-the-add-in). They upload it once and it
appears for everyone assigned.

## What to add once it is up

- **A model key** (`ANTHROPIC_API_KEY`) — without it, drafting and judging fall back to
  rules. Everything works; it is blunter.
- **Mail** — four variables, and password resets start reaching people. Until then they
  silently do not.
- **Your own domain**, if the generated address looks wrong in front of a client. Render
  will issue the certificate; then set `SKILL_CAPTURE_PUBLIC_URL` to the new address and
  redeploy the manifest, because the old one has the old address baked into it.

## Other hosts

`render.yaml` is Render's format, but the `Dockerfile` beside it is not: anything that runs
a container will take it — Fly, Railway, a VM, your own Kubernetes. What such a host needs
from you is `DATABASE_URL`, `SECRET_KEY_BASE`, the three encryption keys, and
`SKILL_CAPTURE_PUBLIC_URL`. Run `./bin/jobs` as a second process for the background work;
without it nothing is ever detected, though the console works.
