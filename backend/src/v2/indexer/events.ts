import { decodeEventLog, toEventSelector, type Abi, type Hex } from 'viem';

export const states = ['None', 'Bidding', 'AwaitingFunding', 'ReadyForPickup', 'InTransit', 'DeliveredPending', 'ReturnRequired', 'Disputed', 'Completed', 'Returned', 'Resolved', 'Cancelled', 'Expired'] as const;
export interface ChainBlock { number: bigint; hash: Hex; parentHash: Hex; timestamp: bigint }
export interface ChainLog { address: string; blockNumber: bigint; blockHash: Hex; transactionHash: Hex; transactionIndex: number; logIndex: number; data: Hex; topics: Hex[]; removed?: boolean }
export interface HubEvent { name: string; args: Record<string, string>; log: ChainLog; timestamp?: bigint }
export interface Delivery {
  id: string; customer: string; courier: string; state: string; riskTier: string; termsVersion: string; stateDeadline: string;
  courierAsk: string; protocolFee: string; returnReserve: string; requiredCollateral: string;
  etaDeadline: string; etaMinutes: string; completedAt: string;
  customerFunded: boolean; courierFunded: boolean; quoteDigest: string; creationTxHash: string;
}
export interface Bid { courier: string; courierAsk: string; returnAsk: string; etaMinutes: string; validUntil: string; termsVersion: string; active: boolean }
export interface Projection { delivery: Delivery | null; bids: Record<string, Bid> }
export const zeroAddress = `0x${'0'.repeat(40)}`;
export function decodeLogs(abi: Abi, address: string, blocks: ChainBlock[], logs: ChainLog[]): HubEvent[] {
  const hashes = new Map(blocks.map(b => [b.number.toString(), b.hash.toLowerCase()]));
  const topics = new Set(abi.filter(item => item.type === 'event').map(item => toEventSelector(item)));
  const seen = new Map<string, string>(); const events: HubEvent[] = [];
  for (const log of logs) {
    if (log.address.toLowerCase() !== address.toLowerCase() || log.removed || hashes.get(log.blockNumber.toString()) !== log.blockHash.toLowerCase() ||
      !Number.isSafeInteger(log.logIndex) || log.logIndex < 0 || !Number.isSafeInteger(log.transactionIndex) || log.transactionIndex < 0 ||
      !/^0x[0-9a-fA-F]{64}$/.test(log.transactionHash) || !topics.has(log.topics[0]!)) throw new Error('Invalid hub event');
    const key = `${log.blockHash}:${log.logIndex}`;
    const signature = JSON.stringify(log, (_key, value) => typeof value === 'bigint' ? value.toString() : value);
    if (seen.has(key)) { if (seen.get(key) !== signature) throw new Error('Conflicting duplicate event'); continue; }
    seen.set(key, signature);
    const decoded = decodeEventLog({ abi, data: log.data, topics: log.topics as [Hex, ...Hex[]], strict: true });
    const args = Object.fromEntries(Object.entries(decoded.args ?? {}).map(([key, value]) => [key, String(value).toLowerCase()]));
    events.push({ name: decoded.eventName!, args, log, timestamp: blocks.find(b => b.number === log.blockNumber)!.timestamp });
  }
  return events.sort((a, b) => a.log.blockNumber !== b.log.blockNumber ? (a.log.blockNumber < b.log.blockNumber ? -1 : 1) : a.log.transactionIndex - b.log.transactionIndex || a.log.logIndex - b.log.logIndex);
}
export function reduceEvent(projection: Projection, event: HubEvent): void {
  const a = event.args; const id = a.deliveryId;
  if (!id) return; // Known inherited events remain in the inbox for audit.
  if (event.name === 'DeliveryCreated') {
    if (projection.delivery) throw new Error('Duplicate delivery creation');
    projection.delivery = { id, customer: a.customer!, courier: zeroAddress, state: 'None', riskTier: a.riskTier!, termsVersion: '0',
      stateDeadline: a.deadline!, courierAsk: '0', protocolFee: '0', returnReserve: '0', requiredCollateral: a.requiredCollateral!,
      etaDeadline: '0', etaMinutes: '0', completedAt: '0', customerFunded: false, courierFunded: false, quoteDigest: a.quoteDigest!, creationTxHash: event.log.transactionHash };
    return;
  }
  const d = projection.delivery;
  if (!d || d.id !== id) throw new Error('Missing delivery creation');
  const bid = a.courier ? projection.bids[a.courier] : undefined;
  switch (event.name) {
    case 'BidPlaced':
      if (d.state !== 'Bidding' || BigInt(a.termsVersion!) !== BigInt(bid?.termsVersion ?? '0') + 1n) throw new Error('Invalid bid version');
      projection.bids[a.courier!] = { courier: a.courier!, courierAsk: a.courierAsk!, returnAsk: a.returnAsk!, etaMinutes: a.etaMinutes!, validUntil: a.validUntil!, termsVersion: a.termsVersion!, active: true }; break;
    case 'BidWithdrawn':
      if (!bid?.active || d.courier === a.courier) throw new Error('Invalid bid withdrawal');
      bid.active = false; break;
    case 'CourierSelected':
      if (!bid?.active || d.state !== 'AwaitingFunding' || bid.courierAsk !== a.courierAsk || d.courier !== zeroAddress) throw new Error('Invalid courier selection');
      d.courier = a.courier!; d.courierAsk = a.courierAsk!; d.protocolFee = a.protocolFee!; d.returnReserve = bid.returnAsk; d.termsVersion = bid.termsVersion; d.etaMinutes = bid.etaMinutes; break;
    case 'CustomerFunded':
      if (d.state !== 'AwaitingFunding' || d.customerFunded || BigInt(a.amount!) !== BigInt(d.courierAsk) + BigInt(d.protocolFee) + BigInt(d.returnReserve)) throw new Error('Invalid customer funding');
      d.customerFunded = true; break;
    case 'CourierFunded':
      if (d.state !== 'AwaitingFunding' || d.courierFunded || a.courier !== d.courier || !bid?.active) throw new Error('Invalid courier funding');
      d.courierFunded = true; bid.active = false; break;
    case 'StateChanged': {
      const from = states[Number(a.from)]; const to = states[Number(a.to)];
      const allowed: Record<string, string[]> = { None: ['Bidding'], Bidding: ['AwaitingFunding', 'Cancelled', 'Expired'], AwaitingFunding: ['ReadyForPickup', 'Cancelled'], ReadyForPickup: ['InTransit', 'Cancelled'], InTransit: ['DeliveredPending', 'ReturnRequired', 'Disputed'], DeliveredPending: ['Completed', 'Disputed'], ReturnRequired: ['Returned', 'Disputed'], Disputed: ['Resolved'] };
      if (d.state !== from || !to || !allowed[from!]?.includes(to) || (Number(a.to) >= 8 && a.deadline !== '0') ||
        (to === 'ReadyForPickup' && (!d.customerFunded || !d.courierFunded))) throw new Error('Invalid lifecycle transition');
      if (to === 'Cancelled' && from !== 'Bidding' && !d.courierFunded && projection.bids[d.courier]) projection.bids[d.courier]!.active = false;
      if (to === 'Completed') { if (event.timestamp === undefined) throw new Error('Block timestamp required; reindex'); d.completedAt = String(event.timestamp); }
      d.state = to; d.stateDeadline = a.deadline!; break;
    }
    case 'Settled': if (d.state !== states[Number(a.finalState)] || Number(a.finalState) < 8) throw new Error('Invalid settlement'); break;
    case 'PickupConfirmed':
      if (event.timestamp === undefined) throw new Error('Block timestamp required; reindex');
      d.etaDeadline = String(event.timestamp + BigInt(d.etaMinutes) * 60n);
      if (d.courier !== a.courier) throw new Error('Invalid courier proof'); break;
    case 'DeliveryProofSubmitted': case 'ReturnConfirmed': if (d.courier !== a.courier) throw new Error('Invalid courier proof'); break;
  }
}
