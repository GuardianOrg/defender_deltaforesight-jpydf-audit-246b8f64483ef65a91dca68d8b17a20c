# Mainnet Fork Evidence Template

Do not include private keys, credentialed RPC URLs, or unredacted provider
tokens in this file.

## Run Metadata

| Item | Value |
| --- | --- |
| Source commit | `TBD` |
| Fork block | `TBD` |
| RPC provider label | `TBD` |
| Redacted RPC URL | `https://example.invalid/[redacted]` |
| Foundry version | `TBD` |
| Solidity version | `TBD` |
| Deployer address | `TBD` |
| Bridge admin | `TBD` |

## Required Artifacts

- [ ] `evidence-summary.txt`
- [ ] `01-external-preflight.log`
- [ ] `02-deploy-fork.log`
- [ ] `deployment-manifest.json`
- [ ] `deployment-manifest.sha256`
- [ ] `03-manifest-preflight.log`
- [ ] `04-app-env-generation.log`
- [ ] `05-prepare-handover.log`
- [ ] `06-verify-pending-handover.log`
- [ ] `morpho-vault-freeze.json`, if Morpho is an adopted strategy venue in
      the deployment evidence scope
- [ ] `pil-activation-manifest.json`, only if PIL deployment evidence is in
      scope

## Redaction Confirmation

- [ ] Credentialed RPC URLs removed or replaced with redacted URL.
- [ ] API keys removed.
- [ ] Private keys and mnemonic material absent.
- [ ] Local filesystem paths removed where not relevant to reproduction.
- [ ] Machine-specific account names removed where not relevant.
