import 'reflect-metadata';
import { setTimeout } from 'node:timers/promises';
import { parseSettings, ConfigService } from '../dist/config/config.js';
import { DatabaseService } from '../dist/infrastructure/database.module.js';
import { DeliveryAccess } from '../dist/operations/access.js';
import { ProviderJobs } from '../dist/providers/jobs.js';
import { ProviderWorker } from '../dist/providers/worker.js';
import { LocalEvidenceStorage, InAppNotificationProvider } from '../dist/providers/adapters.js';
import { assertImportTarget } from '../dist/private-data/importer.js';
let database;const stop=new AbortController();const shutdown=()=>stop.abort();
process.once('SIGTERM',shutdown);process.once('SIGINT',shutdown);
try{
  const [command,id,...extra]=process.argv.slice(2);
  if(!['once','watch','retry'].includes(command)||extra.length||(command==='retry'?!/^[0-9a-f-]{36}$/.test(id??''):id!==undefined))throw new Error();
  assertImportTarget(process.env,'apply',false);const config=new ConfigService(parseSettings(process.env));
  if(!config.settings.operations.workerEnabled||config.settings.environment==='production')throw new Error();
  database=new DatabaseService(config);const access=new DeliveryAccess(database,config);
  if(command==='retry'){
    access.available();const s=config.settings.indexer;const stream=`${s.chainId}:${s.deployment.address.toLowerCase()}`;
    await database.transaction(async client=>{
      const result=await client.query("UPDATE monosfer.provider_jobs SET status='pending',attempts=0,next_attempt_at=now(),last_error=NULL WHERE id=$1 AND stream=$2 AND status='failed' RETURNING evidence_id",[id,stream]);
      if(!result.rowCount)throw new Error();
      if(result.rows[0].evidence_id)await client.query("UPDATE monosfer.evidence_packages SET status='pending' WHERE id=$1",[result.rows[0].evidence_id]);
    });console.log(JSON.stringify({event:'provider_retry_scheduled'}));
  }else{
    const worker=new ProviderWorker(database,config,access,new ProviderJobs(config),new LocalEvidenceStorage(),new InAppNotificationProvider());
    let failures=0;
    do{
      try{console.log(JSON.stringify({event:'provider_batch',...await worker.once()}));failures=0;}
      catch{if(command==='once')throw new Error();failures=Math.min(failures+1,5);console.error(JSON.stringify({event:'provider_batch_failed'}));}
      if(command==='once')break;
      try{await setTimeout(Math.min(config.settings.operations.workerPollMs*2**failures,60000),undefined,{signal:stop.signal});}catch{/* stop */}
    }while(!stop.signal.aborted);
  }
}catch{console.error(JSON.stringify({event:'provider_worker_failed'}));process.exitCode=1;}
finally{await database?.onApplicationShutdown();process.removeListener('SIGTERM',shutdown);process.removeListener('SIGINT',shutdown);}
