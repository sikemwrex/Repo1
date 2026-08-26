# Gate A — Host Readiness

## Status
Not started.

## Change class
R0 — read-only inspection only.

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
- relevant host and LAN topology

## Required decision output
- safe `CU-VM01` CPU/RAM/disk allocation
- remaining host capacity
- conflicts or constraints
- proposed Gate B network design based on actual topology

## Stop condition
No Hyper-V, firewall, identity or network configuration changes are authorised during Gate A.

## Repository handling
The repository is currently public and GitHub Issues are disabled. Do not commit raw host/network evidence here. Store only sanitized conclusions or references until repository privacy/governance settings are reviewed.
