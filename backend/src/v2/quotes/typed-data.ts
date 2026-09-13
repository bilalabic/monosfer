import { BadRequestException } from '@nestjs/common';
import { hashTypedData, type Address, type Hex } from 'viem';

export const quoteTypes = { Quote: [
  { name: 'customer', type: 'address' }, { name: 'riskTier', type: 'uint8' },
  { name: 'declaredValue', type: 'uint96' }, { name: 'requiredCoverage', type: 'uint96' },
  { name: 'issuedAt', type: 'uint64' }, { name: 'expiresAt', type: 'uint64' }, { name: 'salt', type: 'bytes32' },
] } as const;
export interface CoverageQuote {
  customer: Address; riskTier: number; declaredValue: string; requiredCoverage: string;
  issuedAt: string; expiresAt: string; salt: Hex;
}
export function amount(value: string, bits = 96): bigint {
  if (typeof value !== 'string' || !/^(0|[1-9][0-9]{0,28})$/.test(value)) throw new BadRequestException();
  const n = BigInt(value);
  if (n <= 0n || n >= 2n ** BigInt(bits)) throw new BadRequestException();
  return n;
}
export function typedQuote(quote: CoverageQuote, chainId: number, hub: Address, maxValidity: number) {
  amount(quote.declaredValue); amount(quote.requiredCoverage);
  const issued = amount(quote.issuedAt, 64); const expires = amount(quote.expiresAt, 64);
  if (!Number.isInteger(quote.riskTier) || quote.riskTier < 1 || quote.riskTier > 3 ||
    expires <= issued || expires - issued > BigInt(maxValidity) || !/^0x[0-9a-fA-F]{40}$/.test(quote.customer) ||
    /^0x0{40}$/.test(quote.customer) || !/^0x[0-9a-fA-F]{64}$/.test(quote.salt)) throw new BadRequestException();
  // Decimal strings are JSON-safe and preserve every uint96/uint64 bit.
  const typedData = { domain: { name: 'MONOSFER', version: '1', chainId, verifyingContract: hub },
    types: quoteTypes, primaryType: 'Quote' as const, message: quote };
  return { typedData, quoteDigest: hashTypedData({ ...typedData, message: {
    ...quote, declaredValue: BigInt(quote.declaredValue), requiredCoverage: BigInt(quote.requiredCoverage), issuedAt: issued, expiresAt: expires,
  } }) };
}
