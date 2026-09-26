---
name: email-brief
description: Format for ALL email summaries and daily briefings sent to Telegram. Use whenever summarizing, triaging, or briefing on emails (yesterday, today, unread, last N days).
---

# Email Brief format (Telegram)

## Gathering
- Search Gmail in bounded batches (<=50 per call, short pause between) to avoid rate limits.
  If limited, mark the header line with ⚠️ partial and say what was covered.
- Read-only. Never modify, label, archive, trash, or send anything while building a brief.
- Open full bodies only for items that look actionable (money, deadlines, security, legal/tax, replies).
- Window: since the previous brief was sent; if unknown or the user names a range, use that range.

## Layout
Target ~20 lines. No paragraphs. One line per item, under 80 characters.
Omit any section that is empty.

```
📬 Email Brief · Sat 26 Sep · since Fri 6 PM
🔴 2 need you today · 🟡 3 FYI · 18 bundled

🔴 ACT NOW
[1] 💳 HDFC — card bill ₹18,420 · due 28 Sep → pay
[2] 🧾 CA Mehta — GST docs needed · by 30 Sep → reply
[F1] ⏰ Ravi — quote reply, 2 days waiting → nudge

🟡 FYI
[3] 📅 Zoom — team sync Mon 10:30 AM
[4] 📦 Amazon — order arrives today
[5] 🔐 Google — new sign-in, Chennai → was it you?

📂 BUNDLED
P Promotions 9 — Myntra, Zomato, Nykaa
M Markets 5 — Zerodha, Moneycontrol, Mint
T Tech/AI 3 — Anthropic, OpenAI, Vercel
O Other 1 — LinkedIn

✅ Nothing changed · try: details 1 · remind 2 tomorrow 9am · archive P
```

### Header (2 lines)
- Line 1: `📬 Email Brief · <Day DD Mon> · since <Day time>`. Add ` · ⚠️ partial` if coverage was limited.
- Line 2, the verdict: `🔴 <n> need you today · 🟡 <n> FYI · <n> bundled`.
  Say "today" only for items due today or overdue; otherwise `🔴 <n> to act on`.
- Nothing in ACT NOW: `🎉 Nothing needs you` in place of the red count.

### Items
- Format: `[N] <emoji> <Sender> — <what> · <date/amount> → <action>`. Drop the parts that don't apply.
- The deadline or amount comes right after the description, before the arrow.
- ACT NOW is sorted by deadline, soonest first. Undated items go last.
- Number ACT NOW then FYI continuously: [1], [2], [3]…
- Emojis: 💳 bills/payments/balances/subscriptions, 🔐 security, 📅 events/meetings/calendar,
  📦 orders/delivery, 🧾 tax/legal/terms/shareholder/filings, 💬 a person is waiting for MY reply
  (never for newsletters), 🔑 codes/OTP, ⏰ overdue follow-up, 📄 anything else.
  Pick the most specific one; use 📄 only when none fits.
- Newsletters and digests (markets, tech, promotions) go to BUNDLED, not FYI, unless they name
  something personal (my holdings, my orders, my events).

### Follow-ups
- Tracked items (see email-actions `track`) are not shown at the top.
- Overdue ones join ACT NOW as `[F1]`, `[F2]` with the age and a suggested action.
  Overdue = waiting 2+ days, or its own deadline has passed.
- Other open follow-ups appear only as a count line under FYI: `📌 2 follow-ups open`.

### Bundles
- NEVER bundle a legal, terms, policy, privacy, tax, filing, security or billing-change email,
  even from a sender that is usually promotional or a newsletter (e.g. an AI service updating its
  terms of service). These go to ACT NOW when a review or deadline is involved, otherwise FYI.
- Before finishing, re-scan every bundled message once for those categories and promote any match.
- One line per non-empty group: `<letter> <Group> <count> — <top 3 senders>`.
- The letter leads the line because it is the command key: P Promotions, M Markets, T Tech/AI, O Other.

### Caps
- ACT NOW and FYI show at most 5 items each. Beyond that: `+N more → "more"`.
- Never drop an urgent item to satisfy a cap: overflow goes to FYI or "more", not away.

### Footer
- Exactly `✅ Nothing changed` (or `⚠️ <what failed>` on errors), then ` · try: …` on the same line.
- Then `try:` with 2–3 commands using real numbers from this brief, chosen for what fits:
  a bill -> `remind`, a mail needing a reply -> `reply`, a bundle -> `archive`/`trash`.
- Do not print the full command list. Send it only when the user says `help`.

### Style
- Bold only section headers. Dates as "30 Sep", times as "10:30 PM" (IST).
- Never print passwords, OTP values, PAN, or account numbers. Say "code received" / "password-protected".
