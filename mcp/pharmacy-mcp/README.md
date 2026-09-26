# pharmacy-mcp

NestJS [MCP](https://modelcontextprotocol.io) server that gives Hermes agents **read-only** access to the
RGP back office database (`rgp-bo`), through a dedicated `agent` schema.

## How it reads the data

```
Hermes agent ──MCP──▶ pharmacy-mcp ──agent_ro (read-only)──▶ schema "agent" (views) ──▶ back office tables
```

- `sql/001_agent_views.sql` creates the `agent` schema: views only, nothing in the app's own tables changes.
- `sql/002_agent_role.sql` creates `agent_ro`, a login role that can read `agent` and nothing else
  (no access to `public` tables, transactions are read-only, 15 s statement timeout).
- Customer names are exposed only by the two `gst_*_bills` views, which exist for the CA workbook.
  No MCP tool selects them.

The views follow the back office's own rules: quantities are in units (a strip holds `pack` units),
`sale_item.price` is per unit and excludes tax, and `sale_item.total` includes tax. GST is therefore
taken **out of** the bill total (`total x rate / (100 + rate)`). The legacy `vw_sales_gst_report` and
`gst.sql` compute `total x rate / 100`, which over-states tax; `gst_month_summary` reports both so the
difference is visible.

## Tools

| Tool | Purpose |
| --- | --- |
| `eod_summary` | One day (default today, IST): bills, gross, taxable, tax, cash/UPI/card, payment mismatches, customers (new/total), returns, pending/discarded bills, vs previous 7 days |
| `expiring_soon` | Batches with stock expiring within N days (or already expired), with estimated cost at risk |
| `low_stock` | Products whose stock covers fewer than N days of last-90-day demand |
| `gst_month_summary` | Month totals by tax rate: sales, returns, net tax, and the legacy-formula difference |
| `bill_number_gaps` | Missing bill numbers in a month: discarded, pending, used in another month, or unexplained |

All tools are read-only (`readOnlyHint`). Sales count only when `status = 'COMPLETE'` and not archived.
Stock counts only `VERIFIED` purchase lines: `(qty + free_qty) x pack - sold + adjustments`.
Stock value uses `ptr_cost / pack` and is an estimate.

## Set up the database side

Apply as the role that owns the back office tables, then create the password out of band:

```bash
psql "$OWNER_URL" -v ON_ERROR_STOP=1 -f sql/001_agent_views.sql
psql "$SUPERUSER_URL" -v ON_ERROR_STOP=1 -f sql/002_agent_role.sql
psql "$SUPERUSER_URL" -c "ALTER ROLE agent_ro PASSWORD '<secret>'"
psql "$OWNER_URL" -v ON_ERROR_STOP=1 -f sql/tests/check_agent_views.sql   # consistency checks
```

Try it on the local dev container first (`rgp-db-dev`); never point tests at production.

## Run

```bash
npm install
DATABASE_URL=postgresql://agent_ro:<secret>@127.0.0.1:5432/<db> npm run start:dev   # http://127.0.0.1:3100/mcp
npm run build && node dist/stdio.js                                                  # stdio transport
```

| Env var | Default | Notes |
| --- | --- | --- |
| `DATABASE_URL` | required | Use the `agent_ro` role |
| `HOST` | `127.0.0.1` | Use `0.0.0.0` only behind a reverse proxy |
| `PORT` | `3100` | |
| `MCP_AUTH_TOKEN` | unset | When set, `/mcp` requires `Authorization: Bearer <token>` |

`GET /health` is unauthenticated. `/mcp` is stateless Streamable HTTP (POST only).

## Test

```bash
npm test                 # unit tests, no database needed
npm run test:e2e         # HTTP + MCP protocol; database tests skip without TEST_DATABASE_URL
TEST_DATABASE_URL=postgresql://agent_ro:<secret>@localhost:5432/<db> npm run test:e2e
npm run lint
```

The local dev database is synthetic QA data: use it to check logic, not to judge real sales, margins or discounts.

## Connect from Hermes

Check your Hermes version's docs for the exact MCP config keys; the server side is either of:

- HTTP: `http://127.0.0.1:3100/mcp` with the bearer header
- stdio: `node /path/to/mcp/pharmacy-mcp/dist/stdio.js` with `DATABASE_URL` in its environment

## Adding a tool

Add the query to `src/pharmacy/pharmacy.repository.ts` (select from `agent.*` views only), register it in
`src/mcp/mcp-server.factory.ts`, and add a case in `test/mcp.e2e-spec.ts`. Put any new view in
`sql/001_agent_views.sql` and a check in `sql/tests/check_agent_views.sql`.
