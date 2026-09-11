import { isAddress } from 'viem';

export interface ReleaseSettings {
  supportEnabled: boolean;
  supportWallets: string[];
  adminWallets: string[];
  caseIdempotencyTtl: number;
  metricsToken: string;
  traceSampleRate: number;
  restoreTargetSeconds: number;
  testnetRpcUrl: string;
}

export function parseReleaseSettings(env: NodeJS.ProcessEnv): ReleaseSettings {
  const enabled = env.SUPPORT_ENABLED ?? 'false';
  if (!['true', 'false'].includes(enabled)) throw new Error('Invalid SUPPORT_ENABLED');
  const wallets = (key: string) => {
    const values = (env[key] ?? '').split(',').map(v => v.trim()).filter(Boolean);
    if (values.some(v => !isAddress(v) || /^0x0{40}$/i.test(v))) throw new Error(`Invalid ${key}`);
    return [...new Set(values.map(v => v.toLowerCase()))];
  };
  const supportWallets = wallets('SUPPORT_WALLETS'), adminWallets = wallets('ADMIN_WALLETS');
  if (enabled === 'true' && !supportWallets.length && !adminWallets.length) throw new Error('Support allowlist required');
  const integer = (key: string, fallback: number, max: number) => {
    const raw = env[key] ?? String(fallback), value = Number(raw);
    if (!/^\d+$/.test(raw) || !Number.isSafeInteger(value) || value < 1 || value > max) throw new Error(`Invalid ${key}`);
    return value;
  };
  const metricsToken = env.OPS_METRICS_TOKEN ?? '';
  if (metricsToken && !/^[A-Za-z0-9_-]{32,256}$/.test(metricsToken)) throw new Error('Invalid OPS_METRICS_TOKEN');
  const sample = env.OPS_TRACE_SAMPLE_RATE ?? '0';
  if (!/^(0(\.\d+)?|1(\.0+)?)$/.test(sample)) throw new Error('Invalid OPS_TRACE_SAMPLE_RATE');
  const testnetRpcUrl = env.TESTNET_SMOKE_RPC_URL ?? '';
  if (testnetRpcUrl) {
    try { const url = new URL(testnetRpcUrl); if (!['http:', 'https:'].includes(url.protocol) || url.hash || !url.hostname) throw new Error(); }
    catch { throw new Error('Invalid TESTNET_SMOKE_RPC_URL'); }
  }
  return { supportEnabled: enabled === 'true', supportWallets, adminWallets, metricsToken, traceSampleRate: Number(sample), testnetRpcUrl,
    caseIdempotencyTtl: integer('SUPPORT_CASE_IDEMPOTENCY_TTL_SECONDS', 86400, 2592000),
    restoreTargetSeconds: integer('OPS_RESTORE_DRILL_TARGET_SECONDS', 60, 3600) };
}
