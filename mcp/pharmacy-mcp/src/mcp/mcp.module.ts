import { Module } from '@nestjs/common';
import { PharmacyModule } from '../pharmacy/pharmacy.module.js';
import { McpController } from './mcp.controller.js';
import { McpServerFactory } from './mcp-server.factory.js';

@Module({
  imports: [PharmacyModule],
  controllers: [McpController],
  providers: [McpServerFactory],
  exports: [McpServerFactory],
})
export class McpModule {}
