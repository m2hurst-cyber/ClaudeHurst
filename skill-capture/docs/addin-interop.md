# Talking to another add-in

What is actually possible between two Office add-ins in the same document, what is not,
and which of it is worth building. Written while working out how Skill Capture hands a
skill's directions to Claude for Excel without anyone copying and pasting.

## The thing people assume, which is false

Two add-ins open in the same workbook cannot call each other. Each runs in its own
WebView on its own origin, with no handle to the other: no shared `window`, no
`postMessage`, no events. `window.SkillCaptureMemory` is visible to our ribbon and our
pane because they share one runtime — and to nothing else, ever.

There is no cross-add-in messaging API in Office.js. There never has been.

## What is actually shared

**Settings are not.** `Office.context.document.settings` reads as though it were document
state, but it is stored per add-in per document. Our settings are ours; we cannot see
theirs and they cannot see ours. This is the trap: the API looks like a channel and is not.

**Custom XML parts are.** They live in the document, are addressed by namespace, and
Microsoft's own documentation says other add-ins can read what you store there. In Excel
that is `workbook.customXmlParts`; in Word and PowerPoint,
`Office.context.document.customXmlParts`. There is no change event, so the reader polls.

**Custom document properties are**, and are hopeless for anything but a flag.

**The document content is**, trivially, and this turns out to matter more than any of it.

## The distinction that decides the design

There are two kinds of partner, and they need different channels.

**A cooperating add-in** — one whose authors will agree a namespace with us. Custom XML
parts are the right answer: invisible to the user, structured, travels with the file,
survives save and reopen. The community pattern is a mailbox: writer puts a part under an
agreed namespace, reader polls for it, reads it, deletes it. Crude, documented, works.

**An uncooperating add-in** — one we cannot change and cannot negotiate with. Claude for
Excel is this. It will never know our namespace. But it reads the workbook, and that is
the opening: *anything in the sheet is in its context*. The channel to an AI add-in is not
an API at all. It is the spreadsheet.

That reframing is the whole finding. We do not need Anthropic to integrate with us for a
skill's directions to reach Claude. We need the directions to be in the workbook, in a
place a person can point at in one sentence.

## What we are building

**Hand to the AI** writes the current skill into both channels at once:

1. A custom XML part under `urn:skill-capture:handoff`, carrying the skill's name,
   version, content hash and directions, for any add-in that learns to look.
2. A worksheet named **Skill Capture**, holding the same directions as text, for any AI
   that reads the workbook.

The sheet is deliberately visible. A hidden sheet is tidier and may not be read; being
read is the entire point. Its first row says what it is and that deleting it is safe.

The content hash goes in both, so whatever acts on the directions can say which version
of which skill it followed — and the provenance chain can confirm it.

## What we are not building

**Polling for replies.** A mailbox where we watch for another add-in to answer is a lot of
machinery for a conversation nobody is having yet. One-way is enough until a partner
exists.

**Clipboard tricks.** Pre-filling the clipboard is still a paste, and Office's clipboard
access is restricted anyway.

**A protocol.** Agreeing a schema with one partner is premature. The XML part carries the
same fields the `.md` endpoints already serve, so anyone integrating has seen the shape.

## The route that avoids all of this

MCP, which already works. A client that speaks it — Claude Desktop, Claude Code, a
claude.ai connector — fetches the skill from the server and never touches the document. It
is better in every way, and it is unavailable precisely when the partner is an add-in
running beside us in Excel rather than a model with a connector. Hence the above.
