import { Module } from '@nestjs/common';
import { DatabaseModule } from '../infrastructure/database.module.js';
import { RedisModule } from '../infrastructure/redis.module.js';
import { SecurityModule } from '../security/security.module.js';
import { SessionGuard } from '../security/session.guard.js';
import { AuthController } from './auth.controller.js';
import { AuthRepository } from './auth.repository.js';
import { AuthService } from './auth.service.js';
import { SignatureService } from './signature.service.js';

@Module({ imports: [DatabaseModule, RedisModule, SecurityModule], controllers: [AuthController],
  providers: [AuthRepository, AuthService, SignatureService, SessionGuard], exports: [AuthService, SessionGuard] })
export class AuthModule {}
