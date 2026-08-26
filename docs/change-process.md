# Change Process

## Authoritative lifecycle

`REQUIREMENTS -> ARCHITECTURE -> ARCHITECTURE REVIEW -> THREAT / FAILURE REVIEW -> CHANGE PLAN -> PRE-CHANGE VALIDATION -> IMPLEMENTATION -> AUTOMATED VALIDATION -> MANUAL ACCEPTANCE TEST -> EVIDENCE CAPTURE -> POST-CHANGE REVIEW -> GOLDEN BASELINE`

No material stage is skipped merely because an implementation command completed successfully.

## Change states
General:
`PROPOSED -> REVIEWED -> IMPLEMENTED -> VALIDATED -> ACCEPTED`

Security-sensitive:
`PROPOSED -> RISK REVIEWED -> IMPLEMENTED -> TESTED -> EVIDENCE CAPTURED -> ACCEPTED`

Never jump directly from PROPOSED to ACCEPTED.

## Independent verification perspectives
After implementation, deliberately review from four perspectives:
1. **Build** — did the intended change execute and produce the declared state?
2. **Audit** — what evidence proves the control and what assumption could be false?
3. **Adversarial** — can the guest reach, control or inherit authority it should not?
4. **Recovery** — can the user safely recover if the change fails tomorrow?

## Risk classification
| Class | Typical action | Required behaviour |
| --- | --- | --- |
| R0 | read system information | execute directly; record result |
| R1 | create report/project metadata | execute and verify |
| R2 | create VM/switch/project resource | pre-check, rollback plan, execute, verify |
| R3 | firewall/network/security change | risk review, rollback, execute, automated + manual validation |
| R4 | destructive/credential/host-wide change | explicit user approval, bounded change, rollback, independent validation |

## GitHub workflow
Preferred once repository settings support it:
`Issue -> Branch -> Change -> Validation -> Pull Request -> Review -> Merge -> Deploy -> Post-deployment validation`

If Issues are unavailable, the gate/change document and Airtable Change Log provide the tracking record; branch/PR review should still be used for technical changes where practical.

## PowerShell quality gates
Before a script becomes baseline:
`Syntax -> PSScriptAnalyzer -> read-only/dry-run checks where possible -> controlled execution -> state validation -> repeat-execution/idempotence test`

Expected second-run behaviour is convergence or `Already compliant`, not duplicate configuration.
