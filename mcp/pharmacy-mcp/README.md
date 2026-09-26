# pharmacy-mcp

NestJS [MCP](https://modelcontextprotocol.io) server exposing pharmacy tools to Hermes agents.

## Tools

| Tool | Purpose |
| --- | --- |
| `search_products` | Search products by name, SKU or category |
| `get_stock` | Stock level and reorder status for one SKU |
| `list_low_stock` | Products at or below reorder level |

Data comes from `src/inventory/inventory.service.ts`, which currently holds
in-memory placeholder products. Swap its internals for the real pharmacy
system; the tools don't change.

## Run

```bash
npm install
npm run start:dev          # HTTP on http://127.0.0.1:3100/mcp
npm run build && npm run start:prod
node dist/stdio.js         # stdio transport (after build)
```

| Env var | Default | Notes |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | Use `0.0.0.0` only behind a reverse proxy |
| `PORT` | `3100` | |
| `MCP_AUTH_TOKEN` | unset | When set, `/mcp` requires `Authorization: Bearer <token>` |

`GET /health` is unauthenticated. `/mcp` is stateless Streamable HTTP (POST only).

## Connect from Hermes

Check your Hermes version's docs for the exact MCP config keys; the server
side is either of:

- HTTP: `http://127.0.0.1:3100/mcp` with the bearer header
- stdio: `node /path/to/mcp/pharmacy-mcp/dist/stdio.js`

## Test

```bash
npm test            # unit
npm run test:e2e    # HTTP + MCP protocol
npm run lint
```

## Adding a tool

Register it in `src/mcp/mcp-server.factory.ts` with `server.registerTool(...)`
and add an e2e case in `test/mcp.e2e-spec.ts`.
