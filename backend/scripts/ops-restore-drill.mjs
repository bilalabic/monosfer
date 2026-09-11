import { spawn } from 'node:child_process';
import { randomBytes,randomUUID } from 'node:crypto';
import { mkdir,mkdtemp,readFile,writeFile,rm,lstat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join,resolve,sep } from 'node:path';
import assert from 'node:assert/strict';
import { PrivateDataCrypto } from '../dist/private-data/crypto.js';
import { ConfigService } from '../dist/config/config.js';
import { DatabaseService } from '../dist/infrastructure/database.module.js';
import { RedisService } from '../dist/infrastructure/redis.module.js';
import { checksum } from '../dist/providers/adapters.js';
import { requireLocalOperations } from '../dist/reputation/reputation.service.js';
import { withResources,report } from './ops-common.mjs';

function postgresTool(command,args,input) {
  return new Promise((resolveResult,reject)=>{
    const child=spawn('docker',['compose','-f',fileURLToPath(new URL('../compose.yaml',import.meta.url)),'exec','-T','postgres',command,...args],{windowsHide:true,stdio:['pipe','pipe','pipe']});
    const chunks=[];let length=0;const timer=setTimeout(()=>{child.kill();reject(new Error('Fixture tool timeout'));},30000);
    child.stdout.on('data',chunk=>{length+=chunk.length;if(length>4*1024*1024){child.kill();reject(new Error('Fixture output limit'));}else chunks.push(chunk);});
    child.stderr.resume();child.on('error',()=>{clearTimeout(timer);reject(new Error('Fixture tool failed'));});
    child.on('close',code=>{clearTimeout(timer);code===0?resolveResult(Buffer.concat(chunks)):reject(new Error('Fixture tool failed'));});
    child.stdin.on('error',()=>{});child.stdin.end(input);
  });
}
export async function restoreFixture({settings,config,db,redis}) {
  requireLocalOperations(settings);
  const database=new URL(settings.databaseUrl),redisEndpoint=new URL(settings.redisUrl);
  if(database.port!=='55432'||database.username!=='monosfer'||!['127.0.0.1','localhost'].includes(redisEndpoint.hostname))throw new Error('Backend Compose fixture required');
  const id=randomUUID(),schema=`ops_fixture_${id.replaceAll('-','')}`,source=`${schema}_source`;
  assert.match(schema,/^ops_fixture_[0-9a-f]{32}$/);assert.match(source,/^ops_fixture_[0-9a-f]{32}_source$/);
  const base=resolve(fileURLToPath(new URL('../.local/ops-drills/',import.meta.url)));
  await mkdir(base,{recursive:true,mode:0o700});assert.equal((await lstat(base)).isSymbolicLink(),false);
  const directory=await mkdtemp(join(base,'fixture-'));
  assert.ok(resolve(directory).startsWith(base+sep));
  const keys=[`ops:fixture:${id}:source`,`ops:fixture:${id}:restored`],started=Date.now();
  let sourceCreated=false,renamed=false,restoreStarted=false,result;
  try {
    const crypto=new PrivateDataCrypto(settings),aad=`monosfer/restore-fixture/v1/${id}`,payload={fixture:id,content:randomBytes(24).toString('hex')};
    const envelope=crypto.encrypt(payload,aad),object=JSON.stringify(envelope);
    await db.query(`CREATE SCHEMA ${schema}`);sourceCreated=true;
    await db.query(`CREATE TABLE ${schema}.fixture(id uuid PRIMARY KEY,encrypted_payload jsonb NOT NULL,object_hash text NOT NULL)`);
    await db.query(`INSERT INTO ${schema}.fixture VALUES($1,$2,$3)`,[id,envelope,checksum(object)]);
    await writeFile(join(directory,'evidence.original'),object,{flag:'wx',mode:0o600});
    await redis.set(keys[0],JSON.stringify(crypto.encrypt({fixture:id},aad)),60);
    const ttl=await redis.command(c=>c.pTTL(keys[0]));assert.ok(ttl>0);
    const cache=await redis.get(keys[0]);
    const backup=await postgresTool('pg_dump',['-U','monosfer','-d',database.pathname.slice(1),'-Fc','--no-owner','--no-privileges','--schema',schema]);
    await writeFile(join(directory,'fixture.dump'),backup,{flag:'wx',mode:0o600});
    await db.query(`ALTER SCHEMA ${schema} RENAME TO ${source}`);renamed=true;
    restoreStarted=true;
    await postgresTool('pg_restore',['-U','monosfer','-d',database.pathname.slice(1),'--no-owner','--no-privileges','--exit-on-error'],await readFile(join(directory,'fixture.dump')));
    await writeFile(join(directory,'evidence.restored'),await readFile(join(directory,'evidence.original')),{flag:'wx',mode:0o600});
    const row=(await db.query(`SELECT * FROM ${schema}.fixture WHERE id=$1`,[id])).rows[0];assert.ok(row);
    assert.deepEqual(crypto.decrypt(row.encrypted_payload,aad),payload);
    const restored=await readFile(join(directory,'evidence.restored'),'utf8');assert.equal(checksum(restored),row.object_hash);
    assert.deepEqual(crypto.decrypt(JSON.parse(restored),aad),payload);
    const wrong=new PrivateDataCrypto({...settings,privateDataMasterKeyB64:randomBytes(32).toString('base64')});
    assert.throws(()=>wrong.decrypt(row.encrypted_payload,aad));
    const remaining=await redis.command(c=>c.pTTL(keys[0]));assert.ok(remaining>0);
    await redis.command(c=>c.set(keys[1],cache,{PX:remaining}));
    assert.deepEqual(crypto.decrypt(JSON.parse(await redis.get(keys[1])),aad),{fixture:id});
    assert.ok(await redis.command(c=>c.pTTL(keys[1]))<=ttl);
    // Isolated unavailable clients exercise safe readiness and recovery without stopping shared services.
    const unavailableConfig=new ConfigService({...settings,databaseUrl:'postgresql://127.0.0.1:1/unavailable',redisUrl:'redis://127.0.0.1:1',connectionTimeoutMs:100});
    const unavailableDb=new DatabaseService(unavailableConfig),unavailableRedis=new RedisService(unavailableConfig);
    try {await unavailableRedis.onModuleInit();assert.equal(await unavailableDb.ping(),false);assert.equal(await unavailableRedis.ping(),false);}
    finally {unavailableRedis.onApplicationShutdown();await unavailableDb.onApplicationShutdown();}
    assert.equal(await db.ping(),true);assert.equal(await redis.ping(),true);
    const durationMs=Date.now()-started;
    result={status:durationMs<=settings.release.restoreTargetSeconds*1000?'passed':'failed',durationMs,fixtureOnly:true,postgresDumpRestore:true,encryptedObject:true,wrongKeyRejected:true,redisTtl:true,outageRecovery:true,productionRestoreVerified:false};
  } catch {result={status:'failed',durationMs:Date.now()-started,fixtureOnly:true,code:'RESTORE_FIXTURE_FAILED'};}
  finally {
    // Only schemas/keys/files created by this invocation; no shared or production data is removed.
    if(restoreStarted || (sourceCreated&&!renamed))await db.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    if(renamed)await db.query(`DROP SCHEMA ${source} CASCADE`);
    await redis.del(keys);
    assert.ok(resolve(directory).startsWith(base+sep));await rm(directory,{recursive:true});
  }
  await db.query(`INSERT INTO monosfer.ops_drill_runs(id,kind,status,duration_ms,result) VALUES($1,'restore_fixture',$2,$3,$4)`,[id,result.status,result.durationMs,result]);
  return result;
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  await report('restore_drill',async()=>{
    if(process.argv.slice(2).length!==1||process.argv[2]!=='--fixture')throw new Error('Fixture mode required');
    return withResources(restoreFixture);
  });
}
