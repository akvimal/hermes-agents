import { Inject, Injectable } from '@nestjs/common';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { InventoryService } from '../inventory/inventory.service.js';

const asJson = (data: unknown): CallToolResult => ({
  content: [{ type: 'text', text: JSON.stringify(data, null, 2) }],
});

const asError = (message: string): CallToolResult => ({
  isError: true,
  content: [{ type: 'text', text: message }],
});

/** Builds an McpServer with every pharmacy tool registered. */
@Injectable()
export class McpServerFactory {
  constructor(
    @Inject(InventoryService) private readonly inventory: InventoryService,
  ) {}

  create(): McpServer {
    const server = new McpServer({ name: 'pharmacy-mcp', version: '0.1.0' });

    server.registerTool(
      'search_products',
      {
        description: 'Search pharmacy products by name, SKU or category.',
        inputSchema: {
          query: z.string().min(1).describe('Text to match'),
          limit: z.number().int().min(1).max(50).optional(),
        },
      },
      ({ query, limit }) => asJson(this.inventory.search(query, limit)),
    );

    server.registerTool(
      'get_stock',
      {
        description: 'Get stock level and reorder status for one SKU.',
        inputSchema: { sku: z.string().min(1) },
      },
      ({ sku }) => {
        const product = this.inventory.findBySku(sku);
        if (!product) return asError(`Unknown SKU: ${sku}`);
        return asJson({
          ...product,
          needsReorder: product.stock <= product.reorderLevel,
        });
      },
    );

    server.registerTool(
      'list_low_stock',
      {
        description: 'List products at or below their reorder level.',
        inputSchema: {},
      },
      () => asJson(this.inventory.lowStock()),
    );

    return server;
  }
}
