import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { localEnv, root } from './local-env.mjs';

const env=await localEnv();
const commands={backend:['node','dist/main.js'],realtime:['node','dist/realtime.js'],indexer:['node','scripts/indexer.mjs','watch'],quotes:['node','scripts/quote-worker.mjs','watch'],frontend:['npm','run','dev'],migrate:['node','scripts/migrate.mjs']};
const mode=process.argv[2];
if(!commands[mode])throw new Error('Expected backend, realtime, indexer, quotes, frontend or migrate');
if(mode==='frontend') { env.PORT='3000'; env.HOST='localhost'; }
const [cmd,...args]=commands[mode];
const child=spawn(cmd,args,{cwd:fileURLToPath(new URL(mode==='frontend'?'frontend/':'backend/',root)),env,stdio:'inherit'});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>child.kill(signal));
child.on('exit',code=>process.exit(code??0));
