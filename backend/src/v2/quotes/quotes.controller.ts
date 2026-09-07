import { Body, Controller, Get, Headers, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiCreatedResponse, ApiHeader, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { AuthRateGuard, OriginGuard } from '../security/security.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { CreateQuoteDto, QuoteDigestDto, QuoteResponseDto, QuoteStatusDto, RefreshQuoteDto } from './quotes.dto.js';
import { QuotesService } from './quotes.service.js';

@Controller('quotes') @ApiTags('quotes') @ApiCookieAuth('session')
@UseGuards(AuthRateGuard, SessionGuard, OriginGuard)
export class QuotesController {
  constructor(private readonly quotes: QuotesService) {}
  @Post('delivery') @ApiCreatedResponse({ type:QuoteResponseDto })
  @ApiHeader({ name:'Idempotency-Key',required:true,description:'16–128 ASCII letters/digits/._:-; never reuse for a different request' })
  @ApiHeader({ name:'x-csrf-token',required:true }) @ApiHeader({ name:'Origin',required:true })
  create(@Req() request: AuthRequest,@Headers('idempotency-key') key: string|undefined,@Body() input:CreateQuoteDto) {
    return this.quotes.issue(request.auth.user.walletAddress,key,input);
  }
  @Get(':quoteDigest') @ApiOkResponse({ type:QuoteStatusDto })
  status(@Req() request: AuthRequest,@Param() params:QuoteDigestDto) {
    return this.quotes.status(params.quoteDigest,request.auth.user.walletAddress);
  }
  @Post(':quoteDigest/refresh') @ApiCreatedResponse({ type:QuoteResponseDto })
  @ApiHeader({ name:'Idempotency-Key',required:true })
  @ApiHeader({ name:'x-csrf-token',required:true }) @ApiHeader({ name:'Origin',required:true })
  refresh(@Req() request:AuthRequest,@Param() params:QuoteDigestDto,@Headers('idempotency-key') key:string|undefined,@Body() _input:RefreshQuoteDto) {
    return this.quotes.issue(request.auth.user.walletAddress,key,undefined,params.quoteDigest);
  }
}
