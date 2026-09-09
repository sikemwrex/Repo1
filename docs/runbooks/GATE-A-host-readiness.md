# Gate A — Host Readiness Runbook

## Purpose
Capture the actual laptop state needed to decide whether the accepted `CU-VM01` architecture can be implemented safely.

## Boundary
Gate A is **R0 / read-only**.

The collector must not:
- enable or disable Hyper-V;
- create or modify VMs, switches, NATs, firewall rules or accounts;
- change Defender, services, network adapters, routes, VPNs, Secure Boot or TPM state;
- install software.

## Run
Open **PowerShell 7 as Administrator** on the Windows host. Elevation is used only so read-only Hyper-V, TPM, Secure Boot and feature queries can return complete results; the collector is statically guarded against host-configuration commands.

```powershell
Set-Location <repository-root>
./scripts/host/Get-CUVMHostReadiness.ps1
```

The collector writes a timestamped folder under the local, non-roaming application-data path:

```text
%LOCALAPPDATA%\CU-VM\GateA\
```

Use `-OutputRoot` only when you deliberately choose another private location.

It produces:

- `GateA-Raw.json` — private operational evidence containing network topology needed to select the Gate B NAT subnet.
- `GateA-Sanitized.json` — shareable summary excluding host name, usernames, MAC addresses, IP addresses, route prefixes and local VM/network object names. It includes the SHA-256 of `GateA-Raw.json` so later analysis can prove which private evidence file the summary belongs to.

## Evidence handling
The GitHub repository is public.

**Never commit `GateA-Raw.json`.**

The raw file may be provided directly for Gate A analysis or stored in the private Google Drive `VIRTUAL MACHINE` evidence folder. Only reviewed sanitized conclusions belong in GitHub.

## Gate A decision
After capture, cross-check the evidence against:

- `config/vm-spec.psd1`;
- `docs/architecture.md`;
- `docs/threat-model.md`;
- Airtable Controls, Tests, Risks and VM Inventory.

Required output:

1. host readiness verdict;
2. final CPU/RAM/disk allocation;
3. Hyper-V capability/status;
4. Secure Boot and TPM status;
5. existing VM/switch/NAT conflicts;
6. VPN/address/route conflicts;
7. non-overlapping Gate B NAT subnet proposal;
8. assumptions disproved;
9. revised risks or config changes required.

No Gate B implementation is authorised by Gate A alone.
