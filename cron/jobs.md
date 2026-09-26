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
