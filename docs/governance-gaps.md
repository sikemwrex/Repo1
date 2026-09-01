# Repository Governance Gaps

These items are explicit pre-build governance findings. They do not prevent architecture work, but they must not be silently treated as resolved.

## GOV-001 — Repository is public
**Status:** Open

Generic architecture and sanitized scripts are acceptable. Raw host/network evidence, credentials, private logs, VM exports and sensitive screenshots are prohibited.

**Preferred resolution:** use a private project repository before operational evidence is retained in GitHub.

## GOV-002 — Repository is a fork with generic name `Repo1`
**Status:** Open

A dedicated repository named for the project is preferable for long-term provenance, ownership clarity and migration.

**Preferred resolution:** migrate the reviewed baseline to a dedicated `chatgpt-computer-use-vm` repository when repository-management capability is available.

## GOV-003 — GitHub Issues are disabled
**Status:** Open

Issue-first change tracking cannot currently be enforced. Until resolved, use GitHub branches/PRs plus Airtable Change Log and gate documents.

## GOV-004 — Repository rulesets / branch protection
**Status:** Open — confirmed unenforced

GitHub currently reports `main` as `protected: false`, with branch protection disabled and required status-check enforcement off. The repository rulesets endpoint also returns no configured rulesets.

This means PowerShell Quality is evidence, not an authorization boundary. Direct writes to `main` are not technically blocked by repository policy.

**Preferred resolution:** require PR-based changes and the PowerShell Quality status check before merge, prevent bypass where practical, and protect validation/governance paths.

## GOV-005 — Secret scanning
**Status:** Unverified

The repository documentation requires secret scanning where supported, but current connector capabilities have not verified its effective state.

## GOV-006 — Final-compliance evidence closure
**Status:** Open — acceptance blocker for the golden VM baseline

`Test-CUVMCompliance.ps1` deliberately marks guest Defender, guest Firewall, CUAgent privilege, remote-service state, and clipboard/drive containment as `NOT-ASSESSED`. There is currently no repository mechanism that ingests the corresponding guest-side/manual test evidence and binds it to the exact VM/configuration state under evaluation.

Therefore the current final-compliance script is structurally incapable of producing an acceptance-grade exit `0` without `-AllowNotAssessed`. The override is diagnostic only and must never be used to accept the golden baseline.

**Preferred resolution:** implement an evidence-closure mechanism that consumes independently generated guest/manual test results, verifies they belong to the exact VM/configuration/baseline state, and converts only valid current evidence into assessed controls. The mechanism itself must pass exact-head and exact-deployed validation before use.

## Acceptance rule
None of these items may be represented as PASS without direct configuration evidence. Until a dedicated private repository exists, sanitized technical content only is permitted here. Golden-baseline acceptance is blocked while GOV-006 remains open.
