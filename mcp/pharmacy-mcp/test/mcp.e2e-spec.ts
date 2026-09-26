import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';

const MCP_HEADERS = { Accept: 'application/json, text/event-stream' };

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

  it('GET /health', () =>
    request(app.getHttpServer()).get('/health').expect(200, { status: 'ok' }));

  it('lists the registered tools', async () => {
    const res = await request(app.getHttpServer())
      .post('/mcp')
      .set(MCP_HEADERS)
      .send({ jsonrpc: '2.0', id: 1, method: 'tools/list' })
      .expect(200);
    const names = parse(res).result.tools.map((t: { name: string }) => t.name);
    expect(names).toEqual(['search_products', 'get_stock', 'list_low_stock']);
  });

  it('calls get_stock', async () => {
    const res = await request(app.getHttpServer())
      .post('/mcp')
      .set(MCP_HEADERS)
      .send({
        jsonrpc: '2.0',
        id: 2,
        method: 'tools/call',
        params: { name: 'get_stock', arguments: { sku: 'IBU-200-16' } },
      })
      .expect(200);
    const payload = JSON.parse(parse(res).result.content[0].text);
    expect(payload).toMatchObject({ sku: 'IBU-200-16', needsReorder: true });
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
});
