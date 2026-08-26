# Runbooks

Runbooks describe repeatable operational procedures after the architecture decision is accepted.

Required runbooks for the MVP:
1. `host-readiness.md` — read-only Gate A checks.
2. `build-cu-vm01.md` — Hyper-V/VM creation sequence.
3. `guest-hardening.md` — Windows guest baseline.
4. `validate-containment.md` — host/guest boundary tests.
5. `restore-golden-baseline.md` — controlled rollback procedure.

## Runbook quality rule
Each runbook must contain prerequisites, risk class, pre-change checks, commands/actions, expected results, rollback, validation, evidence requirements, and stop conditions.

A successful command is not proof of a successful change. Every runbook ends with state verification.
