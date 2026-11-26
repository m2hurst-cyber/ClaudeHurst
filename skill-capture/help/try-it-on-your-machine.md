---
title: Try it on your own machine
summary: From nothing to the add-in open in Excel, on your own laptop, in about twenty minutes.
section: start
order: 2
tags: [install, local, add-in, excel, first run, developer]
---

You do not need a server, a domain or an administrator to see this working. You need the
code running on your own machine over HTTPS, and Office pointed at it.

The one thing that will not work: loading the add-in from a copy of this running somewhere
you cannot reach from your own computer. Office fetches the pane from the address in the
manifest, in your browser, on your machine. If your machine cannot open that address,
neither can Excel.

## What you need first

- **Ruby 3.3.6** — the version in `.ruby-version`. `rbenv install 3.3.6` or `asdf`.
- **PostgreSQL**, running. On a Mac, `brew install postgresql@16 && brew services start postgresql@16`.
- **Node**, for the one certificate tool. Any current version.
- **Excel, Word or PowerPoint** — the web versions are easiest, and need no extra setup.

## Set it up

```
git clone <your repository> skill-capture
cd skill-capture
bin/setup
```

`bin/setup` installs the gems and creates the database. It does not create any accounts:
nothing is seeded, deliberately, so an installation never ships with a login somebody else
knows.

**Make yourself an administrator.** This prints a one-time password — keep it:

```
bin/rails users:create EMAIL=you@yourfirm.com NAME="Your Name" ROLE=admin
```

## Run it over HTTPS

Office refuses to load an add-in over plain HTTP, even from your own machine. There is a
script for this:

```
bin/addin-dev
```

It installs Office's own development certificate (you will be asked for your password, once,
to trust it), then runs the app at **https://localhost:3000** with the stylesheet watcher and
the background jobs alongside.

Open https://localhost:3000 and sign in with the account you just made. If the browser warns
about the certificate, the trust step did not complete — run `npx office-addin-dev-certs install`
again and watch for the prompt.

## Put it in Office

Go to **Admin → Deploy** and download `manifest.xml`. Then, whichever of these you prefer:

### Office on the web — easiest, start here

Open Excel on the web. **Home → Add-ins → More add-ins → My add-ins → Upload my add-in**,
and choose the file you just downloaded. It loads immediately — no admin, no waiting.

Your browser is on the same machine as the server, which is why this works with a localhost
address.

### Excel on Windows

Office on Windows loads sideloaded add-ins from a shared folder rather than a file picker.
Put `manifest.xml` in a folder, share it, then in Excel: **File → Options → Trust Center →
Trust Center Settings → Trusted Add-in Catalogs**, add the share's path, tick *Show in Menu*,
and restart Excel. The add-in is then under **Insert → My Add-ins → Shared Folder**.

If that sounds like a lot for a first look, use the web.

### Excel on Mac

Copy the manifest into Office's sideload folder and restart Excel:

```
cp ~/Downloads/manifest.xml ~/Library/Containers/com.microsoft.Excel/Data/Documents/wef/
```

The folder may not exist yet; create it. Word and PowerPoint have their own, with
`com.microsoft.Word` and `com.microsoft.Powerpoint` in the path.

## What should happen

A **Skills** tab appears on the Home ribbon. Click **Library** and the pane opens and asks
you to sign in — it hands itself a key from the console session you already have. From then
on it is signed in on this machine.

Capture a worksheet you built yourself. That is the fastest way to see what the system
actually understands, and the result is yours to correct before anyone else sees it.

## When it does not work

- **"We can't load this add-in"** or a blank pane — the server is not running, or the
  certificate is not trusted. Open https://localhost:3000 in the browser first; if it
  complains there, Office will too.
- **Port 3000 is in use** — stop whatever is using it, or edit `Procfile.addin` and
  `SKILL_CAPTURE_PUBLIC_URL` in `bin/addin-dev` to agree on another port. They must match.
- **The pane loads but sign-in loops** — the address Office is using and the address you
  signed in at are different. Both must be `https://localhost:3000`.
- **The database will not create** — PostgreSQL is not running, or your user cannot create
  databases. `psql -l` tells you which.
- **Nothing is ever captured** — passive capture is off until you turn it on, from the
  **Capture on/off** button on the ribbon.

## When you are ready to give it to other people

That is a different job: a server with a real address, and the manifest deployed centrally
so nobody has to do any of the above. See [Deploy the Office add-in](/help/deploy-the-add-in).
