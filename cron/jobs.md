# Cron Jobs

Each job's schedule, prompt and skill. Recreate with `hermes cron create`.

<!-- Template:
## <job-name>
- Schedule: `<cron expression>`
- Profile: <profile>
- Skill: <skill>
- Prompt: <prompt text>
-->

## daily-email-brief
- Schedule: `0 20 * * *` (20:00 IST, daily)
- Profile: me
- Skills: email-brief, google-workspace
- Deliver: telegram (home channel)
- Prompt: Send today's email brief. Window: everything received since yesterday 8:00 PM IST. Follow the email-brief skill layout exactly. Read-only: do not modify, label, archive, trash or send anything. Reply with only the brief.

```
hermes -p me cron create "0 20 * * *" "<prompt>" --name daily-email-brief --skill email-brief --skill google-workspace --deliver telegram
```

## daily-eod
- Schedule: `0 8 * * *` (08:00 IST, daily)
- Profile: pharma-ops
- Skills: none (uses the `pharmacy` MCP server registered in the profile's config.yaml)
- Deliver: telegram (home channel)
- Prompt: Call the eod_summary tool for yesterday's date (IST). Report the figures exactly as returned: bills, gross sales, taxable value, tax, cash/UPI/card split, any payment mismatches, new vs total customers, returns, and pending/discarded bills. Then call low_stock with default arguments and list any products below cover. Then call expiring_soon with default arguments and list any batches expiring soon. Do not calculate or estimate any number yourself - only report what the tools return. Keep the whole reply under 20 lines.
- Note: as of 2026-09-27 the `pharmacy` MCP points at the local dev database (synthetic test data via `docker compose` in `mcp/pharmacy-mcp`), not production. Point `DATABASE_URL` at the production `agent_ro` role before relying on this job's numbers.

```
hermes -p pharma-ops cron create "0 8 * * *" "<prompt>" --name daily-eod --deliver telegram
```

