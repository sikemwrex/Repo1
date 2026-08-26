# ChatGPT Computer Use VM

Authoritative repository for the laptop-first Hyper-V environment that will run ChatGPT Desktop and Computer Use inside an isolated Windows 11 VM.

## Governing principle

**The host supervises. Hyper-V contains. The VM executes. ChatGPT operates inside the VM. The user retains ultimate control.**

## Target architecture

`Windows host -> Hyper-V -> isolated NAT -> CU-VM01 -> Windows 11 -> ChatGPT Desktop -> Computer Use`

## Engineering standard

Important changes follow: **Proposed -> Reviewed -> Implemented -> Validated -> Accepted**.

No control is considered complete solely because a command succeeded. Security-sensitive changes require rollback planning, state validation, evidence capture, and post-change review.

## Repository intent

- `docs/` architecture, threat model, recovery and runbooks
- `adr/` architecture decision records
- `config/` declarative VM specifications
- `scripts/` host, Hyper-V, guest and validation automation
- `tests/` acceptance and containment tests
- `evidence/` evidence-handling guidance only; do not commit secrets or sensitive guest data

## Security warning

This repository is public. Never commit passwords, tokens, API keys, BitLocker recovery keys, browser data, VM exports, credentials, private logs, or sensitive screenshots.

## Current phase

**Architecture / pre-build governance.** No host changes are authorised by this repository alone.
