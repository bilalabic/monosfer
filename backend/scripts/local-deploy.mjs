import { readFile, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createPublicClient, createWalletClient, http } from 'viem';
import { foundry } from 'viem/chains';
import { localAccount, localRpc, root } from './local-env.mjs';

const client = createPublicClient({ chain: foundry, transport: http(localRpc) });
if (await client.getChainId() !== 31337) throw new Error('Local deployment requires chain 31337');
const manifestPath = new URL('contracts/deployments/31337.json', root);
let manifest;
try { manifest = JSON.parse(await readFile(manifestPath, 'utf8')); } catch { /* fresh local chain */ }
if (!manifest || !await client.getCode({address:manifest.contracts.DeliveryHub.address})) {
  const admin = localAccount(0);
  const key = `0x${Buffer.from(admin.getHdKey().privateKey).toString('hex')}`;
  const roles = { PRIVATE_KEY: key, EXPECTED_CHAIN_ID: '31337', DEFAULT_ADMIN: admin.address,
    CONFIG_ADMIN: localAccount(1).address, EMERGENCY_ADMIN: localAccount(2).address, SIGNER_ADMIN: localAccount(3).address,
    TREASURER: localAccount(1).address, TREASURY: localAccount(1).address,
    RISK_QUOTE_SIGNER: localAccount(2).address, POD_ATTESTATION_SIGNER: localAccount(3).address };
  const deployed = spawnSync('forge', ['script','script/v1/DeployCore.s.sol:DeployCoreScript','--rpc-url',localRpc,'--broadcast','--offline','--non-interactive','--disable-code-size-limit'],
    { cwd: fileURLToPath(new URL('contracts/', root)), env: {...process.env,...roles}, encoding:'utf8' });
  if (deployed.status !== 0) throw new Error(`Local core deployment failed: ${deployed.stderr}`);
  const broadcast = JSON.parse(await readFile(new URL('contracts/broadcast/DeployCore.s.sol/31337/run-latest.json', root), 'utf8'));
  const contracts = Object.fromEntries(broadcast.transactions.filter(tx=>tx.transactionType==='CREATE').map(tx=>{
    const receipt = broadcast.receipts.find(row=>row.transactionHash===tx.hash);
    return [tx.contractName,{address:tx.contractAddress.toLowerCase(),block:Number(BigInt(receipt.blockNumber)),txHash:tx.hash}];
  }));
  manifest = {chainId:31337,name:'Monosfer Local Test',rpcUrl:localRpc,explorer:'',contracts};
  await writeFile(manifestPath,JSON.stringify(manifest,null,2)+'\n');
}
const wallet = createWalletClient({account:localAccount(0),chain:foundry,transport:http(localRpc)});
const artifact = JSON.parse(await readFile(new URL('contracts/out/ProtocolAccessManager.sol/ProtocolAccessManager.json',root),'utf8'));
const access = manifest.contracts.ProtocolAccessManager.address;
for (const [role,target] of [['VAULT_CONTROLLER_ROLE','CourierRegistry'],['VAULT_CONTROLLER_ROLE','DeliveryHub'],['REGISTRY_CONTROLLER_ROLE','DeliveryHub'],['REPUTATION_REPORTER_ROLE','DeliveryHub'],['REFERRAL_REPORTER_ROLE','DeliveryHub']]) {
  const value=await client.readContract({address:access,abi:artifact.abi,functionName:role});
  const address=manifest.contracts[target].address;
  if (!await client.readContract({address:access,abi:artifact.abi,functionName:'hasRole',args:[value,address]})) {
    const hash=await wallet.writeContract({address:access,abi:artifact.abi,functionName:'grantRole',args:[value,address]});
    const receipt=await client.waitForTransactionReceipt({hash});
    if(receipt.status!=='success')throw new Error('Local role grant failed');
  }
}
console.log('Local core deployed and roles verified (31337).');
