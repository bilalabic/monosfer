import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const rootDir = process.cwd();
const localRpcUrl = process.env.LOCAL_RPC_URL || "http://127.0.0.1:8545";
const artifactPath = path.join(
  rootDir,
  "contracts",
  "out",
  "Counter.sol",
  "Counter.json",
);
const deploymentsDir = path.join(rootDir, "contracts", "deployments");
const deploymentPath = path.join(deploymentsDir, "local.json");

async function rpc(method, params = []) {
  const response = await fetch(localRpcUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method,
      params,
    }),
  });

  if (!response.ok) {
    throw new Error(`RPC request failed with status ${response.status}`);
  }

  const payload = await response.json();

  if (payload.error) {
    throw new Error(`${method} failed: ${payload.error.message}`);
  }

  return payload.result;
}

function toHex(value) {
  return `0x${value.toString(16)}`;
}

async function waitForReceipt(transactionHash) {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const receipt = await rpc("eth_getTransactionReceipt", [transactionHash]);

    if (receipt) {
      return receipt;
    }

    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  throw new Error(`Timed out while waiting for receipt: ${transactionHash}`);
}

async function main() {
  const artifactRaw = await readFile(artifactPath, "utf8");
  const artifact = JSON.parse(artifactRaw);
  const bytecode = artifact.bytecode?.object;

  if (!bytecode) {
    throw new Error("Counter bytecode not found. Run `npm run contracts:build` first.");
  }

  const deploymentBytecode = bytecode.startsWith("0x") ? bytecode : `0x${bytecode}`;

  const [deployer] = await rpc("eth_accounts");

  if (!deployer) {
    throw new Error("No unlocked account found on the local chain.");
  }

  const gasEstimate = await rpc("eth_estimateGas", [
    {
      from: deployer,
      data: deploymentBytecode,
    },
  ]);

  const transactionHash = await rpc("eth_sendTransaction", [
    {
      from: deployer,
      data: deploymentBytecode,
      gas: gasEstimate || toHex(3_000_000),
    },
  ]);

  const receipt = await waitForReceipt(transactionHash);
  const chainIdHex = await rpc("eth_chainId");

  await mkdir(deploymentsDir, { recursive: true });
  await writeFile(
    deploymentPath,
    JSON.stringify(
      {
        contractName: "Counter",
        address: receipt.contractAddress,
        transactionHash,
        chainId: Number.parseInt(chainIdHex, 16),
        rpcUrl: localRpcUrl,
      },
      null,
      2,
    ),
  );

  console.log(`Counter deployed to ${receipt.contractAddress}`);
  console.log(`Saved deployment to ${deploymentPath}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
