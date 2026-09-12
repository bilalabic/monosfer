#!/usr/bin/env node
/**
 * Builds the consumer-facing artifact bundle for the frontend and backend.
 *
 * Sources of truth, in order:
 *   1. contracts/deployments/<chainId>.json  — addresses, committed and reviewable
 *   2. contracts/out/<File>.sol/<Name>.json  — ABIs, produced by `forge build`
 *
 * Output (contracts/exports/), all generated, all committed:
 *   index.js     ESM: chain metadata, addresses, ABIs, lookup helpers
 *   index.d.ts   type declarations, so the TypeScript frontend gets checking and
 *                the JavaScript backend still gets editor completion
 *   abis/*.json  one ABI per contract, for tools that want the raw file
 *
 * Why generated rather than hand-written: addresses used to be copied by hand
 * into frontend/app/config/chain.ts, frontend/.env and the contracts README, and
 * those three copies had already drifted apart. One generator, one manifest, no
 * copies.
 *
 * Event topics and custom-error selectors are deliberately NOT precomputed here.
 * viem, wagmi and ethers all derive them from the ABI, and a hand-rolled keccak
 * in a build script is a liability with no upside.
 *
 * Usage:
 *   node tools/build-exports.mjs            # write exports
 *   node tools/build-exports.mjs --check    # fail if exports are stale
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const deploymentsDir = join(root, "deployments");
const outDir = join(root, "out");
const exportsDir = join(root, "exports");

const checkOnly = process.argv.includes("--check");

/** Contracts a consumer talks to, and the source file their ABI comes from. */
const EXPORTED = {
  // V1
  ProtocolAccessManager: "ProtocolAccessManager.sol",
  ProtocolConfig: "ProtocolConfig.sol",
  SettlementVault: "SettlementVault.sol",
  CourierRegistry: "CourierRegistry.sol",
  DeliveryHub: "DeliveryHub.sol",
  // V1 dispute layer (P4). The frontend needs the court for appeal status and
  // the backend needs the committee to coordinate a fallback (sec. 31).
  DisputeCourt: "DisputeCourt.sol",
  JurorPool: "JurorPool.sol",
  FallbackCommittee: "FallbackCommittee.sol",
  // Legacy: frozen under decision D1, retired at P5.3. Exported so the existing
  // app keeps working until the cut-over.
  Delivera: "Delivera.sol",
  DeliveryEscrow: "DeliveryEscrow.sol",
  Leaderboard: "Leaderboard.sol",
  ReputationBadge: "ReputationBadge.sol",
  RewardDistributor: "RewardDistributor.sol",
  MCRYToken: "MCRYToken.sol",
};

function loadAbi(name) {
  const file = join(outDir, EXPORTED[name], `${name}.json`);
  if (!existsSync(file)) {
    throw new Error(`ABI missing for ${name} at ${file}. Run \`forge build\` first.`);
  }
  return JSON.parse(readFileSync(file, "utf8")).abi;
}

function loadDeployments() {
  if (!existsSync(deploymentsDir)) return [];
  return readdirSync(deploymentsDir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(join(deploymentsDir, f), "utf8")))
    .sort((a, b) => a.chainId - b.chainId);
}

function render(deployments, abis) {
  const names = Object.keys(EXPORTED);
  const chains = Object.fromEntries(
    deployments.map((d) => [
      d.chainId,
      { chainId: d.chainId, name: d.name, rpcUrl: d.rpcUrl, explorer: d.explorer, contracts: d.contracts },
    ]),
  );

  const js = `// GENERATED FILE - DO NOT EDIT BY HAND.
// Produced by contracts/tools/build-exports.mjs from contracts/deployments/*.json
// and the \`forge build\` output. Regenerate with: npm run contracts:exports
//
// Hand-editing this file reintroduces exactly the drift it exists to prevent.

export const CHAINS = ${JSON.stringify(chains, null, 2)};

export const ABIS = {
${names.map((n) => `  ${n}: ${JSON.stringify(abis[n])},`).join("\n")}
};

/**
 * Addresses for one chain.
 * Throws instead of returning undefined: a missing deployment should fail loudly
 * at startup, not silently produce calls to the zero address.
 */
export function getContracts(chainId) {
  const chain = CHAINS[chainId];
  if (!chain) {
    throw new Error(\`No MONOSFER deployment recorded for chainId \${chainId}\`);
  }
  return chain.contracts;
}

/** Address of one contract on one chain. */
export function getAddress(chainId, name) {
  const entry = getContracts(chainId)[name];
  if (!entry) {
    throw new Error(\`\${name} is not deployed on chainId \${chainId}\`);
  }
  return entry.address;
}

/** Chain metadata (rpc, explorer, name) without the address book. */
export function getChain(chainId) {
  const chain = CHAINS[chainId];
  if (!chain) {
    throw new Error(\`Unknown chainId \${chainId}\`);
  }
  const { contracts, ...meta } = chain;
  return meta;
}

/** Explorer URL for an address on a chain. */
export function explorerAddressUrl(chainId, address) {
  return \`\${getChain(chainId).explorer}/address/\${address}\`;
}

/** Explorer URL for a transaction on a chain. */
export function explorerTxUrl(chainId, txHash) {
  return \`\${getChain(chainId).explorer}/tx/\${txHash}\`;
}
`;

  const dts = `// GENERATED FILE - DO NOT EDIT BY HAND.
export type ContractName =
${names.map((n) => `  | "${n}"`).join("\n")};

export interface DeployedContract {
  address: \`0x\${string}\`;
  block?: number;
  txHash?: \`0x\${string}\`;
  /** True for contracts frozen under decision D1 and retired at P5.3. */
  legacy?: boolean;
}

export interface ChainMeta {
  chainId: number;
  name: string;
  rpcUrl: string;
  explorer: string;
}

export interface ChainDeployment extends ChainMeta {
  contracts: Partial<Record<ContractName, DeployedContract>>;
}

export declare const CHAINS: Record<number, ChainDeployment>;
export declare const ABIS: Record<ContractName, readonly unknown[]>;

export declare function getContracts(chainId: number): Partial<Record<ContractName, DeployedContract>>;
export declare function getAddress(chainId: number, name: ContractName): \`0x\${string}\`;
export declare function getChain(chainId: number): ChainMeta;
export declare function explorerAddressUrl(chainId: number, address: string): string;
export declare function explorerTxUrl(chainId: number, txHash: string): string;
`;

  return { js, dts };
}

function main() {
  const deployments = loadDeployments();
  const names = Object.keys(EXPORTED);

  const abis = {};
  for (const name of names) abis[name] = loadAbi(name);

  const { js, dts } = render(deployments, abis);
  // Marks the bundle as ESM so Node resolves it without a reparse warning and
  // bundlers pick up the type declarations.
  const pkg = `${JSON.stringify(
    {
      name: "@monosfer/contracts",
      version: "0.1.0",
      private: true,
      type: "module",
      main: "index.js",
      types: "index.d.ts",
      exports: { ".": { types: "./index.d.ts", default: "./index.js" }, "./abis/*": "./abis/*" },
    },
    null,
    2,
  )}
`;

  const files = new Map([
    ["package.json", pkg],
    ["index.js", js],
    ["index.d.ts", dts],
    ...names.map((n) => [join("abis", `${n}.json`), `${JSON.stringify(abis[n], null, 2)}\n`]),
  ]);

  if (checkOnly) {
    const stale = [];
    for (const [file, expected] of files) {
      const path = join(exportsDir, file);
      if (!existsSync(path) || readFileSync(path, "utf8") !== expected) stale.push(file);
    }
    if (stale.length > 0) {
      console.error("Exports are stale. Run: npm run contracts:exports");
      for (const f of stale) console.error(`  - ${f}`);
      process.exit(1);
    }
    console.log(`exports up to date (${names.length} contracts, ${deployments.length} chain(s))`);
    return;
  }

  rmSync(exportsDir, { recursive: true, force: true });
  mkdirSync(join(exportsDir, "abis"), { recursive: true });
  for (const [file, content] of files) writeFileSync(join(exportsDir, file), content);

  console.log(`exports written: ${names.length} contracts, ${deployments.length} chain(s)`);
  for (const d of deployments) {
    console.log(`  chain ${d.chainId} (${d.name}): ${Object.keys(d.contracts).length} addresses`);
  }
}

main();
