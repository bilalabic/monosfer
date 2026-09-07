import 'reflect-metadata';
import { setTimeout } from 'node:timers/promises';
import { parseSettings, ConfigService } from '../dist/config/config.js';
import { DatabaseService } from '../dist/infrastructure/database.module.js';
import { QuotesRepository } from '../dist/quotes/quotes.repository.js';
import { QuoteLinkWorker } from '../dist/quotes/link-worker.js';
import { assertImportTarget } from '../dist/private-data/importer.js';

const stop=new AbortController(); const shutdown=()=>stop.abort(); let database;
process.once('SIGTERM',shutdown);process.once('SIGINT',shutdown);
try {
  const [command,...args]=process.argv.slice(2);
  if (!['once','watch'].includes(command)||args.length) throw new Error();
  // Phase 5 executable is deliberately local-only; production policy is not approved.
  assertImportTarget(process.env,'apply',false);
  const settings=parseSettings(process.env);
  if (!settings.quotes.workerEnabled||settings.environment==='production') throw new Error();
  const config=new ConfigService(settings);database=new DatabaseService(config);
  const worker=new QuoteLinkWorker(config,new QuotesRepository(database,config));
  let failures=0;
  do {
    try { console.log(JSON.stringify({event:'quote_link_batch',...await worker.once()}));failures=0; }
    catch { if(command==='once') throw new Error();failures=Math.min(failures+1,5);console.error(JSON.stringify({event:'quote_link_batch_failed'})); }
    if(command==='once') break;
    try {await setTimeout(Math.min(settings.quotes.pollMs*2**failures,60000),undefined,{signal:stop.signal});} catch { /* shutdown */ }
  }while(!stop.signal.aborted);
}catch{console.error(JSON.stringify({event:'quote_worker_failed'}));process.exitCode=1;}
finally{await database?.onApplicationShutdown();process.removeListener('SIGTERM',shutdown);process.removeListener('SIGINT',shutdown);}
