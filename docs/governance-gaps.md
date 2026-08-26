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

## GOV-004 — Repository rulesets
**Status:** Open

Ruleset query returned no configured repository rulesets. Main-branch protection could not be independently read because the integration received HTTP 403.

**Preferred resolution:** require PR-based changes and passing PowerShell Quality checks before merge once repository rules/branch protection can be configured.

## GOV-005 — Secret scanning
**Status:** Unverified

The repository documentation requires secret scanning where supported, but current connector capabilities have not verified its effective state.

## Acceptance rule
None of these items may be represented as PASS without direct configuration evidence. Until a dedicated private repository exists, sanitized technical content only is permitted here.
