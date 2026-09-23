# Hyper-V Scripts

Automation in this directory creates and manages only project-owned Hyper-V resources.

## Current revision
- `Get-CUVMBuildPlan.ps1` is the only executable Hyper-V script. It is **R0 / read-only**.
- It emits the declared `CU-VM01` plan from `config/vm-spec.psd1` as JSON.
- The current revision always reports `ImplementationAuthorized: false`; it identifies the unresolved `Network.Subnet` and missing reviewed creator blockers.
- This revision contains no VM, switch, NAT, Hyper-V feature, checkpoint, or network mutation behavior.

## Expected later responsibilities
- create/update `CU-NAT` internal switch and project NAT configuration
- create `CU-VM01` from `config/vm-spec.psd1`
- configure CPU, memory, storage, firmware, Secure Boot and vTPM
- manage project checkpoints
- validate resulting Hyper-V state

Those creators are **not authorized by this folder existing**. They require Gate A evidence, a reviewed change, and exact-head validation.

## Quality gates
PowerShell must pass syntax validation, PSScriptAnalyzer, controlled execution, state validation, and repeat-execution testing before becoming baseline.

A second run should converge on the declared state or report `Already compliant` rather than duplicate configuration.
