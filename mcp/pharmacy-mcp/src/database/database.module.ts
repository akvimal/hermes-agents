import { Global, Inject, Module, OnApplicationShutdown } from '@nestjs/common';
import pg from 'pg';

export const PG_POOL = Symbol('PG_POOL');

// numeric -> number, bigint -> number, date -> 'YYYY-MM-DD' string (no timezone shifts).
pg.types.setTypeParser(1700, (v) => parseFloat(v));
pg.types.setTypeParser(20, (v) => parseInt(v, 10));
pg.types.setTypeParser(1082, (v) => v);

/**
 * One lazy pool for the read-only `agent_ro` role. Nothing connects until the first query,
 * so the app can boot (health checks, tests) without a database.
 */
@Global()
@Module({
  providers: [
    {
      provide: PG_POOL,
      useFactory: () => {
        const connectionString = process.env.DATABASE_URL;
        if (!connectionString) {
          throw new Error(
            'DATABASE_URL is not set (use the read-only agent_ro role)',
          );
        }
        const pool = new pg.Pool({
          connectionString,
          max: 5,
          idleTimeoutMillis: 30_000,
        });
        pool.on('error', (err) => console.error('pg pool error:', err.message));
        return pool;
      },
    },
  ],
  exports: [PG_POOL],
})
export class DatabaseModule implements OnApplicationShutdown {
  constructor(@Inject(PG_POOL) private readonly pool: pg.Pool) {}

  async onApplicationShutdown(): Promise<void> {
    await this.pool.end();
  }
}
