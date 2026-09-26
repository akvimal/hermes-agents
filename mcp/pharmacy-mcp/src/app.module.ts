import { Module } from '@nestjs/common';
import { DatabaseModule } from './database/database.module.js';
import { HealthController } from './health.controller.js';
import { McpModule } from './mcp/mcp.module.js';

@Module({
  imports: [DatabaseModule, McpModule],
  controllers: [HealthController],
})
export class AppModule {}
