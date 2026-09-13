// Explicit local verification harness. Never used by runtime or production CLI commands.
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { authEnv } from './env.mjs';
const modes={'preflight':'ops:preflight','restore':'ops:restore-drill','smoke':'ops:testnet-smoke'};
const script=modes[process.argv[2]];if(!script)throw new Error('Invalid verification mode');
const env={...process.env,...authEnv,NODE_ENV:'test',DATABASE_URL:'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2',
  REDIS_URL:'redis://:local-development-only@127.0.0.1:56379',CORS_ORIGINS:'https://app.example.com',
  INDEXER_ENABLED:'false',OPERATIONS_ENABLED:'false',SUPPORT_ENABLED:'false',QUOTE_LINK_WORKER_ENABLED:'false',PROVIDER_WORKER_ENABLED:'false',
  OPS_METRICS_TOKEN:randomBytes(32).toString('hex')};
const args=['run',script,...(process.argv[2]==='restore'?['--','--fixture']:[])];
const child=process.platform==='win32'
  ?spawn('cmd.exe',['/d','/s','/c',`npm.cmd ${args.join(' ')}`],{cwd:fileURLToPath(new URL('../../',import.meta.url)),env,stdio:'inherit',windowsHide:true})
  :spawn('npm',args,{cwd:fileURLToPath(new URL('../../',import.meta.url)),env,stdio:'inherit'});
child.on('error',()=>{process.exitCode=1;});child.on('close',code=>{process.exitCode=code??1;});
