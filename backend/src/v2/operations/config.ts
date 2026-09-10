export interface OperationsSettings {
  enabled: boolean; sessionTtl: number; locationTtl: number; eventTtl: number; pollMs: number;
  realtimePort: number; streamSeconds: number; maxConnections: number; routeTtl: number;
  workerEnabled: boolean; workerPollMs: number; providerTimeoutMs: number; maxAttempts: number;
}
export function parseOperationsSettings(env: NodeJS.ProcessEnv): OperationsSettings {
  const flag=(key:string)=>{const v=env[key]??'false';if(!['true','false'].includes(v))throw new Error(`Invalid ${key}`);return v==='true';};
  const int=(key:string,value:number,min:number,max:number)=>{const s=env[key]??String(value);const n=Number(s);
    if(!/^\d+$/.test(s)||!Number.isSafeInteger(n)||n<min||n>max)throw new Error(`Invalid ${key}`);return n;};
  const enabled=flag('OPERATIONS_ENABLED');const workerEnabled=flag('PROVIDER_WORKER_ENABLED');
  if(enabled&&(env.NODE_ENV==='production'||env.INDEXER_ENABLED!=='true'))throw new Error('Invalid OPERATIONS_ENABLED');
  if(workerEnabled&&!enabled)throw new Error('Invalid PROVIDER_WORKER_ENABLED');
  return {enabled,workerEnabled,sessionTtl:int('TRACKING_SESSION_TTL_SECONDS',300,1,900),
    locationTtl:int('TRACKING_LOCATION_TTL_SECONDS',60,1,300),eventTtl:int('TRACKING_EVENT_TTL_SECONDS',180,1,900),
    pollMs:int('TRACKING_POLL_MS',1000,100,5000),realtimePort:int('REALTIME_PORT',3002,1,65535),
    streamSeconds:int('TRACKING_STREAM_SECONDS',60,1,300),maxConnections:int('TRACKING_MAX_CONNECTIONS',100,1,1000),
    routeTtl:int('ROUTE_CACHE_TTL_SECONDS',30,1,300),workerPollMs:int('PROVIDER_WORKER_POLL_MS',2000,250,60000),
    providerTimeoutMs:int('PROVIDER_TIMEOUT_MS',1000,100,5000),maxAttempts:int('PROVIDER_MAX_ATTEMPTS',3,1,10)};
}
