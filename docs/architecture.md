# Architecture

## Objective
Run ChatGPT Desktop and Computer Use inside an isolated Windows 11 VM on a Windows laptop/workstation, while the physical host remains the supervisory and recovery control plane.

## Target
- Hypervisor: Microsoft Hyper-V
- Guest: Windows 11 Generation 2
- VM: `CU-VM01`
- vCPU: 4 initial
- RAM: 8 GB initial, 12 GB preferred where host capacity allows
- Disk: 100 GB dynamic VHDX
- Security: Secure Boot + vTPM
- Networking: internal Hyper-V switch with NAT; private-LAN access controlled by explicit policy
- Guest identities: `CUAdmin` for maintenance, `CUAgent` for routine Computer Use

## Control-plane separation
Computer Use may operate the guest workload. It must not be intentionally granted host administrator credentials, host filesystem access, Hyper-V management, host PowerShell, checkpoint controls, or broad host-device redirection.

## Delivery gates
1. Host readiness — read-only inspection and capacity assessment.
2. Hyper-V/networking — minimum required host virtualization changes.
3. VM creation — create and size `CU-VM01`.
4. Guest build — Windows install, patching, `CUAdmin`/`CUAgent`.
5. Hardening — Defender, firewall, remote-service and sharing controls.
6. ChatGPT — install/authenticate ChatGPT Desktop in guest.
7. Validation — functional, containment, privilege, network and recovery tests.
8. Golden baseline — checkpoint only after mandatory tests pass.

## Change priority
When implementation choices conflict, prefer: host safety > recoverability > reproducibility > simplicity > performance > convenience.
