# ADR-001: Hyper-V and Guest Containment

- Status: Accepted
- Date: 2026-08-26

## Decision
Use Microsoft Hyper-V as the laptop virtualization layer. Run ChatGPT Desktop and Computer Use inside `CU-VM01`, a Windows 11 Generation 2 guest. The host remains the management and recovery plane.

## Rationale
Hyper-V provides native Windows integration, Generation 2 VM security features, vTPM, Secure Boot, PowerShell automation, checkpoints, and a low-friction Windows-heavy migration lineage.

## Security boundary
The guest must not be intentionally given host-drive redirection, shared host folders, host administrator credentials, host PowerShell access, Hyper-V management, or checkpoint controls. Clipboard/device conveniences remain disabled during containment validation and may only be introduced later through an explicit reviewed change.

## Alternatives considered
- VMware Workstation: acceptable fallback if a verified Hyper-V incompatibility exists.
- VirtualBox: not preferred for the primary Windows architecture.
- Vagrant: useful later as provisioning orchestration, not as the hypervisor decision.

## Consequences
The build must include independent containment testing and a recovery test before the golden checkpoint is accepted.
