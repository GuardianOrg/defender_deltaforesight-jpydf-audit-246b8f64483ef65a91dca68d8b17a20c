# Timelock Readback Template

Do not include private keys, seed phrases, raw RPC URLs, or Safe nonces.

| Check | Expected | Observed | Evidence |
| --- | --- | --- | --- |
| Timelock address | `DF_TIMELOCK` | `TBD` | `TBD` |
| `getMinDelay()` | `86400` | `TBD` | `TBD` |
| `PROPOSER_ROLE` holder | Admin multisig | `TBD` | `TBD` |
| `EXECUTOR_ROLE` holder | Admin multisig | `TBD` | `TBD` |
| `EXECUTOR_ROLE(address(0))` | `false` | `TBD` | `TBD` |
| `CANCELLER_ROLE` holder | Admin multisig | `TBD` | `TBD` |
| `CANCELLER_ROLE(Guardian)` | `false` | `TBD` | `TBD` |
| `TIMELOCK_ADMIN_ROLE(Timelock)` | `true` | `TBD` | `TBD` |
| `TIMELOCK_ADMIN_ROLE(deployer)` | `false` | `TBD` | `TBD` |
| `TIMELOCK_ADMIN_ROLE(Admin multisig)` | `false` | `TBD` | `TBD` |

Mainnet delivery is No-Go if any observed value differs from the expected value.
