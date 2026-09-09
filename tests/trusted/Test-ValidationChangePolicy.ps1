[CmdletBinding()]
param(
    [string[]]$ChangedFiles,
    [string]$CandidateValidatorPath,
    [string]$TrustedConfigPath,
    [string]$TrustedLineageOraclePath = (Join-Path $PSScriptRoot 'Test-CheckpointLineageOracle.ps1'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Normalize-ChangedFiles {
    param([string[]]$Files)
    return @(
        $Files |
        Where-Object { $_ } |
        ForEach-Object { ([string]$_).Replace('\','/').TrimStart('./') } |
        Sort-Object -Unique
    )
}

function Invoke-ValidationChangePolicy {
    param(
        [Parameter(Mandatory)][string[]]$Files,
        [Parameter(Mandatory)][scriptblock]$LineageOracle
    )

    $normalized = Normalize-ChangedFiles -Files $Files
    $implementation = @($normalized | Where-Object { $_ -like 'scripts/*' -or $_ -like 'config/*' })
    $harness = @($normalized | Where-Object { $_ -like 'tests/*' -or $_ -like '.github/workflows/*' })

    if ($implementation.Count -eq 0 -and $harness.Count -eq 0) {
        Write-Output 'Trusted change policy: no validation-sensitive files changed.'
        return
    }

    if ($implementation.Count -gt 0 -and $harness.Count -gt 0) {
        $allowedImplementation = @('scripts/validation/Test-CUVMCompliance.ps1')
        $allowedHarness = @('tests/behavioral/Test-ComplianceBehavior.ps1')

        $unsupportedImplementation = @($implementation | Where-Object { $_ -notin $allowedImplementation })
        $unsupportedHarness = @($harness | Where-Object { $_ -notin $allowedHarness })
        $validatorChanged = 'scripts/validation/Test-CUVMCompliance.ps1' -in $implementation

        if (-not $validatorChanged -or $unsupportedImplementation.Count -gt 0 -or $unsupportedHarness.Count -gt 0) {
            throw "Unsupported implementation + validation-harness co-change. Land/accept an independent trusted oracle or isolate the harness change first. Implementation=[$($implementation -join ', ')]; Harness=[$($harness -join ', ')]"
        }

        & $LineageOracle
        Write-Output 'Trusted change policy: supported validator + behavioral-test co-change independently judged by accepted-base lineage oracle.'
        return
    }

    if ($implementation.Count -gt 0) {
        if ('scripts/validation/Test-CUVMCompliance.ps1' -in $implementation) {
            & $LineageOracle
            Write-Output 'Trusted change policy: implementation-only validator change independently judged by accepted-base lineage oracle.'
        } else {
            Write-Output 'Trusted change policy: implementation-only change; candidate does not redefine its validation harness in the same revision.'
        }
        return
    }

    Write-Output 'Trusted change policy: isolated harness/oracle change. It may not authorize a production co-change until merged and revalidated on main.'
}

function Assert-PolicyPass {
    param([string]$Name,[string[]]$Files,[scriptblock]$Oracle)
    Invoke-ValidationChangePolicy -Files $Files -LineageOracle $Oracle
    Write-Output "Trusted change policy self-test PASS: $Name"
}

function Assert-PolicyReject {
    param([string]$Name,[string[]]$Files,[scriptblock]$Oracle)
    $rejected = $false
    try {
        Invoke-ValidationChangePolicy -Files $Files -LineageOracle $Oracle
    } catch {
        $rejected = $true
        Write-Output "Trusted change policy self-test PASS: $Name rejected"
    }
    if (-not $rejected) { throw "Trusted change policy self-test failed: '$Name' was not rejected" }
}

if ($SelfTest) {
    $script:oracleCalls = 0
    $oracle = { $script:oracleCalls++; Write-Output 'Self-test trusted oracle invoked.' }

    Assert-PolicyPass -Name 'Documentation-only change' -Files @('docs/recovery.md') -Oracle $oracle
    Assert-PolicyPass -Name 'Isolated validation-harness change' -Files @('tests/behavioral/Test-ComplianceBehavior.ps1') -Oracle $oracle
    Assert-PolicyPass -Name 'Implementation-only host change' -Files @('scripts/host/Get-HostReadiness.ps1') -Oracle $oracle
    Assert-PolicyPass -Name 'Supported validator plus behavioral regression co-change' -Files @(
        'scripts/validation/Test-CUVMCompliance.ps1',
        'tests/behavioral/Test-ComplianceBehavior.ps1'
    ) -Oracle $oracle

    if ($script:oracleCalls -ne 1) {
        throw "Trusted change policy self-test failed: expected trusted oracle exactly once; observed $script:oracleCalls"
    }

    Assert-PolicyReject -Name 'Validator plus workflow co-change' -Files @(
        'scripts/validation/Test-CUVMCompliance.ps1',
        '.github/workflows/powershell-quality.yml'
    ) -Oracle $oracle

    Assert-PolicyReject -Name 'Uncovered implementation plus candidate test co-change' -Files @(
        'scripts/hyperv/New-CUVM.ps1',
        'tests/behavioral/Test-CUVMBuild.ps1'
    ) -Oracle $oracle

    Assert-PolicyReject -Name 'Production validator plus trusted-oracle co-change' -Files @(
        'scripts/validation/Test-CUVMCompliance.ps1',
        'tests/trusted/Test-CheckpointLineageOracle.ps1'
    ) -Oracle $oracle

    Write-Output 'Trusted validation-change policy self-test: PASS'
    exit 0
}

if (-not $ChangedFiles -or $ChangedFiles.Count -eq 0) {
    throw 'ChangedFiles is required unless -SelfTest is used.'
}

$normalizedInput = Normalize-ChangedFiles -Files $ChangedFiles

$realOracle = {
    if (-not $CandidateValidatorPath) { throw 'CandidateValidatorPath is required when the production compliance validator changes.' }
    if (-not $TrustedConfigPath) { throw 'TrustedConfigPath is required when the production compliance validator changes.' }
    if (-not (Test-Path -LiteralPath $TrustedLineageOraclePath)) { throw "Trusted lineage oracle not found: $TrustedLineageOraclePath" }

    & $TrustedLineageOraclePath `
        -CandidateValidatorPath $CandidateValidatorPath `
        -TrustedConfigPath $TrustedConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "Trusted lineage oracle failed with exit code $LASTEXITCODE"
    }
}

Invoke-ValidationChangePolicy -Files $normalizedInput -LineageOracle $realOracle
Write-Output 'Trusted validation-change policy: PASS'
exit 0
