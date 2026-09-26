import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';

const MCP_HEADERS = { Accept: 'application/json, text/event-stream' };

/**
 * Database-backed tests run against a database that has sql/001_agent_views.sql and
 * sql/002_agent_role.sql applied. Set TEST_DATABASE_URL (agent_ro role) to enable them.
 */
const TEST_DB = process.env.TEST_DATABASE_URL;

/** Streamable HTTP may answer as JSON or as a single SSE event. */
function parse(res: request.Response): any {
  if (res.body && Object.keys(res.body).length) return res.body;
  const line = res.text.split('\n').find((l) => l.startsWith('data:'));
  return JSON.parse(line!.slice(5));
}

describe('pharmacy-mcp (e2e)', () => {
  let app: INestApplication;

  beforeEach(async () => {
    delete process.env.MCP_AUTH_TOKEN;
    // The pool is lazy, so a placeholder URL is enough for tests that never query.
    process.env.DATABASE_URL =
      TEST_DB ?? 'postgresql://unused:unused@127.0.0.1:1/unused';
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterEach(async () => {
    delete process.env.MCP_AUTH_TOKEN;
    await app.close();
  });

  const call = async (name: string, args: object = {}) => {
    const res = await request(app.getHttpServer())
      .post('/mcp')
      .set(MCP_HEADERS)
      .send({
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/call',
        params: { name, arguments: args },
      })
      .expect(200);
    const result = parse(res).result;
    return { result, data: result.isError ? null : JSON.parse(result.content[0].text) };
  };

  it('GET /health', () =>
    request(app.getHttpServer()).get('/health').expect(200, { status: 'ok' }));

  it('lists the registered tools', async () => {
    const res = await request(app.getHttpServer())
      .post('/mcp')
      .set(MCP_HEADERS)
      .send({ jsonrpc: '2.0', id: 1, method: 'tools/list' })
      .expect(200);
    const names = parse(res).result.tools.map((t: { name: string }) => t.name);
    expect(names).toEqual([
      'eod_summary',
      'expiring_soon',
      'low_stock',
      'gst_month_summary',
      'bill_number_gaps',
    ]);
  });

  it('enforces the bearer token when one is configured', async () => {
    process.env.MCP_AUTH_TOKEN = 'test-token';
    const body = { jsonrpc: '2.0', id: 1, method: 'tools/list' };
    await request(app.getHttpServer())
      .post('/mcp')
      .set(MCP_HEADERS)
      .send(body)
      .expect(401);
    await request(app.getHttpServer())
      .post('/mcp')
      .set(MCP_HEADERS)
      .set('Authorization', 'Bearer test-token')
      .send(body)
      .expect(200);
  });

  describe.skipIf(!TEST_DB)('against the database', () => {
    it('gst_month_summary is internally consistent and uses the corrected tax', async () => {
      const { data } = await call('gst_month_summary', { month: '2026-08' });
      const t = data.totals;
      expect(t.sales_gross).toBeGreaterThan(0);
      // gross = taxable + tax (rounding tolerance of a few paise per bill)
      expect(Math.abs(t.sales_gross - t.sales_taxable - t.sales_tax)).toBeLessThan(1);
      // the legacy formula never under-states tax on tax-inclusive totals
      expect(t.legacy_export_tax_estimate).toBeGreaterThanOrEqual(t.sales_tax);
    });

    it('eod_summary returns a day and a 7-day comparison', async () => {
      const { data } = await call('eod_summary', { date: '2026-09-04' });
      expect(data.date).toBe('2026-09-04');
      expect(data.day.bills).toBeGreaterThan(0);
      expect(data.day.cash + data.day.upi + data.day.card).toBeGreaterThan(0);
    });

    it('eod_summary for a day with no sales returns null, not an error', async () => {
      const { data } = await call('eod_summary', { date: '2001-01-01' });
      expect(data.day).toBeNull();
    });

    it('low_stock and expiring_soon return their shapes', async () => {
      const low = (await call('low_stock', { cover_days: 365, limit: 5 })).data;
      expect(low.items.length).toBeLessThanOrEqual(5);
      const exp = (await call('expiring_soon', { days: 365 })).data;
      expect(exp.summary).toHaveProperty('batches');
    });

    it('bill_number_gaps explains or flags every gap', async () => {
      const { data } = await call('bill_number_gaps', { month: '2026-08' });
      expect(data.missing).toBe(
        data.explained_discarded +
          data.explained_pending +
          data.used_elsewhere +
          data.unexplained,
      );
    });

    it('cannot see customer names through any tool', async () => {
      const outputs = await Promise.all([
        call('eod_summary', { date: '2026-09-04' }),
        call('gst_month_summary', { month: '2026-08' }),
        call('bill_number_gaps', { month: '2026-08' }),
      ]);
      for (const o of outputs) {
        expect(JSON.stringify(o.data)).not.toMatch(/customer_name|"customer"|mobile/i);
      }
    });
  });
});
