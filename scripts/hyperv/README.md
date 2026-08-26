# Hyper-V Scripts

Automation in this directory creates and manages only project-owned Hyper-V resources.

## Expected responsibilities
- create/update `CU-NAT` internal switch and project NAT configuration
- create `CU-VM01` from `config/vm-spec.psd1`
- configure CPU, memory, storage, firmware, Secure Boot and vTPM
- manage project checkpoints
- validate resulting Hyper-V state

## Quality gates
PowerShell must pass syntax validation, PSScriptAnalyzer, controlled execution, state validation, and repeat-execution testing before becoming baseline.

A second run should converge on the declared state or report `Already compliant` rather than duplicate configuration.
