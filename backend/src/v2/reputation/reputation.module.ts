import { Controller, Get, Module, Param, Req, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { DatabaseModule } from '../infrastructure/database.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { AuthRateGuard } from '../security/security.module.js';
import { SupportModule } from '../support/support.module.js';
import { PrivilegedGuard } from '../support/policy.js';
import { SupportService } from '../support/support.service.js';
import { supportActor } from '../support/support.controller.js';
import { WalletIdDto } from '../support/support.dto.js';
import { ReputationService } from './reputation.service.js';
import { reputationSchema } from '../support/support.schemas.js';

@Controller('users/me') @ApiTags('reputation') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,SessionGuard)
export class MyReputationController {
  constructor(private readonly reputation: ReputationService) {}
  @Get('reputation') @ApiOkResponse({schema:reputationSchema}) read(@Req() req:AuthRequest) { return this.reputation.read(req.auth.user.walletAddress); }
}
@Controller('support/wallets') @ApiTags('support') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,PrivilegedGuard)
export class SupportReputationController {
  constructor(private readonly reputation:ReputationService,private readonly support:SupportService) {}
  @Get(':wallet/reputation') @ApiOkResponse({schema:reputationSchema}) read(@Req() req:AuthRequest,@Param() p:WalletIdDto) {
    return this.support.run(supportActor(req),'support.reputation','wallet',p.wallet,client=>this.reputation.read(p.wallet,client));
  }
}
@Module({imports:[DatabaseModule,SupportModule],providers:[ReputationService],controllers:[MyReputationController,SupportReputationController],exports:[ReputationService]})
export class ReputationModule {}
