# Host Scripts

Host-side scripts are limited to approved Hyper-V/platform operations.

## Rules
- default to read-only discovery first
- never disable Defender, firewall, BitLocker, Secure Boot or unrelated services to make the VM work
- identify project-owned objects before modifying/removing them
- R3/R4 actions require explicit rollback and user approval
- emit machine-readable results where practical
- reruns should be safe and idempotent

Gate A host-readiness scripts belong here once developed in Work mode.
