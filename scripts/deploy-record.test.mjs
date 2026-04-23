import test from "node:test";
import assert from "node:assert/strict";

import { buildDeploymentRecord, parseEnvFile } from "./deploy-record.mjs";

test("parseEnvFile reads simple dotenv values and ignores comments", () => {
  const env = parseEnvFile(`
    # local values
    MONAD_TESTNET_RPC_URL=https://testnet-rpc.monad.xyz
    PRIVATE_KEY=0xabc
  `);

  assert.deepEqual(env, {
    MONAD_TESTNET_RPC_URL: "https://testnet-rpc.monad.xyz",
    PRIVATE_KEY: "0xabc",
  });
});

test("buildDeploymentRecord extracts the Counter create transaction", () => {
  const record = buildDeploymentRecord(
    {
      transactions: [
        {
          contractName: "Counter",
          contractAddress: "0x1111111111111111111111111111111111111111",
          hash: "0x2222",
          transactionType: "CREATE",
        },
      ],
    },
    {
      chainId: 10143,
      contractName: "Counter",
      rpcUrl: "https://testnet-rpc.monad.xyz",
    },
  );

  assert.deepEqual(record, {
    contractName: "Counter",
    address: "0x1111111111111111111111111111111111111111",
    chainId: 10143,
    rpcUrl: "https://testnet-rpc.monad.xyz",
    transactionHash: "0x2222",
  });
});
