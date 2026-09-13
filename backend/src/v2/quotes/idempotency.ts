import { createHmac } from 'node:crypto';
import { BadRequestException } from '@nestjs/common';

export function canonical(value: unknown): string {
  if (Array.isArray(value)) return '['+value.map(canonical).join(',')+']';
  if (value && typeof value==='object') return '{'+Object.entries(value).filter(([,v])=>v!==undefined)
    .sort(([a],[b])=>a<b?-1:a>b?1:0).map(([k,v])=>JSON.stringify(k)+':'+canonical(v)).join(',')+'}';
  return JSON.stringify(value);
}
export function idempotencyScope(key: unknown, owner: string, route: string, stream: string, secret: string) {
  if (typeof key!=='string' || !/^[A-Za-z0-9._:-]{16,128}$/.test(key)) throw new BadRequestException();
  return privateHash([owner,route,stream,key],secret);
}
export function privateHash(value: unknown, secret: string): string {
  return createHmac('sha256',Buffer.from(secret,'base64')).update('monosfer/quote-idempotency/v1\0').update(canonical(value)).digest('hex');
}
export const responseAad = (scope: string) => `monosfer/quote-response/v1/${scope}`;
