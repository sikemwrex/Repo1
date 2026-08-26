# ChatGPT Computer Use VM

Authoritative technical repository for the laptop-first Hyper-V environment that will run ChatGPT Desktop and Computer Use inside an isolated Windows 11 VM.

## Governing principle

**Nothing important is merely configured. It is designed, reviewed, implemented, tested, evidenced, and made recoverable.**

Operationally:

**The host supervises. Hyper-V contains. The VM executes. ChatGPT operates inside the VM. The user retains ultimate control.**

## Target architecture

`Windows host -> Hyper-V -> isolated NAT -> CU-VM01 -> Windows 11 -> ChatGPT Desktop -> Computer Use`

## Authoritative lifecycle

`REQUIREMENTS -> ARCHITECTURE -> ARCHITECTURE REVIEW -> THREAT / FAILURE REVIEW -> CHANGE PLAN -> PRE-CHANGE VALIDATION -> IMPLEMENTATION -> AUTOMATED VALIDATION -> MANUAL ACCEPTANCE TEST -> EVIDENCE CAPTURE -> POST-CHANGE REVIEW -> GOLDEN BASELINE`

A successful command is never sufficient evidence that a configuration is correct.

## Review perspectives

Every material implementation is challenged from four perspectives:

1. **Build** — did the intended configuration execute?
2. **Audit** — what evidence proves it and what assumption could be wrong?
3. **Adversarial** — can the guest reach or control anything it should not?
4. **Recovery** — can the user recover safely if this breaks tomorrow?

## Repository structure

- `docs/` — architecture, threat model, network, recovery, change process and runbooks
- `adr/` — architecture decision records
- `config/` — declarative VM specification
- `scripts/host/` — host-readiness and host platform automation
- `scripts/hyperv/` — Hyper-V lifecycle automation
- `scripts/guest/` — Windows guest hardening/configuration
- `scripts/validation/` — read-only compliance/drift validation
- `tests/host-readiness/` — Gate A tests
- `tests/containment/` — host/guest boundary tests
- `tests/recovery/` — rollback/rebuild tests
- `evidence/` — evidence-handling rules; sanitized references only while public

## Five required project outcomes

The project is not complete until all five exist:

1. **Working environment** — `CU-VM01`
2. **Reproducible build** — PowerShell/configuration sufficient to rebuild
3. **Security baseline** — defined controls with effective tests
4. **Recovery capability** — tested checkpoints plus rebuild procedure
5. **Audit trail** — GitHub technical history plus Airtable governance/evidence state

## Security warning

This repository is currently **public**. Never commit passwords, tokens, API keys, BitLocker/recovery keys, credentials, browser data, VM exports, private logs, sensitive screenshots, VHD/VHDX files, or sensitive host/network evidence.

Repository privacy and GitHub Issues capability remain pre-build governance items. Secret scanning should be enabled where supported by repository/account settings.

## Current phase

**Architecture / pre-build governance.** No host changes are authorised by repository content alone. The next operational stage is Gate A: read-only host readiness assessment.
