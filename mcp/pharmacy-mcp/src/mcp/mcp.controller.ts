import {
  Controller,
  Delete,
  Get,
  Inject,
  Post,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { Request, Response } from 'express';
import { BearerAuthGuard } from '../common/bearer-auth.guard.js';
import { McpServerFactory } from './mcp-server.factory.js';

/**
 * Stateless Streamable HTTP endpoint: each POST gets its own server and
 * transport, so there are no sessions to persist or clean up.
 */
@Controller('mcp')
@UseGuards(BearerAuthGuard)
export class McpController {
  constructor(
    @Inject(McpServerFactory) private readonly factory: McpServerFactory,
  ) {}

  @Post()
  async handle(@Req() req: Request, @Res() res: Response): Promise<void> {
    const server = this.factory.create();
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
    });
    res.on('close', () => {
      void transport.close();
      void server.close();
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  }

  @Get()
  notAllowedGet(@Res() res: Response): void {
    this.methodNotAllowed(res);
  }

  @Delete()
  notAllowedDelete(@Res() res: Response): void {
    this.methodNotAllowed(res);
  }

  private methodNotAllowed(res: Response): void {
    res.status(405).json({
      jsonrpc: '2.0',
      error: { code: -32000, message: 'Method not allowed.' },
      id: null,
    });
  }
}
