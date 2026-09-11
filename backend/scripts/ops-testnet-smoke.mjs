import { testnetSmoke } from '../dist/ops/testnet-smoke.js';
import { report } from './ops-common.mjs';

await report('testnet_read_only_smoke',()=>testnetSmoke(process.env.TESTNET_SMOKE_RPC_URL??''));
