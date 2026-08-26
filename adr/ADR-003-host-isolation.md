# ADR-003 — Host Isolation Boundary

## Status
Accepted

## Decision
Treat the physical Windows host and Hyper-V management plane as outside the authority boundary of ChatGPT Computer Use.

## Required baseline
During containment validation, `CU-VM01` receives no normal access to:
- host drives or shared folders
- host clipboard
- host administrator credentials
- Hyper-V Manager or checkpoint controls
- host PowerShell/registry
- host browser/password-manager state
- unnecessary device redirection

Routine Computer Use operates as guest standard user `CUAgent`; `CUAdmin` is reserved for controlled maintenance.

## Rationale
The containment layer must remain independently controllable even when guest automation is incorrect, compromised, or destructive.

## Alternatives considered
- run Computer Use directly on the host
- operate the VM through broad Enhanced Session redirection
- use one shared administrative identity across host and guest

## Consequences
Some convenience features are intentionally unavailable during baseline validation. Individual integrations may be added later only as explicit, reviewed exceptions with dedicated tests.
