#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$evaluator = Join-Path $repoRoot 'scripts\host\Test-CUVMGateAEvidence.ps1'

if (-not (Test-Path -LiteralPath $evaluator -PathType Leaf)) {
    throw "Gate A evidence evaluator not found: $evaluator"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cu-gate-a-evaluator-" + [guid]::NewGuid().Guid)
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $collectorPath = Join-Path $tempRoot 'collector.ps1'
    $configPath = Join-Path $tempRoot 'vm-spec.psd1'
    $rawPath = Join-Path $tempRoot 'GateA-Raw.json'
    $sanitizedPath = Join-Path $tempRoot 'GateA-Sanitized.json'

    @'
# synthetic reviewed collector bytes for evaluator regression
Get-Date | Out-Null
'@ | Set-Content -LiteralPath $collectorPath -Encoding utf8

    @'
@{
    VMName = 'CU-VM01'
    Generation = 2
    Compute = @{
        ProcessorCount = 4
        StartupMemoryGB = 8
        PreferredMemoryGB = 12
        DynamicMemory = $false
    }
    Storage = @{
        SizeGB = 100
    }
    Network = @{
        Mode = 'InternalNAT'
        SwitchName = 'CU-NAT'
        Subnet = $null
    }
}
'@ | Set-Content -LiteralPath $configPath -Encoding utf8

    function Write-CUTestEvidence {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [datetimeoffset]$CapturedAt,

            [Parameter(Mandatory)]
            [string[]]$Routes,

            [double]$AvailableMemoryGB = 12.0,

            [string[]]$ExistingVMNames = @(),

            [string[]]$ExistingSwitchNames = @()
        )

        $collectorHash = (Get-FileHash -LiteralPath $collectorPath -Algorithm SHA256).Hash
        $evidenceId = [guid]::NewGuid().Guid

        $raw = [ordered]@{
            EvidenceSchemaVersion = '1.0'
            EvidenceId = $evidenceId
            CapturedAt = $CapturedAt.ToString('o')
            CollectorSha256 = $collectorHash
            ReadOnlyGate = 'Gate A'
            Volumes = [ordered]@{
                Data = @(
                    [ordered]@{
                        DriveLetter = 'C'
                        FileSystemType = 'NTFS'
                        Size = 500GB
                        SizeRemaining = 250GB
                        HealthStatus = 'Healthy'
                    }
                )
            }
            HyperVVMs = [ordered]@{
                Available = $true
                Data = @(
                    $ExistingVMNames | ForEach-Object {
                        [ordered]@{ Name = $_ }
                    }
                )
            }
            VirtualSwitches = [ordered]@{
                Available = $true
                Data = @(
                    $ExistingSwitchNames | ForEach-Object {
                        [ordered]@{
                            Name = $_
                            SwitchType = 'Internal'
                        }
                    }
                )
            }
            NetNat = [ordered]@{
                Available = $true
                Data = @()
            }
            IPv4Routes = [ordered]@{
                Available = $true
                Data = @(
                    $Routes | ForEach-Object {
                        [ordered]@{ DestinationPrefix = $_ }
                    }
                )
            }
        }

        $raw | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rawPath -Encoding utf8
        $rawHash = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash

        $sanitized = [ordered]@{
            EvidenceSchemaVersion = '1.0'
            EvidenceId = $evidenceId
            CapturedAt = $CapturedAt.ToString('o')
            CollectorSha256 = $collectorHash
            RawEvidenceSha256 = $rawHash
            ReadOnlyGate = 'Gate A'
            Hardware = [ordered]@{
                PhysicalCores = 4
                LogicalProcessors = 8
                InstalledMemoryGB = 16.0
                AvailableMemoryGB = $AvailableMemoryGB
                HypervisorPresent = $true
            }
            Security = [ordered]@{
                SecureBootAvailable = $true
                SecureBootEnabled = $true
                TpmQueryAvailable = $true
                TpmPresent = $true
                TpmReady = $true
            }
            HyperV = [ordered]@{
                FeatureQueryAvailable = $true
                FeatureState = '1'
                ExistingVMCount = $ExistingVMNames.Count
                ExistingSwitchCount = $ExistingSwitchNames.Count
                ExistingNatCount = 0
            }
            Network = [ordered]@{
                VpnConnectionCount = 0
            }
            QueryFailures = @()
        }

        $sanitized | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sanitizedPath -Encoding utf8
    }

    function Invoke-CUEvaluatorCase {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$CandidateSubnet
        )

        $outputPath = Join-Path $tempRoot ("result-" + [guid]::NewGuid().Guid + '.json')
        $errorPath = Join-Path $tempRoot ("error-" + [guid]::NewGuid().Guid + '.txt')

        $argumentList = @(
            '-NoProfile',
            '-File', $evaluator,
            '-RawPath', $rawPath,
            '-SanitizedPath', $sanitizedPath,
            '-ConfigPath', $configPath,
            '-CollectorPath', $collectorPath,
            '-CandidateSubnet', $CandidateSubnet,
            '-MaxEvidenceAgeHours', '24',
            '-MinimumHostReserveGB', '4',
            '-MinimumStorageReserveGB', '20'
        )

        $process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') `
            -ArgumentList $argumentList `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $outputPath `
            -RedirectStandardError $errorPath

        $stdout = if (Test-Path -LiteralPath $outputPath) {
            Get-Content -LiteralPath $outputPath -Raw
        }
        else {
            ''
        }

        $stderr = if (Test-Path -LiteralPath $errorPath) {
            Get-Content -LiteralPath $errorPath -Raw
        }
        else {
            ''
        }

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = if ($stdout) { $stdout | ConvertFrom-Json -Depth 20 } else { $null }
            StandardError = $stderr
        }
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow) -Routes @(
        '192.168.1.0/24',
        '172.31.48.0/20',
        '0.0.0.0/0'
    )

    $valid = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.0/24'
    if ($valid.ExitCode -ne 0 -or $valid.Output.Verdict -ne 'READY_FOR_OWNER_DECISION') {
        $detail = if ($valid.Output) { $valid.Output | ConvertTo-Json -Depth 20 -Compress } else { '<no JSON output>' }
        throw "Expected fresh non-overlapping evidence to pass. Exit=$($valid.ExitCode) Error=$($valid.StandardError) Output=$detail"
    }
    if ($valid.Output.Authorization.GateAClosed -or $valid.Output.Authorization.GateBImplementationAuthorized) {
        throw 'Evaluator must never close Gate A or authorize Gate B.'
    }

    $overlap = Invoke-CUEvaluatorCase -CandidateSubnet '192.168.1.0/24'
    if ($overlap.ExitCode -eq 0 -or $overlap.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected overlapping candidate subnet to fail closed.'
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow.AddHours(-48)) -Routes @(
        '192.168.1.0/24'
    )
    $stale = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.0/24'
    if ($stale.ExitCode -eq 0 -or $stale.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected stale Gate A evidence to fail closed.'
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow) -Routes @(
        '192.168.1.0/24'
    )
    Add-Content -LiteralPath $rawPath -Value ' ' -Encoding utf8
    $tampered = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.0/24'
    if ($tampered.ExitCode -eq 0 -or $tampered.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected tampered raw evidence to fail closed.'
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow) -Routes @(
        '192.168.1.0/24',
        '0.0.0.0/0'
    ) -AvailableMemoryGB 5.5
    $memory = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.0/24'
    if ($memory.ExitCode -eq 0 -or $memory.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected insufficient current available memory for startup allocation to fail closed.'
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow) -Routes @(
        '192.168.1.0/24',
        '0.0.0.0/0'
    )
    $hostAddress = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.5/24'
    if ($hostAddress.ExitCode -eq 0 -or $hostAddress.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected a non-network-aligned candidate CIDR to fail closed.'
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow) -Routes @(
        '192.168.1.0/24',
        '0.0.0.0/0'
    ) -ExistingVMNames @('CU-VM01')
    $vmCollision = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.0/24'
    if ($vmCollision.ExitCode -eq 0 -or $vmCollision.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected an existing CU-VM01 name collision to fail closed.'
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow) -Routes @(
        '192.168.1.0/24',
        '0.0.0.0/0'
    ) -ExistingSwitchNames @('CU-NAT')
    $switchCollision = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.0/24'
    if ($switchCollision.ExitCode -eq 0 -or $switchCollision.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected an existing CU-NAT switch collision to fail closed.'
    }

    Write-CUTestEvidence -CapturedAt ([datetimeoffset]::UtcNow) -Routes @()
    $missingRoutes = Invoke-CUEvaluatorCase -CandidateSubnet '10.77.77.0/24'
    if ($missingRoutes.ExitCode -eq 0 -or $missingRoutes.Output.Verdict -ne 'BLOCKED') {
        throw 'Expected missing route evidence to fail closed.'
    }

    Write-Output 'Gate A evidence evaluator behavioral regression: PASS'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
