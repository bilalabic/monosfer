import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import type { Settings } from '../config/config.js';

export const token = () => randomBytes(32).toString('hex');
export const hash = (value: string) => createHash('sha256').update(value).digest('hex');
export const csrf = (session: string, secret: string) => createHmac('sha256', secret).update(`csrf:${session}`).digest('hex');
export const equalToken = (left: unknown, right: string): boolean => typeof left === 'string' && /^[a-f0-9]{64}$/.test(left) && timingSafeEqual(Buffer.from(left), Buffer.from(right));
// __Host cookies require Secure even in development; keep the prefix invariant.
// Local HTTP uses an explicitly separate, unprefixed development cookie.
export const cookieNames = (settings: Settings) => ({
  session: settings.environment === 'production' || settings.siweUri.startsWith('https:') ? '__Host-monosfer_sid' : 'monosfer_sid_dev',
  challenge: settings.environment === 'production' || settings.siweUri.startsWith('https:') ? '__Host-monosfer_challenge' : 'monosfer_challenge_dev',
});
export const cookieOptions = (settings: Settings) => ({ httpOnly: true, secure: settings.environment === 'production' || settings.siweUri.startsWith('https:'), sameSite: 'lax' as const, path: '/' });
