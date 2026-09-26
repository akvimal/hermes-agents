import { Module } from '@nestjs/common';
import { InventoryModule } from '../inventory/inventory.module.js';
import { McpController } from './mcp.controller.js';
import { McpServerFactory } from './mcp-server.factory.js';

@Module({
  imports: [InventoryModule],
  controllers: [McpController],
  providers: [McpServerFactory],
  exports: [McpServerFactory],
})
export class McpModule {}
