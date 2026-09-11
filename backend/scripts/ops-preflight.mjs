import { readFile,readdir,lstat } from 'node:fs/promises';
import { OpsService } from '../dist/ops/ops.service.js';
import { IndexerReadRepository } from '../dist/indexer/read.module.js';
import { LocalEvidenceStorage } from '../dist/providers/adapters.js';
import { withResources,report } from './ops-common.mjs';

await report('ops_preflight',()=>withResources(async({settings,config,db,redis})=>{
  const checks={config:true,migrations:false,openapi:false,storage:false,postgres:await db.ping(),redis:await redis.ping(),opsToken:!!settings.release.metricsToken};
  const applied=(await db.query('SELECT name FROM public.pgmigrations')).rows.map(r=>r.name);
  const files=(await readdir(new URL('../migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).map(f=>f.slice(0,-4));
  checks.migrations=files.every(f=>applied.includes(f));
  const document=JSON.parse(await readFile(new URL('../artifacts/openapi.json',import.meta.url),'utf8'));
  checks.openapi=['/v1/support/cases','/v1/admin/audit','/v1/ops/status','/v1/users/me/reputation'].every(p=>!!document.paths[p]);
  const storage=new LocalEvidenceStorage();
  try {const info=await lstat(storage.root);checks.storage=info.isDirectory()&&!info.isSymbolicLink();}
  catch(error) {if(error.code!=='ENOENT')throw error;checks.storage=!settings.operations.enabled;}
  const ops=await new OpsService(db,redis,config,new IndexerReadRepository(db,config)).status();
  return {status:Object.values(checks).every(Boolean)?'passed':'failed',checks,ops,productionReady:false};
}));
