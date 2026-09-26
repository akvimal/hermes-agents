import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { McpServerFactory } from './mcp-server.factory.js';
import type { PharmacyRepository } from '../pharmacy/pharmacy.repository.js';

async function connect(repo: Partial<PharmacyRepository>) {
  const server = new McpServerFactory(repo as PharmacyRepository).create();
  const client = new Client({ name: 'test', version: '0.0.0' });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await Promise.all([server.connect(a), client.connect(b)]);
  return client;
}

const text = (r: any) => r.content[0].text as string;

describe('McpServerFactory', () => {
  it('registers the read-only pharmacy tools', async () => {
    const client = await connect({});
    const { tools } = await client.listTools();
    expect(tools.map((t) => t.name)).toEqual([
      'eod_summary',
      'expiring_soon',
      'low_stock',
      'gst_month_summary',
      'bill_number_gaps',
    ]);
    expect(tools.every((t) => t.annotations?.readOnlyHint === true)).toBe(true);
  });

  it('passes validated arguments (with defaults) to the repository', async () => {
    const expiring = vi.fn().mockResolvedValue({ items: [] });
    const client = await connect({ expiring });
    await client.callTool({ name: 'expiring_soon', arguments: {} });
    expect(expiring).toHaveBeenCalledWith(90, 50);
  });

  it('rejects a malformed month before touching the database', async () => {
    const gstMonth = vi.fn();
    const client = await connect({ gstMonth });
    const res: any = await client.callTool({
      name: 'gst_month_summary',
      arguments: { month: '2026-13' },
    });
    expect(res.isError).toBe(true);
    expect(gstMonth).not.toHaveBeenCalled();
  });

  it('turns a database failure into a tool error', async () => {
    const client = await connect({
      eod: vi.fn().mockRejectedValue(new Error('connection refused')),
    });
    const res: any = await client.callTool({ name: 'eod_summary', arguments: {} });
    expect(res.isError).toBe(true);
    expect(text(res)).toContain('connection refused');
  });
});
