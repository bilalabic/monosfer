# Security review

Review date: 2026-10-25. Scope: the source tree on `main` and the full commit history of both branches (`main` and `Monosfer-V2`).

## Scope and findings

The first review enumerated the 45 commits reachable from `main`, their recursive file trees, all current readable text files, and 237 additional historical text blobs. It checked environment files, likely credentials, long hexadecimal literals, credential-bearing connection strings, provider-token patterns, private-key headers, and configuration references.

A second, pattern-based review covered the diffs of all 140 commits on both branches. It looked for cloud and provider tokens, private-key headers, JWTs, connection strings with credentials for non-local hosts, RPC URLs with embedded API keys, and secret-like assignments. None of these were found. The only matches were non-sensitive: the publicly documented Anvil development key, local-only development passwords for `127.0.0.1` services, and the demo RPC key shipped inside the vendored `forge-std` library. Binary files were not inspected.

| Finding | Assessment | Change |
| --- | --- | --- |
| Tracked `frontend/.env` | Public API endpoint, testnet network values, and a public contract address; no privileged credential identified in the file or its historical variants | Removed from the current tracked tree; replaced with a local-development `.env.example` |
| Literal key in `contracts/.env.example` | Known, publicly documented Anvil development key; unsafe to reuse for real funds | Removed the literal; private-key fields are blank |
| Incomplete backend example | Database and JWT settings used by the code were missing | Added all server settings and instructions to generate a local JWT secret |
| Hardcoded modular contract addresses | Public identifiers rather than secrets; tied to a particular deployment | Moved to optional `VITE_*` configuration |
| Automatic SSH workflow | A copied workflow should not deploy without an explicit setup decision | Added the `ENABLE_PRODUCTION_DEPLOY` opt-in gate |

The reviewed text did not reveal a production credential requiring confirmed rotation. Hashes, public contract addresses, local MongoDB URLs without credentials, and vendored Foundry fixtures were distinguished from privileged secrets. Pattern-based review cannot prove that every possible secret is absent.

## Handling local configuration

- Copy the examples to ignored `.env` files and supply values locally.
- Generate a unique JWT secret per environment. Changing an existing secret invalidates signed sessions.
- Use disposable testnet wallets. Never fund a publicly known development key with real assets.
- Treat every `VITE_*` value as public: Vite embeds it into browser assets.
- Keep SSH credentials in Actions secrets and database credentials on the server.
- Never attach real `.env` files, database dumps, seed phrases, or private keys to issues or pull requests.

No real service credential was generated, revoked, or rotated by this repository cleanup. Those operations require the corresponding provider account. If any previously shared credential was real, revoke/replace it at the provider; deleting a file or rewriting Git history does not revoke a key.

## History

This repository contains the full commit history of both branches. Historical commits still include earlier configuration files, such as a tracked `frontend/.env` (public endpoints and contract addresses only) and the known Anvil development key. The latter is a public test key and must never hold real funds. The `Monosfer-V2` branch still tracks that `frontend/.env`; none of its values are privileged credentials.

Contributor email addresses in commit metadata use GitHub noreply addresses. Because of that, commit hashes differ from those in any older clone of the original project.

The review did not cover Actions logs and artifacts, release assets, or any local configuration that is not committed. Deleting a file or rewriting Git history does not revoke a key, so replace any credential that was ever real.

## Application security work still required

- Add server-side wallet signature verification with expiring, single-use nonces. Merely supplying a wallet address currently obtains a token.
- Restrict delivery details and recipient contact information to authorized participants; review currently public list/detail routes.
- Use cryptographically secure recipient codes with expiry, attempt limits, and appropriate storage.
- Verify contract transactions, receipts, and events independently before accepting payment-state changes.
- Review the Solidity code and obtain a dedicated audit before using real funds.

This cleanup prepares source configuration and documentation. It does not certify the application for production.

## Reporting

Do not post credentials or sensitive exploit details in a public issue. Contact a repository maintainer through an established private channel. If private vulnerability reporting is enabled for this repository, use its Security tab.

## Validation of this update

- Node.js 24.22.1; backend dependency installation and all 13 backend tests passed.
- Both deployment-record helper tests passed.
- Repaired missing optional dependency entries in the existing frontend lockfile; clean installation, Vue/TypeScript checking, and the Vite production build passed. Existing Vite devtools peer-dependency warnings remain.
- Verified that environment files and key-file patterns are ignored while the three environment examples remain trackable; local Markdown links resolve.
- Solidity tests were not run in this environment because Foundry was not installed. No contract deployment, wallet transaction, live database migration, or provider credential rotation was performed.
