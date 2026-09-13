import { Module } from '@nestjs/common';
import { DatabaseModule } from '../infrastructure/database.module.js';
import { RedisModule } from '../infrastructure/redis.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { SecurityModule } from '../security/security.module.js';
import { ProofChain } from './chain.js';
import { ProofsService } from './proofs.service.js';
import { ProofsController } from './proofs.controller.js';
@Module({imports:[DatabaseModule,RedisModule,AuthModule,SecurityModule],providers:[ProofChain,ProofsService],controllers:[ProofsController]})
export class ProofsModule {}
