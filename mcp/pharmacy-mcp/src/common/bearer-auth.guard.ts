import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { timingSafeEqual } from 'node:crypto';
import type { Request } from 'express';

/**
 * Requires `Authorization: Bearer <MCP_AUTH_TOKEN>`. When MCP_AUTH_TOKEN is
 * unset the guard allows everything, so only do that on a loopback bind.
 */
@Injectable()
export class BearerAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const expected = process.env.MCP_AUTH_TOKEN;
    if (!expected) return true;

    const header = context.switchToHttp().getRequest<Request>().headers
      .authorization;
    const supplied = header?.startsWith('Bearer ') ? header.slice(7) : '';

    const a = Buffer.from(supplied);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new UnauthorizedException();
    }
    return true;
  }
}
