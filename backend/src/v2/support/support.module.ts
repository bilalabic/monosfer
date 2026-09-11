import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { SecurityModule } from '../security/security.module.js';
import { AuditModule } from '../audit/audit.module.js';
import { ProvidersModule } from '../providers/providers.module.js';
import { PrivilegedGuard, SupportPolicy } from './policy.js';
import { SupportService } from './support.service.js';
import { SupportController, AdminAuditController } from './support.controller.js';

@Module({imports:[AuthModule,SecurityModule,AuditModule,ProvidersModule],providers:[SupportService,SupportPolicy,PrivilegedGuard],
  controllers:[SupportController,AdminAuditController],exports:[SupportService,SupportPolicy,PrivilegedGuard,AuthModule,SecurityModule,AuditModule]})
export class SupportModule {}
