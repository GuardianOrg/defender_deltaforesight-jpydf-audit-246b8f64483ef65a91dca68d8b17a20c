# TroveNFT / MetadataNFT Differential Review (2026-06-14, revised 2026-06-15)

The scope covers the `TroveNFT` collection metadata, the `MetadataNFT` tokenURI metadata, the related spec / verification ledger, and `troveNFT.t.sol`.

## Findings

### 2026-06-15 conclusion: the core-side display-text change is withdrawn

The `TroveNFT` collection `name` / `symbol` and the `MetadataNFT` JSON `name` / `description` inherit the base's `"Liquity V2"` / `"LV2_"` / `"(BOLD)"` notation. As of 2026-06-14 a plan to rename them to JPYdf for the product-facing display was considered, but it would change upstream-derived files under `contracts/src`, which violates the core immutability guard.

The criterion for protocol soundness is the core immutability guard, so the display-text change to the core source is not adopted. On surfaces where a JPYdf display is required, alias it in outer layers such as the frontend / indexer / marketplace metadata adapter.

Actions:

- Reverted the `TroveNFT` / `MetadataNFT` source to the upstream notation.
- Removed `CORE-MOD-006` from the Core spec / verification ledger.
- Marked `CORE-TN-TBD-002` as resolved with "the core keeps the upstream notation, and the product alias is handled in outer layers".
- `troveNFT.t.sol` verifies that the collection name/symbol and the tokenURI description keep the upstream notation.

## Residual Risks / Operational Assumptions

- Because the core metadata contains `"Liquity V2"` / `"(BOLD)"`, if the product UI displays the tokenURI as-is it diverges from the JPYdf product display. Make the alias policy explicit on the surfaces that need it.
- Because `TroveNFT.name()` / `symbol()` fix the collToken `name()` / `symbol()` at constructor time, deploying a branch before the dToken `setTokenInfo` permanently fixes the placeholder name. This ordering risk remains undecided as `CORE-TN-TBD-001`.
- Going forward, changing the NFT metadata on the protocol source side first requires an extension of the core immutability guard exception, and must not be introduced as a standalone source change.

## Verification

- `bash .github/scripts/check-core-immutability.sh origin/base HEAD`
- `forge test --match-path test/troveNFT.t.sol`
