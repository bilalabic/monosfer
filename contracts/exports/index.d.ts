// GENERATED FILE - DO NOT EDIT BY HAND.
export type ContractName =
  | "ProtocolAccessManager"
  | "ProtocolConfig"
  | "SettlementVault"
  | "CourierRegistry"
  | "DeliveryHub"
  | "Delivera"
  | "DeliveryEscrow"
  | "Leaderboard"
  | "ReputationBadge"
  | "RewardDistributor"
  | "MCRYToken";

export interface DeployedContract {
  address: `0x${string}`;
  block?: number;
  txHash?: `0x${string}`;
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
export declare function getAddress(chainId: number, name: ContractName): `0x${string}`;
export declare function getChain(chainId: number): ChainMeta;
export declare function explorerAddressUrl(chainId: number, address: string): string;
export declare function explorerTxUrl(chainId: number, txHash: string): string;
