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

function Test-CUPrivateIPv4Cidr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Cidr
    )

    $candidate = Get-CUCidrRange -Cidr $Cidr
    foreach ($privateCidr in @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')) {
        $privateRange = Get-CUCidrRange -Cidr $privateCidr
        if (
            $candidate.Network -ge $privateRange.Network -and
            $candidate.Broadcast -le $privateRange.Broadcast
        ) {
            return $true
        }
    }

    return $false
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

$requiredRawSections = @(
    'OperatingSystem',
    'ComputerSystem',
    'Processor',
    'Volumes',
    'PhysicalDisks',
    'HyperVFeature',
    'SecureBoot',
    'TPM',
    'HyperVVMs',
    'VirtualSwitches',
    'NetNat',
    'NetworkAdapters',
    'IPv4Addresses',
    'VpnConnections',
    'IPv4Routes'
)

$missingRawSections = @(
    $requiredRawSections |
        Where-Object { $_ -notin $raw.PSObject.Properties.Name }
)

$checks.EvidenceEnvelope = [ordered]@{
    RawSchemaVersion       = $raw.EvidenceSchemaVersion
    SanitizedSchemaVersion = $sanitized.EvidenceSchemaVersion
    RawReadOnlyGate        = $raw.ReadOnlyGate
    SanitizedReadOnlyGate  = $sanitized.ReadOnlyGate
    EvidenceIdPresent      = -not [string]::IsNullOrWhiteSpace([string]$raw.EvidenceId)
    MissingRawSections     = $missingRawSections
}

if (
    $raw.EvidenceSchemaVersion -ne '1.0' -or
    $sanitized.EvidenceSchemaVersion -ne '1.0'
) {
    $blockers.Add('Unsupported or mismatched Gate A evidence schema version.')
}
if ($raw.ReadOnlyGate -ne 'Gate A' -or $sanitized.ReadOnlyGate -ne 'Gate A') {
    $blockers.Add('Evidence does not declare the expected Gate A read-only boundary.')
}
if ([string]::IsNullOrWhiteSpace([string]$raw.EvidenceId)) {
    $blockers.Add('Raw evidence has no EvidenceId.')
}
if ($missingRawSections.Count -gt 0) {
    $blockers.Add("Raw Gate A evidence is missing required section(s): $($missingRawSections -join ', ').")
}

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

$rawQueryFailures = @(
    $raw.PSObject.Properties |
        Where-Object {
            $_.Value -is [pscustomobject] -and
            $_.Value.PSObject.Properties.Name -contains 'Available' -and
            -not [bool]$_.Value.Available
        } |
        ForEach-Object Name |
        Sort-Object
)
$sanitizedQueryFailures = @(
    $sanitized.QueryFailures |
        ForEach-Object { [string]$_ } |
        Sort-Object
)
$queryFailureListsMatch = (
    ($rawQueryFailures -join [char]0) -eq
    ($sanitizedQueryFailures -join [char]0)
)

$checks.QueryCoverage = [ordered]@{
    RawFailureCount       = $rawQueryFailures.Count
    RawFailures           = $rawQueryFailures
    SanitizedFailureCount = $sanitizedQueryFailures.Count
    SanitizedFailures     = $sanitizedQueryFailures
    ListsMatch            = $queryFailureListsMatch
    Complete              = ($rawQueryFailures.Count -eq 0 -and $queryFailureListsMatch)
}
if (-not $queryFailureListsMatch) {
    $blockers.Add('Sanitized QueryFailures does not match failures derived from raw evidence.')
}
if ($rawQueryFailures.Count -gt 0) {
    $blockers.Add("Gate A collector reported query failures: $($rawQueryFailures -join ', ').")
}

$processorData = @($raw.Processor.Data)
$derivedPhysicalCores = [int](($processorData | Measure-Object -Property NumberOfCores -Sum).Sum)
$derivedLogicalProcessors = [int](($processorData | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
$derivedInstalledMemoryGB = if ([bool]$raw.ComputerSystem.Available) {
    [math]::Round(([double]$raw.ComputerSystem.Data.TotalPhysicalMemory / 1GB), 2)
}
else {
    0
}
$derivedAvailableMemoryGB = if ([bool]$raw.OperatingSystem.Available) {
    [math]::Round((([double]$raw.OperatingSystem.Data.FreePhysicalMemoryKiB * 1KB) / 1GB), 2)
}
else {
    0
}
$derivedHypervisorPresent = [bool]$raw.ComputerSystem.Data.HypervisorPresent
$derivedFeatureAvailable = [bool]$raw.HyperVFeature.Available
$derivedFeatureState = [string]$raw.HyperVFeature.Data.State
$derivedSecureBootAvailable = [bool]$raw.SecureBoot.Available
$derivedSecureBootEnabled = [bool]$raw.SecureBoot.Data.Enabled
$derivedTpmAvailable = [bool]$raw.TPM.Available
$derivedTpmPresent = [bool]$raw.TPM.Data.TpmPresent
$derivedTpmReady = [bool]$raw.TPM.Data.TpmReady
$derivedVmCount = @($raw.HyperVVMs.Data).Count
$derivedSwitchCount = @($raw.VirtualSwitches.Data).Count
$derivedNatCount = @($raw.NetNat.Data).Count
$derivedVpnCount = @($raw.VpnConnections.Data).Count
$derivedRouteCount = @($raw.IPv4Routes.Data).Count
$derivedDefaultRouteCount = @(
    @($raw.IPv4Routes.Data) |
        Where-Object DestinationPrefix -eq '0.0.0.0/0'
).Count

$summaryMismatches = [System.Collections.Generic.List[string]]::new()
if ([double]$sanitized.Hardware.InstalledMemoryGB -ne $derivedInstalledMemoryGB) { $summaryMismatches.Add('InstalledMemoryGB') }
if ([double]$sanitized.Hardware.AvailableMemoryGB -ne $derivedAvailableMemoryGB) { $summaryMismatches.Add('AvailableMemoryGB') }
if ([int]$sanitized.Hardware.PhysicalCores -ne $derivedPhysicalCores) { $summaryMismatches.Add('PhysicalCores') }
if ([int]$sanitized.Hardware.LogicalProcessors -ne $derivedLogicalProcessors) { $summaryMismatches.Add('LogicalProcessors') }
if ([bool]$sanitized.Hardware.HypervisorPresent -ne $derivedHypervisorPresent) { $summaryMismatches.Add('HypervisorPresent') }
if ([bool]$sanitized.HyperV.FeatureQueryAvailable -ne $derivedFeatureAvailable) { $summaryMismatches.Add('FeatureQueryAvailable') }
if ([string]$sanitized.HyperV.FeatureState -ne $derivedFeatureState) { $summaryMismatches.Add('FeatureState') }
if ([int]$sanitized.HyperV.ExistingVMCount -ne $derivedVmCount) { $summaryMismatches.Add('ExistingVMCount') }
if ([int]$sanitized.HyperV.ExistingSwitchCount -ne $derivedSwitchCount) { $summaryMismatches.Add('ExistingSwitchCount') }
if ([int]$sanitized.HyperV.ExistingNatCount -ne $derivedNatCount) { $summaryMismatches.Add('ExistingNatCount') }
if ([bool]$sanitized.Security.SecureBootAvailable -ne $derivedSecureBootAvailable) { $summaryMismatches.Add('SecureBootAvailable') }
if ([bool]$sanitized.Security.SecureBootEnabled -ne $derivedSecureBootEnabled) { $summaryMismatches.Add('SecureBootEnabled') }
if ([bool]$sanitized.Security.TpmQueryAvailable -ne $derivedTpmAvailable) { $summaryMismatches.Add('TpmQueryAvailable') }
if ([bool]$sanitized.Security.TpmPresent -ne $derivedTpmPresent) { $summaryMismatches.Add('TpmPresent') }
if ([bool]$sanitized.Security.TpmReady -ne $derivedTpmReady) { $summaryMismatches.Add('TpmReady') }
if ([int]$sanitized.Network.VpnConnectionCount -ne $derivedVpnCount) { $summaryMismatches.Add('VpnConnectionCount') }
if ([int]$sanitized.Network.IPv4RouteCount -ne $derivedRouteCount) { $summaryMismatches.Add('IPv4RouteCount') }
if ([int]$sanitized.Network.DefaultRouteCount -ne $derivedDefaultRouteCount) { $summaryMismatches.Add('DefaultRouteCount') }

$checks.SanitizedConsistency = [ordered]@{
    Match      = ($summaryMismatches.Count -eq 0)
    Mismatches = @($summaryMismatches)
}
if ($summaryMismatches.Count -gt 0) {
    $blockers.Add("Sanitized evidence disagrees with decision-critical values derived from raw evidence: $($summaryMismatches -join ', ').")
}

$installedMemoryGB = $derivedInstalledMemoryGB
$availableMemoryGB = $derivedAvailableMemoryGB
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
$logicalProcessors = $derivedLogicalProcessors
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
$volumeEvidenceAvailable = [bool]$raw.Volumes.Available
$checks.VolumeEvidence = [ordered]@{
    Available = $volumeEvidenceAvailable
    Count     = $volumeData.Count
}
if (-not $volumeEvidenceAvailable) {
    $blockers.Add('Volume evidence is unavailable.')
}

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

$vmEvidenceAvailable = [bool]$raw.HyperVVMs.Available
$switchEvidenceAvailable = [bool]$raw.VirtualSwitches.Available
$natEvidenceAvailable = [bool]$raw.NetNat.Available

if (-not $vmEvidenceAvailable) {
    $blockers.Add('Hyper-V VM inventory evidence is unavailable.')
}
if (-not $switchEvidenceAvailable) {
    $blockers.Add('Virtual-switch inventory evidence is unavailable.')
}
if (-not $natEvidenceAvailable) {
    $blockers.Add('NAT inventory evidence is unavailable.')
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

$featureState = $derivedFeatureState
$hyperVEnabled = $featureState -in @('1', 'Enabled')
$checks.HyperV = [ordered]@{
    HypervisorPresent     = $derivedHypervisorPresent
    FeatureQueryAvailable = $derivedFeatureAvailable
    FeatureState          = $featureState
    HyperVEnabled         = $hyperVEnabled
    ExistingVMCount       = $derivedVmCount
    ExistingSwitchCount   = $derivedSwitchCount
    ExistingNatCount      = $derivedNatCount
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
    SecureBootAvailable = $derivedSecureBootAvailable
    SecureBootEnabled   = $derivedSecureBootEnabled
    TpmQueryAvailable   = $derivedTpmAvailable
    TpmPresent          = $derivedTpmPresent
    TpmReady            = $derivedTpmReady
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
        if (-not (Test-CUPrivateIPv4Cidr -Cidr $CandidateSubnet)) {
            throw "Candidate CIDR must be wholly contained in RFC1918 private IPv4 address space: $CandidateSubnet"
        }

        if ($candidateRange.Prefix -gt 30) {
            throw "Candidate CIDR is too small for an internal NAT subnet: $CandidateSubnet"
        }

        $routeEvidenceAvailable = [bool]$raw.IPv4Routes.Available
        $routeData = @($raw.IPv4Routes.Data)
        if (-not $routeEvidenceAvailable) {
            throw 'Captured IPv4 route evidence is unavailable.'
        }

        $routePrefixes = @(
            $routeData |
                ForEach-Object DestinationPrefix |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        if ($routePrefixes.Count -eq 0) {
            throw 'Captured route evidence is incomplete: no IPv4 route prefixes were recorded.'
        }

        foreach ($routePrefix in $routePrefixes) {
            try {
                $routeRange = Get-CUCidrRange -Cidr $routePrefix
                if (-not $routeRange.IsNetworkAligned) {
                    throw "Captured route CIDR is not network aligned: $routePrefix"
                }
            }
            catch {
                throw "Captured IPv4 route evidence contains an invalid prefix '$routePrefix': $($_.Exception.Message)"
            }
        }

        if ('0.0.0.0/0' -notin $routePrefixes) {
            throw 'Captured route evidence is incomplete: a default IPv4 route is required.'
        }

        foreach ($routePrefix in @($routePrefixes | Where-Object { $_ -ne '0.0.0.0/0' })) {
            if (Test-CUCidrOverlap -First $CandidateSubnet -Second $routePrefix) {
                $subnetOverlaps += $routePrefix
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
                $natRange = Get-CUCidrRange -Cidr $natPrefix
                if (-not $natRange.IsNetworkAligned) {
                    throw "Captured NAT CIDR is not network aligned: $natPrefix"
                }
            }
            catch {
                throw "Captured NAT evidence contains an invalid prefix '$natPrefix': $($_.Exception.Message)"
            }

            if (Test-CUCidrOverlap -First $CandidateSubnet -Second $natPrefix) {
                $subnetOverlaps += $natPrefix
            }
        }

        $addressEvidenceAvailable = [bool]$raw.IPv4Addresses.Available
        if (-not $addressEvidenceAvailable) {
            throw 'Captured IPv4 address evidence is unavailable.'
        }
        foreach ($address in @($raw.IPv4Addresses.Data)) {
            if ([string]::IsNullOrWhiteSpace([string]$address.IPAddress)) {
                throw 'Captured IPv4 address evidence contains an empty IP address.'
            }
            $addressCidr = "$($address.IPAddress)/$($address.PrefixLength)"
            try {
                $null = Get-CUCidrRange -Cidr $addressCidr
            }
            catch {
                throw "Captured IPv4 address evidence contains an invalid address/prefix '$addressCidr': $($_.Exception.Message)"
            }
            if (Test-CUCidrOverlap -First $CandidateSubnet -Second $addressCidr) {
                $subnetOverlaps += "address:$addressCidr"
            }
        }

        $subnetOverlaps = @($subnetOverlaps | Sort-Object -Unique)
        $vpnCount = $derivedVpnCount
        $checks.Network = [ordered]@{
            CandidateSubnet = $CandidateSubnet
            Assessed        = $true
            Overlaps        = $subnetOverlaps
            NonOverlapping  = ($subnetOverlaps.Count -eq 0)
            VpnCount        = $vpnCount
        }
        if ($subnetOverlaps.Count -gt 0) {
            $blockers.Add("Candidate subnet $CandidateSubnet overlaps captured route/NAT prefix(es): $($subnetOverlaps -join ', ').")
        }
        if ($vpnCount -gt 0) {
            $blockers.Add('Configured VPN connections are present. Their potential address spaces must be explicitly assessed before a Gate B NAT subnet can be approved.')
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
