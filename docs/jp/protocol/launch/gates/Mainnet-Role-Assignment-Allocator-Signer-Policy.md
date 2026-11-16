# Mainnet Role Assignment Allocator Signer Policy

## 0. メタ情報

| 項目             | 値                                                                                                                                                                                                                                                                                                                   |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status           | Active                                                                                                                                                                                                                                                                                                               |
| Date             | 2026-07-18                                                                                                                                                                                                                                                                                                           |
| Domain           | Protocol Governance |
| Lifecycle        | Launch |
| Artifact Type    | Policy |
| Decision Authority | Protocol Governance |
| Maintainer       | DeltaForesight (Contributor) |
| 対象             | `DF_ALLOCATOR` / Vault `ALLOCATOR_ROLE` の Day-1 holder 形態                                                                                                                                                                                                                                                         |
| 決定             | Day-1 は **Allocator Safe / manual operation** で開始し、hardened bot signer への移管は別 activation gate とする。                                                                                                                                    |
| 関連ドキュメント | [Protocol Role Holder Manifest](../manifests/Mainnet-Protocol-Role-Holder-Manifest.md) / [Role Holder Separation Policy](./Mainnet-Role-Holder-Separation-Policy.md) / [Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md) / [Governance](../../../Governance.md) |

---

## 1. 結論

`DF_ALLOCATOR` は persistent privileged holder ではあるが、任意宛先へ資金を抜く権限ではない。Vault の `allocate()` / `transferYieldToTreasury()` は送金経路が登録 Strategy または `treasury` に固定され、`setAllocatorConfig()` は GOV のみが実行できる。

この決定では、Day-1 の signer roster / bot custody を確定する前に automation を有効化しない。physical holder address は [Protocol Role Holder Manifest](../../../protocol/launch/manifests/Mainnet-Protocol-Role-Holder-Manifest.md)、owner / threshold / signer 構成は [Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md) を正本とする。

hardened bot signer は将来の移管先として残す。**未保護の EOA を production privileged holder として直接置くことは許容しない**。秘密鍵を人が直接扱わない運用基盤、操作監査、即時停止、後続 revoke / replacement が揃い、別 activation package が承認された場合に限り Timelock が `ALLOCATOR_ROLE` を移管する。

## 2. 判断軸

Allocator holder の形は次の 2 点で決まる。

| 軸           | 評価                                                                                                                |
| ------------ | ------------------------------------------------------------------------------------------------------------------- |
| Blast radius | 任意宛先送金はできず、主な被害は buffer を Strategy 側へ寄せる一時的な流動性 griefing。                             |
| 運用頻度     | `allocate()` / `transferYieldToTreasury()` は繰り返し実行されうるため、毎回 multisig 署名に寄せると運用が重くなる。 |

このため automation は将来的に合理的だが、Day-1 の手動運用負荷は bot activation gate を安全に後続へ分離するための受容コストとする。

## 3. Code Facts

照合対象は `contracts/src/CollateralVault.sol`。本節の行番号は設計時点の operational pointer であり、audit freeze の正本ではない。freeze package では対象 commit の source から同じ function / guard / role fact を再 grep し、line-specific evidence は launch evidence package に残す。

| Fact                                                                   | 参照箇所                  | 意味                                                  |
| ---------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------- |
| `ALLOCATOR_ROLE` constant                                              | role constant             | Allocator role identity。                             |
| `allocate()` is `onlyRole(ALLOCATOR_ROLE)` + `whenNotPausedAllocation` | `allocate()` guard        | Guardian pause で allocator activity を止められる。   |
| `allocatorCooldown` gate                                               | `allocate()` guard        | Frequency control。                                   |
| excess is capped by `allocateMaxMove`                                  | allocation size logic     | Per-move size control。                               |
| default `allocateMaxMove = type(uint256).max`                          | initializer default       | launch 前に上書きしない限り deploy default は危険。   |
| `_allocateToStrategies()` uses registered enabled strategies           | strategy allocation loop  | Destination set は GOV strategy registry が支配する。 |
| `setAllocatorConfig()` is `onlyRole(GOV_ROLE)`                         | config setter guard       | Allocator は自分の cap / cooldown を緩められない。    |
| `pauseAllocation()` is `onlyRole(GUARDIAN_ROLE)`                       | pause function guard      | 即時 kill-switch。                                    |

## 4. Blast Radius

| Area         | allocator signer が侵害された場合                                                                                                | できないこと                                                                   |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Asset theft  | 任意 recipient は選べず、資金は registered Strategy または `treasury` にしか動かない。                                           | Vault assets を attacker-controlled address に送ること。                       |
| Availability | `allocateMaxMove` / cooldown の範囲で excess buffer を Strategy 側へ寄せ、一時的に instant redeem / claim liquidity を下げうる。 | backing を直接毀損すること、または strategy registry を変更すること。          |
| Recovery     | Guardian が `pauseAllocation` を呼べる。Timelock が `ALLOCATOR_ROLE` を revoke / replace できる。                                | Allocator が自分で unpause すること、または自分に追加 role を grant すること。 |

このため、Allocator は GOV、WRITEOFF、Guardian、Treasury、Bridge admin、PriceFeed owner とは materially different な role である。後者は Safe / Timelock / contract holder のままとする。

## 5. Future Bot Activation Controls

`DF_ALLOCATOR` を hardened bot signer にできるのは、以下の control がすべて true の場合に限る。

| Control        | Requirement                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| Key custody    | KMS / HSM / managed custody。operator が plaintext key を扱わない。                             |
| IAM            | 承認済み function set への署名に必要な最小権限だけを付与する。                                  |
| Audit logs     | すべての signature と caller identity を記録・保持する。                                        |
| Balance cap    | Gas / funding balance を文書化された loss budget に制限する。                                   |
| Function scope | Bot は allocator operations と必要な strategy push / withdrawal operations だけを submit する。 |
| On-chain cap   | `allocateMaxMove` は `type(uint256).max` ではなく、正の bounded value にする。                  |
| Cooldown       | risk owner が一時 exception を明示承認しない限り、`allocatorCooldown` は正値にする。            |
| Pause path     | Guardian `pauseAllocation()` が live で監視されている。                                         |
| Rotation       | Key rotation と Timelock-based revoke / replacement を文書化する。                              |
| Monitoring     | 予期しない allocation size、cadence、strategy target、revert pattern を ops に alert する。     |

いずれかの item が欠ける場合は現在の holder を維持し、allocator bot activation を No-Go とする。

## 6. Alternatives

| 形態                     | Role holder | Automation                  | 侵害時の結果                                                        | 位置づけ                             |
| ------------------------ | ----------- | --------------------------- | ------------------------------------------------------------------- | ------------------------------------ |
| Full Safe                | Safe        | Manual                      | holder control は強いが、運用負荷が高い。                           | **Day-1 採用。**                     |
| Safe with module / guard | Safe        | Automated within allow-list | Defense-in-depth。Safe が owner plane を保持する。                  | Upgrade path.                        |
| Hardened bot signer      | Bot signer  | Automated                   | 任意 asset theft はできず、griefing は cap で bounded。             | 別 activation gate 後の候補。        |
| 未保護 EOA               | EOA         | Automated                   | operational hardening なしに key が allocator role を直接支配する。 | production では不可。                |

## 7. Changeability

`CollateralVault` は `AccessControlUpgradeable` を使い、`ALLOCATOR_ROLE` の grant / revoke は handover 後に Timelock が保持する `DEFAULT_ADMIN_ROLE` で制御される。したがって:

- Safe holder は後から Safe + module または approved hardened bot signer に置き換えられる。
- compromised or stale signer は Guardian が即時 pause し、Timelock 経由で revoke できる。
- role migration に protocol redeploy は不要。
- Vault 側から role を enumerate できないため、launch evidence では old allocator が revoke 済みであることを確認する。

## 8. Launch Gate

public launch 前に、evidence package は次を示す必要がある。

1. `DF_ALLOCATOR`がProtocol Role Holder Manifestの承認済みphysical holder addressと一致すること。
2. owner / threshold / signer 構成が Safe Threshold Policy と一致すること。
3. Allocator Safe と Launch / Ops finance Safe が別 contract address であること。
4. `allocateMaxMove` と `allocatorCooldown` の readback。
5. Guardian `pauseAllocation()` holder readiness。
6. Timelock revoke / replacement procedure。
7. hardened bot signer に `ALLOCATOR_ROLE` が付与されておらず、bot activation が別 gate に残っていること。
