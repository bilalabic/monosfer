import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { buildDeploymentRecord, parseEnvFile } from "./deploy-record.mjs";

const rootDir = process.cwd();
const contractsDir = path.join(rootDir, "contracts");
const envPath = path.join(contractsDir, ".env");
const frontendEnvPath = path.join(rootDir, "frontend", ".env");
const broadcastPath = path.join(
  contractsDir,
  "broadcast",
  "Deploy.s.sol",
  "10143",
  "run-latest.json",
);
const deploymentPath = path.join(
  contractsDir,
  "deployments",
  "monad-testnet.json",
);

const DEFAULT_TESTNET_RPC_URL = "https://testnet-rpc.monad.xyz";

async function loadContractEnv() {
  if (!existsSync(envPath)) {
    return {};
  }

  return parseEnvFile(await readFile(envPath, "utf8"));
}

function runForgeDeploy(env) {
  const result = spawnSync(
    "forge",
    [
      "script",
      "script/Deploy.s.sol:DeployScript",
      "--rpc-url",
      "monad_testnet",
      "--broadcast",
    ],
    {
      cwd: contractsDir,
      env,
      encoding: "utf8",
      stdio: "inherit",
    },
  );

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`forge script failed with exit code ${result.status}`);
  }
}

async function updateFrontendEnv(address) {
  const key = "VITE_DELIVERA_ADDRESS";
  let content = "";

  if (existsSync(frontendEnvPath)) {
    content = await readFile(frontendEnvPath, "utf8");
  }

  const line = `${key}=${address}`;
  const pattern = new RegExp(`^${key}=.*$`, "m");

  if (pattern.test(content)) {
    content = content.replace(pattern, line);
  } else {
    const separator = content.length > 0 && !content.endsWith("\n") ? "\n" : "";
    content = `${content}${separator}${line}\n`;
  }

  await writeFile(frontendEnvPath, content);
}

async function main() {
  const fileEnv = await loadContractEnv();
  const monadTestnetRpcUrl =
    process.env.MONAD_TESTNET_RPC_URL ||
    fileEnv.MONAD_TESTNET_RPC_URL ||
    DEFAULT_TESTNET_RPC_URL;
  const privateKey = process.env.PRIVATE_KEY || fileEnv.PRIVATE_KEY;

  if (!privateKey) {
    throw new Error(
      "PRIVATE_KEY is required. Add it to contracts/.env or export it before deploy.",
    );
  }

  runForgeDeploy({
    ...process.env,
    MONAD_TESTNET_RPC_URL: monadTestnetRpcUrl,
    PRIVATE_KEY: privateKey,
  });

  const broadcast = JSON.parse(await readFile(broadcastPath, "utf8"));
  const deploymentRecord = buildDeploymentRecord(broadcast, {
    chainId: 10143,
    contractName: "Delivera",
    rpcUrl: monadTestnetRpcUrl,
  });

  await mkdir(path.dirname(deploymentPath), { recursive: true });
  await writeFile(deploymentPath, `${JSON.stringify(deploymentRecord, null, 2)}\n`);
  await updateFrontendEnv(deploymentRecord.address);

  console.log(`Delivera deployed to ${deploymentRecord.address}`);
  console.log(`Saved deployment to ${deploymentPath}`);
  console.log(`Updated ${frontendEnvPath}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
