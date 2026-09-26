import { Inject, Injectable } from '@nestjs/common';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { PharmacyRepository } from '../pharmacy/pharmacy.repository.js';

const asJson = (data: unknown): CallToolResult => ({
  content: [{ type: 'text', text: JSON.stringify(data, null, 2) }],
});

const asError = (message: string): CallToolResult => ({
  isError: true,
  content: [{ type: 'text', text: message }],
});

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'use YYYY-MM-DD');
const month = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'use YYYY-MM');

const readOnly = { readOnlyHint: true, openWorldHint: false };

/** Builds an McpServer with every pharmacy tool registered. All tools are read-only. */
@Injectable()
export class McpServerFactory {
  constructor(
    @Inject(PharmacyRepository) private readonly repo: PharmacyRepository,
  ) {}

  create(): McpServer {
    const server = new McpServer({ name: 'pharmacy-mcp', version: '0.2.0' });

    // Every tool reports database problems as a tool error instead of crashing the request.
    const guard =
      <A>(fn: (args: A) => Promise<unknown>) =>
      async (args: A): Promise<CallToolResult> => {
        try {
          return asJson(await fn(args));
        } catch (e) {
          return asError(`Database query failed: ${(e as Error).message}`);
        }
      };

    server.registerTool(
      'eod_summary',
      {
        description:
          "End-of-day summary for one date (default: today, IST): completed bills, gross sales, taxable value and tax, cash/UPI/card split, bills whose payments don't add up, customers (new and total), returns, pending and discarded bills, and how gross sales compare with the previous 7 days.",
        inputSchema: { date: date.optional() },
        annotations: readOnly,
      },
      guard(({ date }) => this.repo.eod(date)),
    );

    server.registerTool(
      'expiring_soon',
      {
        description:
          'Batches that still have stock and expire within N days (or already expired), soonest first, with an estimated cost of the stock at risk.',
        inputSchema: {
          days: z.number().int().min(1).max(365).default(90),
          limit: z.number().int().min(1).max(200).default(50),
        },
        annotations: readOnly,
      },
      guard(({ days, limit }) => this.repo.expiring(days, limit)),
    );

    server.registerTool(
      'low_stock',
      {
        description:
          'Products whose stock covers fewer than N days of their last-90-day demand (negative stock first). Only products that sold in the last 90 days.',
        inputSchema: {
          cover_days: z.number().min(1).max(365).default(15),
          limit: z.number().int().min(1).max(200).default(50),
        },
        annotations: readOnly,
      },
      guard(({ cover_days, limit }) => this.repo.lowStock(cover_days, limit)),
    );

    server.registerTool(
      'gst_month_summary',
      {
        description:
          'GST totals for a month by tax rate: sales (gross, taxable, CGST, SGST) and returns, plus net tax. Tax is taken out of the tax-inclusive bill total. Only completed bills count.',
        inputSchema: { month },
        annotations: readOnly,
      },
      guard(({ month }) => this.repo.gstMonth(month)),
    );

    server.registerTool(
      'bill_number_gaps',
      {
        description:
          'Missing bill numbers between the first and last completed bill of a month, split into ones explained by a discarded or pending sale, ones used by a completed bill in another month, and ones with no record at all (the CA may ask about these).',
        inputSchema: {
          month,
          limit: z.number().int().min(1).max(500).default(100),
        },
        annotations: readOnly,
      },
      guard(({ month, limit }) => this.repo.billGaps(month, limit)),
    );

    return server;
  }
}
