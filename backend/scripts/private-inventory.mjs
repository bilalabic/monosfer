import { LegacySource, parseLegacySettings } from '../dist/private-data/legacy-source.js';

let source;
try {
  if (process.argv.length > 2) throw new Error();
  source = new LegacySource(parseLegacySettings(process.env));
  console.log(JSON.stringify({ event: 'private_inventory', report: await source.inventory() }));
} catch {
  console.error(JSON.stringify({ event: 'private_inventory_failed' }));
  process.exitCode = 1;
} finally { if (source) await source.close(); }
