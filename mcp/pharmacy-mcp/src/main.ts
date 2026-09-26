import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const host = process.env.HOST ?? '127.0.0.1';
  const port = Number(process.env.PORT ?? 3100);
  await app.listen(port, host);
  console.log(`pharmacy-mcp listening on http://${host}:${port}/mcp`);
}
await bootstrap();
