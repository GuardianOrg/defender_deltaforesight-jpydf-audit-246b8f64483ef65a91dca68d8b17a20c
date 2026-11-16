# Final Production Cleanup Delta

This directory preserves the exact two-file cleanup that removed the temporary
pilot overlay before the final production source freeze. It makes the cleanup
reviewable even if audit PR history is later squashed or shallow-cloned.

| Item | Identity |
| --- | --- |
| Pre-cleanup audit commit | `5d08fe09c0a058e2c2444077c73a191d0454ddcb` |
| Pre-cleanup `source-snapshot/contracts/src` tree | `477779ebce15897f471e7cf869d6a2caf40a1b79` |
| Final source audit commit | `2725216e0407a0ef4599e359a04094ae5f322624` |
| Final `source-snapshot/contracts/src` tree | `84476d9086e89580c58918b203f4142ecd839765` |
| Patch | [`production-cleanup.patch`](./production-cleanup.patch) |
| Patch SHA-256 | `c0f3b9f7154985d8031f46d89bdbd87a14d53929bbabba3c2637ca3331157fcb` |

Changed blobs:

| Path | Pre-cleanup blob | Final blob | Result |
| --- | --- | --- | --- |
| `ActivePool.sol` | `da3f2e7d1a40f26188a3496d2477cc56f182f0b4` | `4a97ea9f17d9c402c340863a333719e4e4c3d421` | Both yield calculations use `SP_YIELD_SPLIT` directly; final blob equals the Chain Defenders base. |
| `Dependencies/Constants.sol` | `292e908c7562854742443d9cc487d32c49c73357` | `a1b6f32ba0b27aba3d2ed4151f0ebb33a9541501` | Four pilot-overlay symbols are physically absent; the surviving base-to-final change is the production `MIN_DEBT`. |

Reproduce the patch hash from a full audit-repository history:

```sh
git diff --no-ext-diff --unified=5 \
  5d08fe09c0a058e2c2444077c73a191d0454ddcb \
  2725216e0407a0ef4599e359a04094ae5f322624 -- \
  source-snapshot/contracts/src/ActivePool.sol \
  source-snapshot/contracts/src/Dependencies/Constants.sol \
  | shasum -a 256
```

The priced `d4122704` to final differential contains only surviving endpoint
hunks. Because ActivePool returns to its base blob, the cleanup is represented
there by absence. This pinned patch records the otherwise-collapsed intermediate
removal delta without pricing removed code as final production Solidity.
