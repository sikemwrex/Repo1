#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RawPath,

    [Parameter(Mandatory)]
    [string]$SanitizedPath,

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\config\vm-spec.psd1'),

    [string]$CollectorPath = (Join-Path $PSScriptRoot 'Get-CUVMHostReadiness.ps1'),

    [string]$CandidateSubnet,

    [ValidateRange(1, 720)]
    [int]$MaxEvidenceAgeHours = 24,

    [ValidateRange(0, 64)]
    [double]$MinimumHostReserveGB = 4,

    [ValidateRange(0, 1024)]
    [double]$MinimumStorageReserveGB = 20
)

$ErrorActionPreference = 'Stop'

function ConvertTo-CUIPv4UInt32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Address
    )

    $bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
    if ($bytes.Count -ne 4) {
        throw "IPv4 address required: $Address"
    }

    [uint64]$value = 0
    foreach ($byte in $bytes) {
        $value = (($value -shl 8) -bor [uint64]$byte)
    }

    return [uint32]$value
}

function Get-CUCidrRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Cidr
    )

    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) {
        throw "Invalid CIDR: $Cidr"
    }

    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 0 -or $prefix -gt 32) {
        throw "Invalid CIDR prefix: $Cidr"
    }

    $address = ConvertTo-CUIPv4UInt32 -Address $parts[0]
    [uint64]$mask = if ($prefix -eq 0) {
        0
    }
    else {
        (([uint64]4294967295 -shl (32 - $prefix)) -band [uint64]4294967295)
    }

    [uint64]$network = ([uint64]$address -band $mask)
    [uint64]$broadcast = ($network -bor ((-bnot $mask) -band [uint64]4294967295))

    [pscustomobject]@{
        Cidr             = $Cidr
        Prefix           = $prefix
        Address          = [uint64]$address
        Network          = $network
        Broadcast        = $broadcast
        IsNetworkAligned = ([uint64]$address -eq $network)
    }
}

function Test-CUCidrOverlap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$First,

        [Parameter(Mandatory)]
        [string]$Second
    )

    $firstRange = Get-CUCidrRange -Cidr $First
    $secondRange = Get-CUCidrRange -Cidr $Second

    return (
        $firstRange.Network -le $secondRange.Broadcast -and
        $secondRange.Network -le $firstRange.Broadcast
    )
}

$blockers = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks = [ordered]@{}

foreach ($path in @($RawPath, $SanitizedPath, $ConfigPath, $CollectorPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $blockers.Add("Required file not found: $path")
    }
}

if ($blockers.Count -gt 0) {
    [pscustomobject]@{
        SchemaVersion = '1.0'
        Mode          = 'GateAEvidenceAssessment'
        Verdict       = 'BLOCKED'
        Blockers      = @($blockers)
        Warnings      = @($warnings)
        Checks        = $checks
    } | ConvertTo-Json -Depth 8
    exit 1
}

$raw = Get-Content -LiteralPath $RawPath -Raw | ConvertFrom-Json -Depth 20
$sanitized = Get-Content -LiteralPath $SanitizedPath -Raw | ConvertFrom-Json -Depth 20
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath

$rawHash = (Get-FileHash -LiteralPath $RawPath -Algorithm SHA256).Hash
$collectorHash = (Get-FileHash -LiteralPath $CollectorPath -Algorithm SHA256).Hash

$checks.EvidenceIdentity = [ordered]@{
    RawEvidenceId       = $raw.EvidenceId
    SanitizedEvidenceId = $sanitized.EvidenceId
    Match               = ($raw.EvidenceId -eq $sanitized.EvidenceId)
}
if (-not $checks.EvidenceIdentity.Match) {
    $blockers.Add('Raw and sanitized EvidenceId values do not match.')
}

$checks.RawHashBinding = [ordered]@{
    Expected = $sanitized.RawEvidenceSha256
    Actual   = $rawHash
    Match    = ($sanitized.RawEvidenceSha256 -eq $rawHash)
}
if (-not $checks.RawHashBinding.Match) {
    $blockers.Add('Sanitized evidence does not match the actual raw evidence SHA-256.')
}

$collectorFieldsMatch = (
    $raw.CollectorSha256 -eq $sanitized.CollectorSha256 -and
    $sanitized.CollectorSha256 -eq $collectorHash
)
$checks.CollectorProvenance = [ordered]@{
    RawRecorded       = $raw.CollectorSha256
    SanitizedRecorded = $sanitized.CollectorSha256
    LocalActual       = $collectorHash
    Match             = $collectorFieldsMatch
}
if (-not $collectorFieldsMatch) {
    $blockers.Add('Collector SHA-256 provenance does not match the local reviewed collector bytes.')
}

try {
    $captured = [datetimeoffset]::Parse([string]$sanitized.CapturedAt)
    $rawCaptured = [datetimeoffset]::Parse([string]$raw.CapturedAt)
    $age = [datetimeoffset]::UtcNow - $captured.ToUniversalTime()
    $timestampMatch = ($captured -eq $rawCaptured)
    $fresh = ($age.TotalHours -ge -0.1 -and $age.TotalHours -le $MaxEvidenceAgeHours)

    $checks.Freshness = [ordered]@{
        CapturedAt          = $sanitized.CapturedAt
        RawTimestampMatch   = $timestampMatch
        AgeHours            = [math]::Round($age.TotalHours, 2)
        MaxEvidenceAgeHours = $MaxEvidenceAgeHours
        Fresh               = $fresh
    }

    if (-not $timestampMatch) {
        $blockers.Add('Raw and sanitized capture timestamps do not match.')
    }
    if ($age.TotalHours -lt -0.1) {
        $blockers.Add('Gate A evidence timestamp is in the future.')
    }
    elseif (-not $fresh) {
        $blockers.Add("Gate A evidence is stale: $([math]::Round($age.TotalHours, 2)) hours old; maximum is $MaxEvidenceAgeHours.")
    }
}
catch {
    $checks.Freshness = [ordered]@{ Fresh = $false; Error = $_.Exception.Message }
    $blockers.Add('Gate A evidence capture timestamp is invalid.')
}

$queryFailures = @($sanitized.QueryFailures)
$checks.QueryCoverage = [ordered]@{
    FailureCount = $queryFailures.Count
    Failures     = $queryFailures
    Complete     = ($queryFailures.Count -eq 0)
}
if ($queryFailures.Count -gt 0) {
    $blockers.Add("Gate A collector reported query failures: $($queryFailures -join ', ').")
}

$installedMemoryGB = [double]$sanitized.Hardware.InstalledMemoryGB
$availableMemoryGB = [double]$sanitized.Hardware.AvailableMemoryGB
$startupMemoryGB = [double]$config.Compute.StartupMemoryGB
$preferredMemoryGB = [double]$config.Compute.PreferredMemoryGB
$startupInstalledReserveGB = $installedMemoryGB - $startupMemoryGB
$preferredInstalledReserveGB = $installedMemoryGB - $preferredMemoryGB
$startupViable = (
    $installedMemoryGB -ge ($startupMemoryGB + $MinimumHostReserveGB) -and
    $availableMemoryGB -ge ($startupMemoryGB + $MinimumHostReserveGB)
)
$preferredViable = (
    $installedMemoryGB -ge ($preferredMemoryGB + $MinimumHostReserveGB) -and
    $availableMemoryGB -ge ($preferredMemoryGB + $MinimumHostReserveGB)
)

$checks.Memory = [ordered]@{
    InstalledMemoryGB          = $installedMemoryGB
    AvailableMemoryGB          = $availableMemoryGB
    StartupMemoryGB            = $startupMemoryGB
    PreferredMemoryGB          = $preferredMemoryGB
    MinimumHostReserveGB       = $MinimumHostReserveGB
    StartupInstalledReserveGB  = [math]::Round($startupInstalledReserveGB, 2)
    PreferredInstalledReserveGB = [math]::Round($preferredInstalledReserveGB, 2)
    StartupViable              = $startupViable
    PreferredViable            = $preferredViable
}
if (-not $startupViable) {
    $blockers.Add('Current host memory evidence does not support the declared startup allocation while preserving the configured host reserve.')
}
elseif (-not $preferredViable) {
    $warnings.Add('Preferred VM memory is not currently viable; use the declared startup allocation unless fresh evidence supports the preferred value.')
}

$processorCount = [int]$config.Compute.ProcessorCount
$logicalProcessors = [int]$sanitized.Hardware.LogicalProcessors
$checks.Compute = [ordered]@{
    RequestedProcessors = $processorCount
    LogicalProcessors   = $logicalProcessors
    Viable              = ($logicalProcessors -ge $processorCount)
}
if (-not $checks.Compute.Viable) {
    $blockers.Add('Host logical processor count is below the declared VM processor count.')
}

$requiredStorageGB = [double]$config.Storage.SizeGB + $MinimumStorageReserveGB
$volumeData = @($raw.Volumes.Data)
$eligibleVolumes = @(
    $volumeData | Where-Object {
        $_.HealthStatus -eq 'Healthy' -and
        ([double]$_.SizeRemaining / 1GB) -ge $requiredStorageGB
    } | ForEach-Object {
        [pscustomobject]@{
            DriveLetter     = $_.DriveLetter
            FreeGB          = [math]::Round(([double]$_.SizeRemaining / 1GB), 2)
            HealthStatus    = $_.HealthStatus
            FileSystemType  = $_.FileSystemType
        }
    }
)
$checks.Storage = [ordered]@{
    VMStorageGB              = [double]$config.Storage.SizeGB
    MinimumStorageReserveGB  = $MinimumStorageReserveGB
    RequiredFreeGB           = $requiredStorageGB
    EligibleHealthyVolumes   = $eligibleVolumes
    Viable                   = ($eligibleVolumes.Count -gt 0)
}
if (-not $checks.Storage.Viable) {
    $blockers.Add("No healthy fixed volume has at least $requiredStorageGB GB free for the declared VHD plus storage reserve.")
}

$existingVmNames = @(
    $raw.HyperVVMs.Data |
        ForEach-Object Name |
        Where-Object { $_ }
)
$existingSwitches = @($raw.VirtualSwitches.Data)
$vmNameConflict = ($config.VMName -in $existingVmNames)
$targetSwitchConflicts = @(
    $existingSwitches |
        Where-Object { $_.Name -eq $config.Network.SwitchName }
)

$featureState = [string]$sanitized.HyperV.FeatureState
$hyperVEnabled = $featureState -in @('1', 'Enabled')
$checks.HyperV = [ordered]@{
    HypervisorPresent     = [bool]$sanitized.Hardware.HypervisorPresent
    FeatureQueryAvailable = [bool]$sanitized.HyperV.FeatureQueryAvailable
    FeatureState          = $featureState
    HyperVEnabled         = $hyperVEnabled
    ExistingVMCount       = [int]$sanitized.HyperV.ExistingVMCount
    ExistingSwitchCount   = [int]$sanitized.HyperV.ExistingSwitchCount
    ExistingNatCount      = [int]$sanitized.HyperV.ExistingNatCount
    ExistingVMNames       = $existingVmNames
    VMNameConflict        = $vmNameConflict
    TargetSwitchName      = $config.Network.SwitchName
    TargetSwitchConflicts = @($targetSwitchConflicts | ForEach-Object {
        [pscustomobject]@{
            Name       = $_.Name
            SwitchType = $_.SwitchType
        }
    })
}
if (-not $checks.HyperV.HypervisorPresent -or -not $checks.HyperV.FeatureQueryAvailable -or -not $hyperVEnabled) {
    $blockers.Add('Hyper-V readiness is not established by the captured host evidence.')
}
if ($vmNameConflict) {
    $blockers.Add("A VM named $($config.VMName) already exists and must be explicitly reconciled before Gate B.")
}
if ($targetSwitchConflicts.Count -gt 0) {
    $blockers.Add("A virtual switch named $($config.Network.SwitchName) already exists and must be explicitly reconciled before Gate B.")
}

$checks.PlatformSecurity = [ordered]@{
    SecureBootAvailable = [bool]$sanitized.Security.SecureBootAvailable
    SecureBootEnabled   = [bool]$sanitized.Security.SecureBootEnabled
    TpmQueryAvailable   = [bool]$sanitized.Security.TpmQueryAvailable
    TpmPresent          = [bool]$sanitized.Security.TpmPresent
    TpmReady            = [bool]$sanitized.Security.TpmReady
}
if (
    -not $checks.PlatformSecurity.SecureBootAvailable -or
    -not $checks.PlatformSecurity.SecureBootEnabled -or
    -not $checks.PlatformSecurity.TpmQueryAvailable -or
    -not $checks.PlatformSecurity.TpmPresent -or
    -not $checks.PlatformSecurity.TpmReady
) {
    $blockers.Add('Secure Boot and TPM readiness requirements are not fully satisfied.')
}

$subnetOverlaps = @()
if ([string]::IsNullOrWhiteSpace($CandidateSubnet)) {
    $checks.Network = [ordered]@{
        CandidateSubnet = $null
        Assessed        = $false
        Overlaps        = @()
    }
    $blockers.Add('No Gate B NAT subnet candidate was supplied for overlap assessment.')
}
else {
    try {
        $candidateRange = Get-CUCidrRange -Cidr $CandidateSubnet
        if (-not $candidateRange.IsNetworkAligned) {
            throw "Candidate CIDR must identify the network address, not a host address: $CandidateSubnet"
        }

        $routeData = @($raw.IPv4Routes.Data)
        $defaultRoutes = @(
            $routeData |
                Where-Object DestinationPrefix -eq '0.0.0.0/0'
        )
        if ($routeData.Count -eq 0 -or $defaultRoutes.Count -eq 0) {
            throw 'Captured route evidence is incomplete: at least one IPv4 route and one default route are required.'
        }

        $routePrefixes = @(
            $raw.IPv4Routes.Data |
                ForEach-Object DestinationPrefix |
                Where-Object {
                    $_ -and
                    $_ -match '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$' -and
                    $_ -ne '0.0.0.0/0'
                } |
                Sort-Object -Unique
        )

        foreach ($routePrefix in $routePrefixes) {
            try {
                if (Test-CUCidrOverlap -First $CandidateSubnet -Second $routePrefix) {
                    $subnetOverlaps += $routePrefix
                }
            }
            catch {
                $warnings.Add("Skipped unparsable captured IPv4 route prefix: $routePrefix")
            }
        }

        $natPrefixes = @(
            $raw.NetNat.Data |
                ForEach-Object InternalIPInterfaceAddressPrefix |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        foreach ($natPrefix in $natPrefixes) {
            try {
                if (Test-CUCidrOverlap -First $CandidateSubnet -Second $natPrefix) {
                    $subnetOverlaps += $natPrefix
                }
            }
            catch {
                $warnings.Add("Skipped unparsable captured NAT prefix: $natPrefix")
            }
        }

        $subnetOverlaps = @($subnetOverlaps | Sort-Object -Unique)
        $checks.Network = [ordered]@{
            CandidateSubnet = $CandidateSubnet
            Assessed        = $true
            Overlaps        = $subnetOverlaps
            NonOverlapping  = ($subnetOverlaps.Count -eq 0)
            VpnCount        = [int]$sanitized.Network.VpnConnectionCount
        }
        if ($subnetOverlaps.Count -gt 0) {
            $blockers.Add("Candidate subnet $CandidateSubnet overlaps captured route/NAT prefix(es): $($subnetOverlaps -join ', ').")
        }
    }
    catch {
        $checks.Network = [ordered]@{
            CandidateSubnet = $CandidateSubnet
            Assessed        = $false
            Error           = $_.Exception.Message
        }
        $blockers.Add("Candidate subnet is invalid or could not be assessed: $CandidateSubnet")
    }
}

$checks.DeclaredConfig = [ordered]@{
    VMName                = $config.VMName
    Generation            = $config.Generation
    NetworkMode           = $config.Network.Mode
    ConfiguredSubnet      = $config.Network.Subnet
    ImplementationAuthorized = $false
}

if ($null -ne $config.Network.Subnet) {
    $warnings.Add('The repository config already contains a subnet; this evaluator does not authorize or modify it.')
}

$verdict = if ($blockers.Count -eq 0) { 'READY_FOR_OWNER_DECISION' } else { 'BLOCKED' }

$result = [pscustomobject]@{
    SchemaVersion = '1.0'
    Mode          = 'GateAEvidenceAssessment'
    Verdict       = $verdict
    CandidateSubnet = $CandidateSubnet
    Blockers      = @($blockers)
    Warnings      = @($warnings)
    Checks        = $checks
    Authorization = [ordered]@{
        GateAClosed              = $false
        GateBImplementationAuthorized = $false
        HostMutationPerformed   = $false
        SubnetWritten           = $false
    }
}

$result | ConvertTo-Json -Depth 12

if ($blockers.Count -gt 0) {
    exit 1
}

exit 0
