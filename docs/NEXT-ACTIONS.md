# NEXT ACTIONS — ChatGPT Computer Use VM

**Current phase:** Gate A executable / pre-Gate B. No host virtualization change is authorised.

**Main tip evidence:** `5e581fb0b51624013870dce79c71e725a352c713` (merge of PR #21, 2026-10-12).

## User (host) actions required now

These must be performed on the physical Windows laptop that will host `CU-VM01`. No bot or remote tool can execute them.

1. Ensure PowerShell 7 is installed and the repository is current on the host:
   ```powershell
   git clone https://github.com/sikemwrex/Repo1.git
   # or git pull if already present
   Set-Location <repository-root>
   ```

2. Open **PowerShell 7 as Administrator** (elevation is required only for complete read-only queries of Hyper-V, TPM, Secure Boot and optional features).

3. Run the authorised read-only collector and plan:
   ```powershell
   ./scripts/host/Get-CUVMHostReadiness.ps1
   ./scripts/hyperv/Get-CUVMBuildPlan.ps1
   ```

4. Locate the evidence:
   - Private raw: `%LOCALAPPDATA%\CU-VM\GateA\<timestamp>\GateA-Raw.json`
   - Shareable sanitized: same folder `GateA-Sanitized.json`
   - Build plan prints JSON to console (`ImplementationAuthorized: false`).

5. **Never commit `GateA-Raw.json`.** Provide the sanitized JSON (and optionally the raw privately via Drive or direct share) plus the BuildPlan output so Gate A assessment and NAT subnet selection can proceed.

6. After evidence is assessed, a reviewed Gate B change plan must exist before any VM, switch, NAT or Hyper-V feature is created.

## Remaining repository work (in progress)

- Confirm or resolve GOV-001 to GOV-006 (public repo, name, Issues, branch protection, secret scanning, evidence-closure for compliance).
- Draft and review `scripts/hyperv/New-CUVM.ps1` (currently missing; creator blocker).
- Once Gate A selects a non-overlapping RFC1918 NAT subnet, update `config/vm-spec.psd1` Network.Subnet and re-validate.
- Implement guest hardening scripts and evidence-closure path for final compliance (GOV-006).
- Maintain the five required outcomes: working environment, reproducible build, security baseline, recovery capability, audit trail.

## Stop conditions

- No Hyper-V enablement, VM creation, switch/NAT changes, firewall changes or credential material in this phase.
- Repository remains public until privacy is explicitly resolved; sanitized content only.
