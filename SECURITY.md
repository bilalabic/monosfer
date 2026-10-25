# Security and publication review

Review date: 2026-10-25. Source snapshot: `1139d8ff1c5ffe4fc0b040950c08d5d459f369c8`.

## Scope and findings

The review enumerated all 45 commits reachable from the original main branch, their recursive file trees, all current readable text files, and 237 additional historical text blobs. It checked environment files, likely credentials, long hexadecimal literals, credential-bearing connection strings, provider-token patterns, private-key headers, and configuration references. Binary images and non-main refs were outside this text review.

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

## History and public release

This update removes configuration from the current tree. It does **not** erase old commits, remote caches, other clones, or the original repository's fork network. Historical public configuration and the known Anvil key remain in that network.

The repository is a private fork. GitHub does not allow changing its visibility independently. For a public release, agree on ownership and license terms, then create a standalone repository from the sanitized working tree. If preserving the old history is required, perform a separate history-filtering review before pushing it.

Before publication, review all additional branches/tags, pull-request refs, Actions logs/artifacts, release assets, binary files, and any local configuration not available in this snapshot. These are not covered by the main-branch text review.

## Application security work still required

- Add server-side wallet signature verification with expiring, single-use nonces. Merely supplying a wallet address currently obtains a token.
- Restrict delivery details and recipient contact information to authorized participants; review currently public list/detail routes.
- Use cryptographically secure recipient codes with expiry, attempt limits, and appropriate storage.
- Verify contract transactions, receipts, and events independently before accepting payment-state changes.
- Review the Solidity code and obtain a dedicated audit before using real funds.

This cleanup prepares source configuration and documentation. It does not certify the application for production.

## Reporting

Do not post credentials or sensitive exploit details in a public issue. Contact a repository maintainer through an established private channel. If private vulnerability reporting is enabled for the eventual public repository, use its Security tab.

## Validation of this update

- Node.js 24.22.1; backend dependency installation and all 13 backend tests passed.
- Both deployment-record helper tests passed.
- Repaired missing optional dependency entries in the existing frontend lockfile; clean installation, Vue/TypeScript checking, and the Vite production build passed. Existing Vite devtools peer-dependency warnings remain.
- Verified that environment files and key-file patterns are ignored while the three environment examples remain trackable; local Markdown links resolve.
- Solidity tests were not run in this environment because Foundry was not installed. No contract deployment, wallet transaction, live database migration, or provider credential rotation was performed.
