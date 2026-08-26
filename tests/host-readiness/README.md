# Host Readiness Tests

Gate A is R0/read-only.

## Required checks
- Windows edition/build supports intended Hyper-V use
- hardware virtualization available/enabled
- Hyper-V current state recorded
- CPU topology recorded
- installed/available RAM recorded
- SSD/NVMe free capacity recorded
- Secure Boot and TPM state recorded
- existing VMs, switches, NAT objects and relevant routes recorded
- VPN/overlay conflicts identified

## Pass condition
A safe `CU-VM01` CPU/RAM/disk allocation and non-overlapping network plan can be proposed without changing host state.

## Evidence
Store sanitized conclusions in the repository. Raw machine/network evidence must not be committed while the repository is public.
