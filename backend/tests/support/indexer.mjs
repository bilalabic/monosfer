import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { encodeEventTopics, encodeAbiParameters, decodeFunctionData, encodeFunctionResult, toHex } from 'viem';
import { loadBundle } from '../../dist/indexer/config.js';

export const hashOf = value => `0x${createHash('sha256').update(String(value)).digest('hex')}`;
export function hubFixture(customerAddress) {
  const upstream = loadBundle();
  const address = `0x${randomBytes(20).toString('hex')}`;
  const bundle = { ...upstream, chains: { 10143: { chainId: 10143, address, block: 100 } } };
  const customer = customerAddress?.toLowerCase() ?? `0x${randomBytes(20).toString('hex')}`;
  const courier = `0x${randomBytes(20).toString('hex')}`;
  const other = `0x${randomBytes(20).toString('hex')}`;
  const blocks = new Map(); const logs = new Map();
  for (let n = 99; n <= 108; n++) blocks.set(BigInt(n), { number: BigInt(n), hash: hashOf(`initial${n}`), parentHash: hashOf(`initial${n-1}`) });
  const settings = { enabled: true, chainId: 10143, rpcUrl: '', batchSize: 2, pollMs: 250, maxLag: 0, staleSeconds: 30, reorgDepth: 8,
    deployment: bundle.chains[10143], fingerprint: bundle.fingerprint };
  const fixture = { bundle, settings, customer, courier, other, address, blocks, logs, head: 102n, wrongChain: false, corrupt: false, drift: false, duplicate: true, requests: [] };
  fixture.event = (number, name, args) => {
    const height = BigInt(number); const current = logs.get(height) ?? [];
    const definition = bundle.abi.find(item => item.type === 'event' && item.name === name);
    const nonIndexed = definition.inputs.filter(input => !input.indexed);
    const log = { address, blockNumber: height, blockHash: blocks.get(height).hash, transactionHash: hashOf(`${height}:${current.length}`),
      transactionIndex: current.length, logIndex: current.length, removed: false,
      topics: encodeEventTopics({ abi: bundle.abi, eventName: name, args }), data: encodeAbiParameters(nonIndexed, nonIndexed.map(input => args[input.name])) };
    current.push(log); logs.set(height, current); return log;
  };
  const event = fixture.event; const deliveryId = 0n;
  event(100,'DeliveryCreated',{ deliveryId, customer, riskTier: 1, requiredCollateral: 5000n, deadline: 1000n, quoteDigest: hashOf('quote') });
  event(100,'StateChanged',{deliveryId, from:0,to:1,deadline:1000n});
  event(101,'BidPlaced',{deliveryId,courier,courierAsk:100n,returnAsk:20n,etaMinutes:15,validUntil:2000n,termsVersion:1});
  event(101,'BidPlaced',{deliveryId,courier,courierAsk:200n,returnAsk:20n,etaMinutes:10,validUntil:2000n,termsVersion:2});
  event(101,'BidPlaced',{deliveryId,courier:other,courierAsk:300n,returnAsk:30n,etaMinutes:20,validUntil:2000n,termsVersion:1});
  event(101,'StateChanged',{deliveryId,from:1,to:2,deadline:1500n});
  event(101,'CourierSelected',{deliveryId,courier,courierAsk:200n,protocolFee:10n});
  event(102,'CustomerFunded',{deliveryId,amount:230n});
  event(102,'CourierFunded',{deliveryId,courier,reservedBase:5000n,additionalBond:0n});
  event(102,'StateChanged',{deliveryId,from:2,to:3,deadline:1800n});
  event(103,'PickupConfirmed',{deliveryId,courier});
  event(103,'StateChanged',{deliveryId,from:3,to:4,deadline:2200n});
  event(104,'DeliveryProofSubmitted',{deliveryId,courier});
  event(104,'StateChanged',{deliveryId,from:4,to:5,deadline:2500n});
  event(105,'StateChanged',{deliveryId,from:5,to:7,deadline:0n});
  event(105,'Settled',{deliveryId,finalState:7});
  fixture.deliveryAt = height => {
    const n = Number(height);
    const state = n < 100 ? 0 : n === 100 ? 1 : n === 101 ? 2 : n === 102 ? 3 : n === 103 ? 4 : n === 104 ? 5 : 7;
    return { customer, courier: n < 101 ? `0x${'0'.repeat(40)}` : courier, state: fixture.drift ? 9 : state, riskTier: 1,
      termsVersion: n < 101 ? 0 : 2, stateDeadline: BigInt(({ 0:0,1:1000,2:1500,3:1800,4:2200,5:2500,7:0 })[state]),
      courierAsk: n < 101 ? 0n : 200n, protocolFee: n < 101 ? 0n : 10n, returnReserve: n < 101 ? 0n : 20n, requiredCollateral: 5000n,
      customerFunded: n >= 102, courierFunded: n >= 102 };
  };
  fixture.bidAt = (who, height) => ({ courierAsk: who.toLowerCase() === courier ? 200n : 300n,
    returnAsk: who.toLowerCase() === courier ? 20n : 30n, etaMinutes: who.toLowerCase() === courier ? 10 : 20, validUntil: 2000n,
    termsVersion: who.toLowerCase() === courier ? 2 : 1, active: who.toLowerCase() !== courier || height < 102n });
  return fixture;
}

export async function rpcServer(fixture) {
  const server = createServer(async (request, response) => {
    let body = ''; for await (const chunk of request) body += chunk;
    const call = JSON.parse(body); fixture.requests.push(call.method);
    try {
      const [a,b] = call.params ?? []; let result;
      switch(call.method) {
        case 'eth_chainId': result = toHex(fixture.wrongChain ? 1 : 10143); break;
        case 'eth_getCode': result = '0x60016001'; break;
        case 'eth_getBlockByNumber': {
          const block = fixture.blocks.get(a === 'finalized' ? fixture.head : BigInt(a));
          if (!block) throw new Error();
          result = { number: toHex(block.number), hash:block.hash, parentHash:block.parentHash, transactions:[], timestamp:'0x1', gasLimit:'0x1',gasUsed:'0x0',size:'0x1',difficulty:'0x0',extraData:'0x',nonce:'0x0000000000000000',miner:fixture.customer,logsBloom:`0x${'0'.repeat(512)}` }; break;
        }
        case 'eth_getLogs': {
          const found = [...fixture.logs.entries()].filter(([height]) => height>=BigInt(a.fromBlock) && height<=BigInt(a.toBlock)).flatMap(([,values])=>values);
          result = found.map(log=>({...log, blockNumber:toHex(log.blockNumber),transactionIndex:toHex(log.transactionIndex),logIndex:toHex(log.logIndex)})).reverse();
          if(fixture.duplicate && result[0]) result.push({...result[0]});
          if(fixture.corrupt && result[0]) result[0]={...result[0],data:'0x01'};
          break;
        }
        case 'eth_call': {
          const { functionName,args } = decodeFunctionData({abi:fixture.bundle.abi,data:a.data});
          const height=BigInt(b);
          result=encodeFunctionResult({abi:fixture.bundle.abi,functionName,result:functionName==='nextDeliveryId' ? (height>=100n?1n:0n) : functionName==='deliveryOf' ? fixture.deliveryAt(height) : fixture.bidAt(args[1],height)}); break;
        }
        default: throw new Error('Unexpected RPC write or method');
      }
      response.setHeader('content-type','application/json'); response.end(JSON.stringify({jsonrpc:'2.0',id:call.id,result}));
    } catch { response.end(JSON.stringify({jsonrpc:'2.0',id:call.id,error:{code:-32603,message:'RPC_PRIVATE_SECRET'}})); }
  });
  server.listen(0,'127.0.0.1'); await once(server,'listening');
  return { url:`http://127.0.0.1:${server.address().port}`, close:()=>new Promise(resolve=>server.close(resolve)) };
}
