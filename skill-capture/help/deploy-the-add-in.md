---
title: Deploy the Office add-in
summary: What to set before you start, the three ways to install it, and what to expect on the day.
section: admin
order: 2
tags: [add-in, deployment, office, excel, admin, microsoft 365]
---

A firm does not install Skill Capture from a store. It installs **a manifest that points at
its own server**: the ribbon, the pane and every resource load from the address this
installation runs at. The add-in is a thin client, and the firm's skills never leave its
own instance.

That has a consequence worth saying out loud: get the address wrong and the add-in loads a
blank pane with no useful error. Most deployment trouble is this, not Office.

## Before anyone opens Office

All three are checked on [Setup](/admin/setup).

**An HTTPS address that works from outside.** Office refuses to load an add-in over plain
HTTP, in every host, including on a laptop. If there is a proxy or load balancer in front,
set `SKILL_CAPTURE_PUBLIC_URL` to the address people's browsers actually reach — the
manifest writes that into `AppDomains` and every URL in it, and a mismatch is the single
most common cause of a pane that never appears.

**A fixed add-in id.** `SKILL_CAPTURE_ADDIN_ID` has a stable default, but it is the same
default in every installation. If you run a staging instance and a production instance
against one Microsoft tenant, give them different ids or the second overwrites the first.
Changing the id after people have it installs an update as a *second* add-in beside the
old one, so decide before rollout, not after.

**Accounts, and reviewers with areas.** Add people under People, and set each reviewer's
areas. A draft captured on day one has nowhere to go if nobody reviews that area.

## Three ways to install it, in the order to use them

### 1. Try it yourself — one person, five minutes

In Excel, Word or PowerPoint **on the web**: Home → Add-ins → More add-ins → My add-ins →
**Upload my add-in**, and choose the manifest from [Deploy](/admin/deploy). No admin
rights, no waiting. Do this before you involve anybody else.

### 2. Deploy it to the firm — the real answer

In the Microsoft 365 admin centre: **Settings → Integrated apps → Upload custom apps** →
Office Add-in → upload the manifest → assign the people or groups who should have it.

Nobody installs anything; it appears on the Home tab by itself, and an admin can withdraw
it the same way. **Allow up to 24 hours.** Tell the pilot group that before you start, or
the first hour produces support tickets about an add-in that has simply not arrived yet.

### 3. AppSource — only if you are selling it

Listing publicly needs a Microsoft Partner Center account and Microsoft's validation. A
firm deploying its own instance does not need this, and it is worth avoiding until a pilot
has proved something.

## What a person sees

A **Skills** tab on the Home ribbon of Excel, Word and PowerPoint: Library, Search, Memory,
Record, Review, and Capture sheet.

The first click opens the pane and asks them to sign in. The console hands the pane a
personal key, and it stays signed in on that machine. They can see that key afterwards
under Connections, and switch it off there without losing it.

## Updating it

Most changes need no redeployment at all. The pane and its code load from your server, so
a new feature reaches everyone on their next reload.

A manifest redeployment is only needed when the **ribbon itself** changes — a new button,
a new tooltip. Bump `SKILL_CAPTURE_ADDIN_VERSION`, download the manifest again and upload
it through the same admin page. Office caches manifests hard; expect a day again.

## Two things to know before you commit a firm

**There is no single sign-on yet.** People sign in with the key handshake rather than
silently as their Microsoft identity. It is one step, once per machine, and it works — but
it is the only friction in the first run. Removing it needs an Entra ID app registration
and a manifest change.

**This is the XML manifest, not the newer unified one.** That is correct and supported for
Excel, Word and PowerPoint today. Outlook has moved to the unified manifest, which is why
Outlook is not among the hosts here.

## When it does not appear

- **Nothing on the ribbon, hours after deploying.** Usually propagation. Confirm the person
  is in the assigned group, then wait out the 24 hours before investigating anything else.
- **The tab appears but the pane is blank.** The address in the manifest is not reachable
  from the user's machine, or is not HTTPS. Open it in their browser and see.
- **It worked and now there are two.** The add-in id changed between deployments.
- **Sign-in loops.** The console and the add-in disagree about the address. Check
  `SKILL_CAPTURE_PUBLIC_URL` matches what the manifest contains.
