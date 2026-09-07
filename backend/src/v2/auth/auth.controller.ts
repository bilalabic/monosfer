import { Body, Controller, Delete, Get, HttpCode, Post, Req, Res, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiHeader, ApiOkResponse, ApiNoContentResponse, ApiTags } from '@nestjs/swagger';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { ConfigService } from '../config/config.js';
import { AuthRateGuard, OriginGuard } from '../security/security.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { cookieNames, cookieOptions } from '../security/tokens.js';
import { AuthService } from './auth.service.js';
import { NonceInputDto, NonceResponseDto, SessionResponseDto, VerifyInputDto } from './auth.dto.js';

@ApiTags('auth')
@UseGuards(AuthRateGuard)
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService, private readonly config: ConfigService) {}

  @Post('siwe/nonce') @HttpCode(200) @UseGuards(OriginGuard)
  @ApiHeader({ name: 'Origin', required: true })
  @ApiOkResponse({ type: NonceResponseDto, description: 'Sign message verbatim; retain the HttpOnly challenge cookie for verify. Issuing another nonce replaces this browser challenge.' })
  async nonce(@Body() input: NonceInputDto, @Res({ passthrough: true }) reply: FastifyReply) {
    const result = await this.auth.nonce(input.address);
    const settings = this.config.settings;
    reply.setCookie(cookieNames(settings).challenge, result.browserToken, { ...cookieOptions(settings), maxAge: settings.nonceTtlSeconds });
    return result.response;
  }
  @Post('siwe/verify') @HttpCode(200) @UseGuards(OriginGuard)
  @ApiHeader({ name: 'Origin', required: true })
  @ApiOkResponse({ type: SessionResponseDto, description: 'Requires challenge cookie from nonce; sets HttpOnly session cookie. Keep csrfToken in memory.' })
  async verify(@Body() input: VerifyInputDto, @Req() request: FastifyRequest, @Res({ passthrough: true }) reply: FastifyReply) {
    const settings = this.config.settings;
    const names = cookieNames(settings);
    const result = await this.auth.verify(input.message, input.signature, request.cookies[names.challenge]);
    reply.clearCookie(names.challenge, cookieOptions(settings));
    reply.setCookie(names.session, result.sessionId, { ...cookieOptions(settings), maxAge: settings.sessionTtlSeconds, expires: new Date(result.response.session.expiresAt) });
    return result.response;
  }
  @Get('session') @UseGuards(SessionGuard) @ApiCookieAuth('session')
  @ApiOkResponse({ type: SessionResponseDto })
  session(@Req() request: AuthRequest): SessionResponseDto {
    const { user, session, csrfToken } = request.auth;
    return { user, session, csrfToken };
  }
  @Delete('session') @HttpCode(204) @UseGuards(SessionGuard, OriginGuard) @ApiCookieAuth('session')
  @ApiHeader({ name: 'x-csrf-token', required: true }) @ApiHeader({ name: 'Origin', required: true }) @ApiNoContentResponse()
  async logout(@Req() request: AuthRequest, @Res({ passthrough: true }) reply: FastifyReply) {
    await this.auth.revoke(request.auth, false);
    reply.clearCookie(cookieNames(this.config.settings).session, cookieOptions(this.config.settings));
  }
  @Delete('sessions') @HttpCode(204) @UseGuards(SessionGuard, OriginGuard) @ApiCookieAuth('session')
  @ApiHeader({ name: 'x-csrf-token', required: true }) @ApiHeader({ name: 'Origin', required: true }) @ApiNoContentResponse()
  async logoutAll(@Req() request: AuthRequest, @Res({ passthrough: true }) reply: FastifyReply) {
    await this.auth.revoke(request.auth, true);
    reply.clearCookie(cookieNames(this.config.settings).session, cookieOptions(this.config.settings));
  }
}
