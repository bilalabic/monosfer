import type { PoolClient } from 'pg';
import type { HubEvent } from './events.js';

export interface Dispute {
  id: string; deliveryId: string; opener: string; status: string; round: string;
  evidenceCount: number; committeeResolutionAlert: boolean; ruling?: string; customerBps?: string; panel?: string[];
}
export function reduceDispute(current: Dispute | null, event: Pick<HubEvent, 'name'|'args'>): Dispute | null {
  const a = event.args;
  if (!a.disputeId) return current;
  if (event.name === 'DisputeOpened') {
    if (current || !a.deliveryId || !a.opener) throw new Error('Invalid dispute creation');
    return {id:a.disputeId,deliveryId:a.deliveryId,opener:a.opener,status:'opened',round:'0',evidenceCount:0,committeeResolutionAlert:false};
  }
  if (!current || current.id !== a.disputeId) throw new Error('Missing dispute creation');
  switch (event.name) {
    case 'EvidenceSubmitted': current.evidenceCount++; break;
    case 'PanelSeated': current.status='panel_seated'; current.round=a.round!; current.panel=a.panel?.split(',').filter(Boolean)??[]; break;
    case 'Appealed': current.status='appealed'; current.round=a.round!; break;
    case 'ResolvedByCommittee': current.committeeResolutionAlert=true; current.ruling=a.ruling!; break;
    case 'DisputeSettled': current.status='settled'; current.ruling=a.ruling!; current.customerBps=a.customerBps!; break;
    case 'DisputeAbandoned': current.status='abandoned'; break;
  }
  return current;
}
export async function reconstructDispute(db: PoolClient, stream: string, id: string) {
  let data: Dispute | null = null;
  const rows=await db.query('SELECT event_name,args FROM monosfer.dispute_event_inbox WHERE stream=$1 AND dispute_id=$2 AND canonical ORDER BY block_number,transaction_index,log_index',[stream,id]);
  for (const row of rows.rows) data=reduceDispute(data,{name:row.event_name,args:row.args});
  return data;
}
export async function replayDispute(db: PoolClient, stream: string, id: string, block: bigint) {
  const data=await reconstructDispute(db,stream,id);
  if (!data) { await db.query('DELETE FROM monosfer.dispute_projections WHERE stream=$1 AND dispute_id=$2',[stream,id]); return; }
  await db.query(`INSERT INTO monosfer.dispute_projections(stream,dispute_id,delivery_id,data,updated_block) VALUES($1,$2,$3,$4,$5)
    ON CONFLICT(stream,dispute_id) DO UPDATE SET delivery_id=excluded.delivery_id,data=excluded.data,updated_block=excluded.updated_block`,[stream,id,data.deliveryId,data,String(block)]);
}
export async function applyDisputes(db: PoolClient, stream: string, events: HubEvent[], block: bigint) {
  const ids=new Set<string>();
  for (const e of events) {
    await db.query(`INSERT INTO monosfer.dispute_event_inbox(stream,block_hash,block_number,log_index,transaction_index,dispute_id,event_name,args,canonical)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,true) ON CONFLICT(stream,block_hash,log_index) DO UPDATE SET canonical=true`,
      [stream,e.log.blockHash,String(e.log.blockNumber),e.log.logIndex,e.log.transactionIndex,e.args.disputeId??null,e.name,e.args]);
    if (e.args.disputeId) ids.add(e.args.disputeId);
  }
  for (const id of ids) await replayDispute(db,stream,id,block);
}
