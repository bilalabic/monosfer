import { Body, Controller, Get, Patch, Req, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiHeader, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { AuthRateGuard, OriginGuard } from '../security/security.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { UpdateUserDto, UserDto } from './users.dto.js';
import { UsersRepository } from './users.repository.js';

@Controller('users') @ApiTags('users') @ApiCookieAuth('session')
@UseGuards(AuthRateGuard, SessionGuard, OriginGuard)
export class UsersController {
  constructor(private readonly users: UsersRepository) {}
  @Get('me') @ApiOkResponse({ type: UserDto })
  me(@Req() request: AuthRequest) { return request.auth.user; }
  @Patch('me') @ApiOkResponse({ type: UserDto })
  @ApiHeader({ name: 'x-csrf-token', required: true }) @ApiHeader({ name: 'Origin', required: true })
  update(@Req() request: AuthRequest, @Body() input: UpdateUserDto) { return this.users.update(request.auth.user.id, input); }
}
