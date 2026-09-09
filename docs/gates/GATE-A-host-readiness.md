# Gate A — Host Readiness

## Status
Prepared for execution — collector not yet run on the physical host.

## Change class
R0 — read-only inspection only.

## Executable collector
`scripts/host/Get-CUVMHostReadiness.ps1`

Static read-only boundary test:
`tests/host-readiness/Test-GateAReadOnly.ps1`

Runbook:
`docs/runbooks/GATE-A-host-readiness.md`

## Required checks
- Windows edition and build
- CPU model, physical cores and logical processors
- installed and available RAM
- system and secondary SSD/NVMe free capacity
- Hyper-V feature/status
- firmware virtualization status
- Secure Boot status
- TPM availability
- existing Hyper-V VMs and virtual switches
- NAT objects, adapters, VPNs and IPv4 routes needed for topology review

## Required decision output
- safe `CU-VM01` CPU/RAM/disk allocation
- remaining host capacity
- conflicts or constraints
- proposed Gate B network design based on actual topology

## Stop condition
No Hyper-V, firewall, identity, service, account or network configuration changes are authorised during Gate A.

## Evidence handling
The repository is public. Raw host/network evidence must remain private and must not be committed. The collector produces a raw private JSON file plus a sanitized summary.
