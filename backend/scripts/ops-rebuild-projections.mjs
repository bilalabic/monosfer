import { ReputationService } from '../dist/reputation/reputation.service.js';
import { withResources,report } from './ops-common.mjs';

await report('projection_rebuild',async()=>{
  const args=process.argv.slice(2);
  if(args.length!==1||!['--apply','--dry-run'].includes(args[0]))throw new Error('Explicit mode required');
  return withResources(({db,config})=>new ReputationService(db,config).rebuild(args[0]==='--apply'));
});
