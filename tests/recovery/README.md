# Recovery Tests

## Mandatory recovery test
1. Start from a known checkpointed guest state.
2. Create a uniquely identifiable test artifact or configuration change.
3. Restore the selected checkpoint.
4. Verify the post-checkpoint artifact/change is gone and the expected earlier state is restored.
5. Confirm host operation remained unaffected.

## Acceptance
Recovery is PASS only when the observed restored state matches the expected state. The existence of a checkpoint alone is not evidence of recoverability.

## Rebuild test
Before final project closure, documentation and source-controlled configuration must be reviewed for whether another competent administrator could reconstruct `CU-VM01` without undocumented knowledge.
