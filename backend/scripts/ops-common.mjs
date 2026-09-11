import 'reflect-metadata';
import { ConfigService, parseSettings } from '../dist/config/config.js';
import { DatabaseService } from '../dist/infrastructure/database.module.js';
import { RedisService } from '../dist/infrastructure/redis.module.js';

export async function withResources(work) {
  const settings=parseSettings(process.env),config=new ConfigService(settings),db=new DatabaseService(config),redis=new RedisService(config);
  try {await redis.onModuleInit();return await work({settings,config,db,redis});}
  finally {redis.onApplicationShutdown();await db.onApplicationShutdown();}
}
export async function report(event,work) {
  try {const result=await work();console.log(JSON.stringify({event,...result}));if(result.status==='failed')process.exitCode=1;}
  catch {console.error(JSON.stringify({event,status:'failed',code:'OPS_CHECK_FAILED'}));process.exitCode=1;}
}
