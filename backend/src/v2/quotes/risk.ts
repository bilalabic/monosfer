import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { amount } from './typed-data.js';

export interface RiskInput { declaredValue: string; metadata: { packageType: string; urgency: string } }
export interface RiskPolicy { validity: number; coverageBps: bigint; minBps: bigint; maxBps: bigint }
export interface RiskDecision { riskTier: number; requiredCoverage: string; policyVersion: string }
export abstract class RiskAdapter { abstract evaluate(input: RiskInput, policy: RiskPolicy): Promise<RiskDecision> }
@Injectable()
export class DeterministicRiskAdapter extends RiskAdapter {
  async evaluate(input: RiskInput, policy: RiskPolicy): Promise<RiskDecision> {
    // Explicit test-only tier 1 policy; chain supplies the actual coverage band.
    // There is no fiat conversion or invented provider price feed.
    const scaled = amount(input.declaredValue) * policy.coverageBps;
    const coverage = scaled * policy.minBps / 100000000n;
    if (coverage <= 0n || coverage >= 2n ** 96n || coverage > scaled * policy.maxBps / 100000000n) throw new ServiceUnavailableException();
    return { riskTier: 1, requiredCoverage: String(coverage), policyVersion: 'deterministic-dev-v1' };
  }
}
