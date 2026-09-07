import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { SecurityModule } from '../security/security.module.js';
import { DatabaseModule } from '../infrastructure/database.module.js';
import { UsersController } from './users.controller.js';
import { UsersRepository } from './users.repository.js';

@Module({ imports: [AuthModule, SecurityModule, DatabaseModule], controllers: [UsersController], providers: [UsersRepository] })
export class UsersModule {}
