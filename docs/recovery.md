# Recovery Standard

## Objective
A failed configuration, damaged guest, or unsafe automation outcome must be recoverable without depending on undocumented knowledge.

## Recovery layers
1. **Configuration recovery** — rebuild from GitHub-controlled architecture, configuration and scripts.
2. **Checkpoint rollback** — return `CU-VM01` to a known pre-change or golden state.
3. **VM export/backup** — recover when local VM storage or checkpoints are unusable.

## Controlled checkpoints
- `00-WIN11-CLEAN`
- `01-WIN11-HARDENED`
- `02-CHATGPT-INSTALLED`
- `03-COMPUTER-USE-VERIFIED`

`03-COMPUTER-USE-VERIFIED` is created only after mandatory functional, containment, privilege, network and recovery tests pass.

## Change rollback requirement
Every R2-R4 change must document:
- current state
- intended state
- rollback trigger
- exact rollback action
- validation that rollback succeeded

## Recovery test
A recovery claim is not accepted until a controlled state change is made, rollback is executed, and the expected prior state is independently verified.

## Checkpoint discipline
Checkpoints are not backups. Avoid long checkpoint chains; consolidate temporary checkpoints after accepted changes.

## Rebuild objective
A competent administrator should be able to rebuild the environment from source-controlled documentation and configuration without requiring the original VM image.
