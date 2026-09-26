---
name: email-actions
description: Act on emails from the brief — details, read, archive, label, trash, unsubscribe, reply drafts, reminders, calendar events, follow-up tracking. Use when the user replies with a command referencing brief item numbers [N] or groups [P]/[M]/[T]/[O].
---

# Email actions

## Addressing
- Brief items are numbered [1], [2]…; groups use letters: P promotions, M markets, T tech, O other.
- Tracked follow-ups appear in the brief as [F1], [F2]…; commands accept them like any item (details F1, done F1).
- Keep a mapping of number -> Gmail message ID for the latest brief in this session.
  If the mapping is missing or older than 24h, re-run the search and show the new numbering first.
- Several commands can be combined in one message, separated by "·", "," or new lines.

## Commands
- details N — fetch the full message, summarize in <=5 lines, list attachments and links.
- read N / archive N / label N <name> — preview first (sender + subject, max 10 lines, "+X more"),
  wait for an explicit yes, then apply and send the receipt. Same rule as trash: no silent mailbox changes.
- trash N|GROUP — ALWAYS preview first (sender + subject, max 10 lines, "+X more"), then wait for confirm.
  Use Trash only; never permanent delete.
- unsub GROUP — list sender + unsubscribe link. Do not click links or send unsubscribe emails
  unless the user says "unsub confirm".
- reply N[: gist] — draft a reply in Vimal's style (short, polite, direct). Save as a Gmail draft and show it.
  Send only when the user says "send". Never reply to no-reply/automated senders; suggest the right action instead.
- remind N <when> — create a one-time cron job delivered to this Telegram chat. The reminder text must
  include sender, subject, and the action needed. Interpret times in IST and show the exact date/time in the preview.
- event N — extract title/date/time/link and create a Google Calendar event after confirmation.
  If Calendar isn't authorized, say so and offer a reminder instead.
- track N — add to the follow-ups list in memory, with the date it was added.
  Open follow-ups waiting 2+ days (or past their own deadline) appear in ACT NOW of each brief as [F#];
  the rest appear only as a count. They stay until the user says "done F#".
- nudge F# — draft a short follow-up to the same thread (same rules as reply: draft, show, send only on "send").
- more — show the items hidden by the 5-per-section cap of the last brief, continuing the numbering.
- help — list all commands, one line each.

## Safety & receipts
- Any change to mailbox, calendar, or sent mail: preview -> wait for an explicit yes / confirm.
- Batches: one confirmation for the whole batch; the user may say "skip N" for individual items.
- After executing, send a receipt: ✅ what changed, counts, and how to undo
  ("Restore from Trash within 30 days", "undo" to move back, "cancel reminder <id>").
- If an action fails (quota, auth, not found), report which items succeeded and which didn't.
- Never print passwords, OTP values, PAN, or account numbers.
