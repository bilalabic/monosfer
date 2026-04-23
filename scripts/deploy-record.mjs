export function parseEnvFile(content) {
  const values = {};

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();

    if (!line || line.startsWith("#")) {
      continue;
    }

    const separatorIndex = line.indexOf("=");

    if (separatorIndex === -1) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    let value = line.slice(separatorIndex + 1).trim();

    if (
      (value.startsWith("\"") && value.endsWith("\"")) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    values[key] = value;
  }

  return values;
}

export function buildDeploymentRecord(broadcast, options) {
  const transaction = broadcast.transactions?.find((candidate) => {
    return (
      candidate.contractName === options.contractName &&
      candidate.contractAddress
    );
  });

  if (!transaction) {
    throw new Error(`No deployment transaction found for ${options.contractName}`);
  }

  const matchingReceipt = broadcast.receipts?.find((receipt) => {
    return (
      receipt.contractAddress?.toLowerCase() ===
      transaction.contractAddress.toLowerCase()
    );
  });

  const transactionHash =
    transaction.hash || matchingReceipt?.transactionHash || matchingReceipt?.hash;

  if (!transactionHash) {
    throw new Error(`No transaction hash found for ${options.contractName}`);
  }

  return {
    contractName: options.contractName,
    address: transaction.contractAddress,
    chainId: options.chainId,
    rpcUrl: options.rpcUrl,
    transactionHash,
  };
}
