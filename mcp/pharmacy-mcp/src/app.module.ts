import { Module } from '@nestjs/common';
import { HealthController } from './health.controller.js';
import { McpModule } from './mcp/mcp.module.js';

@Module({
  imports: [McpModule],
  controllers: [HealthController],
})
export class AppModule {}
