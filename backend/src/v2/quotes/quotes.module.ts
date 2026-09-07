import { Module } from '@nestjs/common';
import { DatabaseModule } from '../infrastructure/database.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { SecurityModule } from '../security/security.module.js';
import { QuotesController } from './quotes.controller.js';
import { QuotesService } from './quotes.service.js';
import { QuotesRepository } from './quotes.repository.js';
import { QuoteChain, QuoteSigner } from './chain.js';
import { RiskAdapter, DeterministicRiskAdapter } from './risk.js';
import { QuoteLinkWorker } from './link-worker.js';

@Module({imports:[DatabaseModule,AuthModule,SecurityModule],controllers:[QuotesController],
  providers:[QuotesService,QuotesRepository,QuoteChain,QuoteSigner,QuoteLinkWorker,{provide:RiskAdapter,useClass:DeterministicRiskAdapter}],
  exports:[QuoteLinkWorker]})
export class QuotesModule {}
