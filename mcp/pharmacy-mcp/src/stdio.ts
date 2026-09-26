import { NestFactory } from '@nestjs/core';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { AppModule } from './app.module.js';
import { McpServerFactory } from './mcp/mcp-server.factory.js';

// stdio transport for local Hermes profiles: `node dist/stdio.js`.
// Logging is disabled because stdout carries the MCP protocol.
const app = await NestFactory.createApplicationContext(AppModule, {
  logger: false,
});
await app.get(McpServerFactory).create().connect(new StdioServerTransport());
