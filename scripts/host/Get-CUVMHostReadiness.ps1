#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CU-VM\GateA')
)

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDirectory = Join-Path $OutputRoot $timestamp
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$rawPath = Join-Path $outputDirectory 'GateA-Raw.json'
$sanitizedPath = Join-Path $outputDirectory 'GateA-Sanitized.json'
$collectorHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash

function Invoke-ReadOnlyQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    try {
        [pscustomobject]@{
            Name      = $Name
            Available = $true
            Data      = & $ScriptBlock
            Error     = $null
        }
    }
    catch {
        [pscustomobject]@{
            Name      = $Name
            Available = $false
            Data      = $null
            Error     = $_.Exception.Message
        }
    }
}

$os = Invoke-ReadOnlyQuery -Name 'OperatingSystem' -ScriptBlock {
    $item = Get-CimInstance -ClassName Win32_OperatingSystem
    [pscustomobject]@{
        Caption                = $item.Caption
        Version                = $item.Version
        BuildNumber            = $item.BuildNumber
        OSArchitecture         = $item.OSArchitecture
        FreePhysicalMemoryKiB  = [int64]$item.FreePhysicalMemory
        TotalVisibleMemoryKiB  = [int64]$item.TotalVisibleMemorySize
    }
}

$computer = Invoke-ReadOnlyQuery -Name 'ComputerSystem' -ScriptBlock {
    $item = Get-CimInstance -ClassName Win32_ComputerSystem
    [pscustomobject]@{
        Manufacturer        = $item.Manufacturer
        Model               = $item.Model
        TotalPhysicalMemory = [int64]$item.TotalPhysicalMemory
        HypervisorPresent   = [bool]$item.HypervisorPresent
    }
}

$cpu = Invoke-ReadOnlyQuery -Name 'Processor' -ScriptBlock {
    @(Get-CimInstance -ClassName Win32_Processor | ForEach-Object {
        [pscustomobject]@{
            Name                                      = $_.Name
            NumberOfCores                             = [int]$_.NumberOfCores
            NumberOfLogicalProcessors                 = [int]$_.NumberOfLogicalProcessors
            VirtualizationFirmwareEnabled             = [bool]$_.VirtualizationFirmwareEnabled
            VMMonitorModeExtensions                   = [bool]$_.VMMonitorModeExtensions
            SecondLevelAddressTranslationExtensions   = [bool]$_.SecondLevelAddressTranslationExtensions
        }
    })
}

$volumes = Invoke-ReadOnlyQuery -Name 'Volumes' -ScriptBlock {
    @(Get-Volume | Where-Object DriveType -eq 'Fixed' | ForEach-Object {
        [pscustomobject]@{
            DriveLetter    = $_.DriveLetter
            FileSystemType = $_.FileSystemType
            Size           = [int64]$_.Size
            SizeRemaining  = [int64]$_.SizeRemaining
            HealthStatus   = [string]$_.HealthStatus
        }
    })
}

$physicalDisks = Invoke-ReadOnlyQuery -Name 'PhysicalDisks' -ScriptBlock {
    @(Get-PhysicalDisk | ForEach-Object {
        [pscustomobject]@{
            FriendlyName = $_.FriendlyName
            MediaType    = [string]$_.MediaType
            BusType      = [string]$_.BusType
            Size         = [int64]$_.Size
            HealthStatus = [string]$_.HealthStatus
        }
    })
}

$hyperVFeature = Invoke-ReadOnlyQuery -Name 'HyperVFeature' -ScriptBlock {
    $feature = $null
    if (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
        try {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
            return [pscustomobject]@{
                FeatureName = $feature.FeatureName
                State       = [string]$feature.State
            }
        }
        catch {
            $feature = $null
        }
    }

    $feature = Get-CimInstance -ClassName Win32_OptionalFeature |
        Where-Object Name -eq 'Microsoft-Hyper-V-All' |
        Select-Object -First 1
    [pscustomobject]@{
        FeatureName = $feature.Name
        State       = [string]$feature.InstallState
    }
}

$secureBoot = Invoke-ReadOnlyQuery -Name 'SecureBoot' -ScriptBlock {
    [pscustomobject]@{
        Enabled = [bool](Confirm-SecureBootUEFI)
    }
}

$tpm = Invoke-ReadOnlyQuery -Name 'TPM' -ScriptBlock {
    $item = Get-Tpm
    [pscustomobject]@{
        TpmPresent          = [bool]$item.TpmPresent
        TpmReady            = [bool]$item.TpmReady
        TpmEnabled          = [bool]$item.TpmEnabled
        TpmActivated        = [bool]$item.TpmActivated
        AutoProvisioning    = [string]$item.AutoProvisioning
    }
}

$hyperVVMs = Invoke-ReadOnlyQuery -Name 'HyperVVMs' -ScriptBlock {
    if (-not (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
        throw 'Get-VM is unavailable.'
    }

    @(Get-VM | ForEach-Object {
        [pscustomobject]@{
            Name             = $_.Name
            State            = [string]$_.State
            Generation       = [int]$_.Generation
            ProcessorCount   = [int]$_.ProcessorCount
            MemoryAssigned   = [int64]$_.MemoryAssigned
        }
    })
}

$virtualSwitches = Invoke-ReadOnlyQuery -Name 'VirtualSwitches' -ScriptBlock {
    if (-not (Get-Command -Name Get-VMSwitch -ErrorAction SilentlyContinue)) {
        throw 'Get-VMSwitch is unavailable.'
    }

    @(Get-VMSwitch | ForEach-Object {
        [pscustomobject]@{
            Name       = $_.Name
            SwitchType = [string]$_.SwitchType
        }
    })
}

$natObjects = Invoke-ReadOnlyQuery -Name 'NetNat' -ScriptBlock {
    if (-not (Get-Command -Name Get-NetNat -ErrorAction SilentlyContinue)) {
        throw 'Get-NetNat is unavailable.'
    }

    @(Get-NetNat | ForEach-Object {
        [pscustomobject]@{
            Name                             = $_.Name
            InternalIPInterfaceAddressPrefix = $_.InternalIPInterfaceAddressPrefix
            Active                           = [bool]$_.Active
        }
    })
}

$networkAdapters = Invoke-ReadOnlyQuery -Name 'NetworkAdapters' -ScriptBlock {
    @(Get-NetAdapter | ForEach-Object {
        [pscustomobject]@{
            Name                 = $_.Name
            InterfaceDescription = $_.InterfaceDescription
            InterfaceIndex       = [int]$_.ifIndex
            Status               = [string]$_.Status
            LinkSpeed            = [string]$_.LinkSpeed
            Virtual              = [bool]$_.Virtual
        }
    })
}

$ipAddresses = Invoke-ReadOnlyQuery -Name 'IPv4Addresses' -ScriptBlock {
    @(Get-NetIPAddress -AddressFamily IPv4 | ForEach-Object {
        [pscustomobject]@{
            IPAddress      = $_.IPAddress
            PrefixLength   = [int]$_.PrefixLength
            InterfaceAlias = $_.InterfaceAlias
            InterfaceIndex = [int]$_.InterfaceIndex
            AddressState   = [string]$_.AddressState
        }
    })
}

$vpnConnections = Invoke-ReadOnlyQuery -Name 'VpnConnections' -ScriptBlock {
    if (-not (Get-Command -Name Get-VpnConnection -ErrorAction SilentlyContinue)) {
        throw 'Get-VpnConnection is unavailable.'
    }

    $user = @(Get-VpnConnection -ErrorAction SilentlyContinue)
    $allUser = @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue)
    @($user + $allUser | Sort-Object Name -Unique | ForEach-Object {
        [pscustomobject]@{
            Name                  = $_.Name
            ConnectionStatus      = [string]$_.ConnectionStatus
            SplitTunneling        = [bool]$_.SplitTunneling
            TunnelType            = [string]$_.TunnelType
        }
    })
}

$routes = Invoke-ReadOnlyQuery -Name 'IPv4Routes' -ScriptBlock {
    @(Get-NetRoute -AddressFamily IPv4 | ForEach-Object {
        [pscustomobject]@{
            DestinationPrefix = $_.DestinationPrefix
            InterfaceAlias    = $_.InterfaceAlias
            InterfaceIndex    = [int]$_.InterfaceIndex
            NextHop           = $_.NextHop
            RouteMetric       = [int]$_.RouteMetric
            State             = [string]$_.State
        }
    })
}

$raw = [ordered]@{
    EvidenceSchemaVersion = '1.0'
    EvidenceId            = [guid]::NewGuid().Guid
    CapturedAt            = (Get-Date).ToString('o')
    CollectorSha256       = $collectorHash
    ReadOnlyGate          = 'Gate A'
    OperatingSystem       = $os
    ComputerSystem        = $computer
    Processor             = $cpu
    Volumes               = $volumes
    PhysicalDisks         = $physicalDisks
    HyperVFeature         = $hyperVFeature
    SecureBoot            = $secureBoot
    TPM                   = $tpm
    HyperVVMs             = $hyperVVMs
    VirtualSwitches       = $virtualSwitches
    NetNat                = $natObjects
    NetworkAdapters       = $networkAdapters
    IPv4Addresses         = $ipAddresses
    VpnConnections        = $vpnConnections
    IPv4Routes            = $routes
}

$raw | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rawPath -Encoding utf8
$rawEvidenceHash = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash

$osData = $os.Data
$computerData = $computer.Data
$processorData = @($cpu.Data)
$volumeData = @($volumes.Data)
$diskData = @($physicalDisks.Data)
$vmData = @($hyperVVMs.Data)
$switchData = @($virtualSwitches.Data)
$natData = @($natObjects.Data)
$adapterData = @($networkAdapters.Data)
$ipAddressData = @($ipAddresses.Data)
$vpnData = @($vpnConnections.Data)
$routeData = @($routes.Data)

$totalCores = ($processorData | Measure-Object -Property NumberOfCores -Sum).Sum
$totalLogical = ($processorData | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
$totalVolumeBytes = ($volumeData | Measure-Object -Property Size -Sum).Sum
$totalFreeBytes = ($volumeData | Measure-Object -Property SizeRemaining -Sum).Sum

$sanitized = [ordered]@{
    EvidenceSchemaVersion = '1.0'
    EvidenceId            = $raw.EvidenceId
    CapturedAt            = $raw.CapturedAt
    CollectorSha256       = $collectorHash
    RawEvidenceSha256     = $rawEvidenceHash
    ReadOnlyGate          = 'Gate A'
    OS                    = if ($os.Available) {
        [ordered]@{
            Caption        = $osData.Caption
            Version        = $osData.Version
            BuildNumber    = $osData.BuildNumber
            Architecture   = $osData.OSArchitecture
        }
    } else { $null }
    Hardware              = [ordered]@{
        Manufacturer       = if ($computer.Available) { $computerData.Manufacturer } else { $null }
        Model              = if ($computer.Available) { $computerData.Model } else { $null }
        PhysicalCores      = $totalCores
        LogicalProcessors  = $totalLogical
        InstalledMemoryGB  = if ($computer.Available) { [math]::Round($computerData.TotalPhysicalMemory / 1GB, 2) } else { $null }
        AvailableMemoryGB  = if ($os.Available) { [math]::Round(($osData.FreePhysicalMemoryKiB * 1KB) / 1GB, 2) } else { $null }
        HypervisorPresent  = if ($computer.Available) { $computerData.HypervisorPresent } else { $null }
    }
    Virtualization        = [ordered]@{
        FirmwareEnabled = @($processorData | ForEach-Object VirtualizationFirmwareEnabled)
        VMMonitorMode   = @($processorData | ForEach-Object VMMonitorModeExtensions)
        SLAT            = @($processorData | ForEach-Object SecondLevelAddressTranslationExtensions)
    }
    Storage               = [ordered]@{
        FixedVolumeCount = $volumeData.Count
        TotalGB          = if ($totalVolumeBytes) { [math]::Round($totalVolumeBytes / 1GB, 2) } else { 0 }
        FreeGB           = if ($totalFreeBytes) { [math]::Round($totalFreeBytes / 1GB, 2) } else { 0 }
        PhysicalDiskCount = $diskData.Count
        MediaTypes       = @($diskData | ForEach-Object MediaType | Sort-Object -Unique)
        BusTypes         = @($diskData | ForEach-Object BusType | Sort-Object -Unique)
    }
    Security              = [ordered]@{
        SecureBootAvailable = $secureBoot.Available
        SecureBootEnabled   = if ($secureBoot.Available) { $secureBoot.Data.Enabled } else { $null }
        TpmQueryAvailable    = $tpm.Available
        TpmPresent           = if ($tpm.Available) { $tpm.Data.TpmPresent } else { $null }
        TpmReady             = if ($tpm.Available) { $tpm.Data.TpmReady } else { $null }
    }
    HyperV                = [ordered]@{
        FeatureQueryAvailable = $hyperVFeature.Available
        FeatureState          = if ($hyperVFeature.Available) { $hyperVFeature.Data.State } else { $null }
        ExistingVMCount       = $vmData.Count
        ExistingSwitchCount   = $switchData.Count
        ExistingNatCount      = $natData.Count
    }
    Network               = [ordered]@{
        AdapterCount       = $adapterData.Count
        ConnectedAdapters  = @($adapterData | Where-Object Status -eq 'Up').Count
        IPv4AddressCount    = $ipAddressData.Count
        VpnConnectionCount = $vpnData.Count
        IPv4RouteCount     = $routeData.Count
        DefaultRouteCount  = @($routeData | Where-Object DestinationPrefix -eq '0.0.0.0/0').Count
    }
    QueryFailures         = @(
        $raw.GetEnumerator() |
            Where-Object { $_.Value -is [pscustomobject] -and $_.Value.PSObject.Properties.Name -contains 'Available' -and -not $_.Value.Available } |
            ForEach-Object {
                [pscustomobject]@{
                    Query = $_.Key
                    Error = $_.Value.Error
                }
            }
    )
    Privacy               = 'Sanitized summary excludes host name, usernames, MAC addresses, IP addresses, route prefixes, VM names, switch names and VPN names.'
}

$sanitized | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sanitizedPath -Encoding utf8

Write-Output "Gate A read-only evidence captured."
Write-Output "Raw private evidence: $rawPath"
Write-Output "Sanitized summary:    $sanitizedPath"
Write-Output "Do not commit GateA-Raw.json to the public repository."
