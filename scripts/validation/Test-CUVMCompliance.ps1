[CmdletBinding()]
param(
    [string]$VMName,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\config\vm-spec.psd1'),
    [switch]$AllowNotAssessed
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
if (-not $VMName) { $VMName = $config.VMName }

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param([string]$Control,[ValidateSet('PASS','WARNING','FAIL','NOT-ASSESSED')][string]$Status,[string]$Observed)
    $results.Add([pscustomobject]@{ Control=$Control; Status=$Status; Observed=$Observed })
}

try {
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    Add-Result 'VM exists' 'PASS' $vm.Name
} catch {
    Add-Result 'VM exists' 'FAIL' $_.Exception.Message
    $results | Format-Table -AutoSize
    exit 1
}

if ($vm.Generation -eq $config.Generation) { Add-Result 'VM generation' 'PASS' "Generation $($vm.Generation)" } else { Add-Result 'VM generation' 'FAIL' "Generation $($vm.Generation); expected $($config.Generation)" }

$processor = Get-VMProcessor -VMName $VMName
if ($processor.Count -eq $config.Compute.ProcessorCount) { Add-Result 'vCPU baseline' 'PASS' "$($processor.Count) vCPU" } else { Add-Result 'vCPU baseline' 'FAIL' "$($processor.Count) vCPU; expected $($config.Compute.ProcessorCount)" }

$expectedStartupBytes = [int64]$config.Compute.StartupMemoryGB * 1GB
if ($vm.MemoryStartup -eq $expectedStartupBytes) { Add-Result 'Startup memory' 'PASS' "$($config.Compute.StartupMemoryGB) GB" } else { Add-Result 'Startup memory' 'FAIL' "$([math]::Round($vm.MemoryStartup / 1GB,2)) GB; expected $($config.Compute.StartupMemoryGB) GB" }

$dynamicMemoryEnabled = [bool]$vm.DynamicMemoryEnabled
$dynamicMemoryExpected = [bool]$config.Compute.DynamicMemory
if ($dynamicMemoryEnabled -eq $dynamicMemoryExpected) { Add-Result 'Dynamic memory mode' 'PASS' "Enabled=$dynamicMemoryEnabled" } else { Add-Result 'Dynamic memory mode' 'FAIL' "Enabled=$dynamicMemoryEnabled; expected $dynamicMemoryExpected" }

$disks = @(Get-VMHardDiskDrive -VMName $VMName)
if ($disks.Count -ne 1) {
    Add-Result 'VM storage attachment' 'FAIL' "$($disks.Count) virtual hard disks detected; expected exactly 1"
} else {
    try {
        $expectedDiskBytes = [int64]$config.Storage.SizeGB * 1GB
        $currentPath = [string]$disks[0].Path
        $seenPaths = @{}
        $chain = [System.Collections.Generic.List[object]]::new()
        $chainValid = $true

        while ($currentPath) {
            if ($chain.Count -ge 64) {
                Add-Result 'VHD chain integrity' 'FAIL' 'VHD parent chain exceeds 64 layers'
                $chainValid = $false
                break
            }

            $pathKey = $currentPath.ToLowerInvariant()
            if ($seenPaths.ContainsKey($pathKey)) {
                Add-Result 'VHD chain integrity' 'FAIL' "Cycle detected at '$currentPath'"
                $chainValid = $false
                break
            }
            $seenPaths[$pathKey] = $true

            $layer = Get-VHD -Path $currentPath -ErrorAction Stop
            $chain.Add([pscustomobject]@{
                Path       = $currentPath
                VhdType    = $layer.VhdType.ToString()
                Size       = [int64]$layer.Size
                ParentPath = [string]$layer.ParentPath
            })

            if ([int64]$layer.Size -ne $expectedDiskBytes) {
                Add-Result 'VHD virtual size' 'FAIL' "$currentPath reports $([math]::Round($layer.Size/1GB,2)) GB; expected $($config.Storage.SizeGB) GB"
                $chainValid = $false
            }

            $currentPath = [string]$layer.ParentPath
        }

        if ($chain.Count -gt 0) {
            $root = $chain[$chain.Count - 1]
            if ($root.VhdType -eq $config.Storage.VHDType) {
                Add-Result 'VHD base type' 'PASS' "$($root.VhdType) root: $($root.Path)"
            } else {
                Add-Result 'VHD base type' 'FAIL' "$($root.VhdType) root; expected $($config.Storage.VHDType)"
                $chainValid = $false
            }

            if ($chain.Count -gt 1) {
                $invalidChildren = @($chain | Select-Object -First ($chain.Count - 1) | Where-Object VhdType -ne 'Differencing')
                if ($invalidChildren.Count -gt 0) {
                    Add-Result 'VHD checkpoint chain' 'FAIL' "Non-root checkpoint layer is not Differencing: $($invalidChildren[0].Path) ($($invalidChildren[0].VhdType))"
                    $chainValid = $false
                } else {
                    Add-Result 'VHD checkpoint chain' 'PASS' "$($chain.Count - 1) differencing layer(s) rooted in declared base VHD"
                }
            } else {
                Add-Result 'VHD checkpoint chain' 'PASS' 'No active differencing layer'
            }
        } else {
            Add-Result 'VHD chain integrity' 'FAIL' 'No readable VHD layer returned'
            $chainValid = $false
        }

        if ($chainValid) {
            Add-Result 'VHD chain integrity' 'PASS' "$($chain.Count) layer(s); attached leaf '$($disks[0].Path)'"
            Add-Result 'VHD virtual size' 'PASS' "$($config.Storage.SizeGB) GB across validated chain"
        }
    } catch {
        Add-Result 'VHD metadata' 'FAIL' $_.Exception.Message
    }
}

$firmware = Get-VMFirmware -VMName $VMName
$secureBootEnabled = $firmware.SecureBoot -eq 'On'
if ($secureBootEnabled -eq [bool]$config.Firmware.SecureBoot) { Add-Result 'Secure Boot' 'PASS' "Enabled=$secureBootEnabled" } else { Add-Result 'Secure Boot' 'FAIL' "Enabled=$secureBootEnabled; expected $($config.Firmware.SecureBoot)" }

$security = Get-VMSecurity -VMName $VMName
if ([bool]$security.TpmEnabled -eq [bool]$config.Firmware.VirtualTPM) { Add-Result 'Virtual TPM' 'PASS' "Enabled=$($security.TpmEnabled)" } else { Add-Result 'Virtual TPM' 'FAIL' "Enabled=$($security.TpmEnabled); expected $($config.Firmware.VirtualTPM)" }

$guestService = Get-VMIntegrationService -VMName $VMName -Name 'Guest Service Interface' -ErrorAction SilentlyContinue
$guestServiceExpectedEnabled = [bool]$config.Isolation.GuestServicesFileCopy
if ($guestService) {
    if ([bool]$guestService.Enabled -eq $guestServiceExpectedEnabled) { Add-Result 'Guest Services file copy' 'PASS' "Enabled=$($guestService.Enabled)" } else { Add-Result 'Guest Services file copy' 'FAIL' "Enabled=$($guestService.Enabled); expected $guestServiceExpectedEnabled" }
} else { Add-Result 'Guest Services file copy' 'NOT-ASSESSED' 'Integration service not returned' }

$adapters = @(Get-VMNetworkAdapter -VMName $VMName)
if ($adapters.Count -eq 1) {
    if ($adapters[0].SwitchName -eq $config.Network.SwitchName) { Add-Result 'Network attachment' 'PASS' "1 adapter on '$($adapters[0].SwitchName)'" } else { Add-Result 'Network attachment' 'FAIL' "Adapter attached to '$($adapters[0].SwitchName)'; expected '$($config.Network.SwitchName)'" }
} else { Add-Result 'Network attachment' 'FAIL' "$($adapters.Count) adapters detected; expected exactly 1" }

try {
    $switch = Get-VMSwitch -Name $config.Network.SwitchName -ErrorAction Stop
    if ($config.Network.Mode -eq 'InternalNAT') {
        if ($switch.SwitchType -eq 'Internal') { Add-Result 'Virtual switch type' 'PASS' 'Internal' } else { Add-Result 'Virtual switch type' 'FAIL' "$($switch.SwitchType); expected Internal for InternalNAT" }
    } else {
        Add-Result 'Virtual switch type' 'NOT-ASSESSED' "Network mode '$($config.Network.Mode)' has no runtime switch-type rule"
    }
} catch {
    Add-Result 'Virtual switch existence' 'FAIL' $_.Exception.Message
}

$checkpoints = @(Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue)
$declaredCheckpoints = @($config.Checkpoints)
$duplicateDeclared = @($declaredCheckpoints | Group-Object | Where-Object Count -gt 1)
if ($declaredCheckpoints.Count -eq 0) {
    Add-Result 'Declared checkpoint set' 'FAIL' 'No checkpoints are declared in configuration'
} elseif ($duplicateDeclared.Count -gt 0) {
    Add-Result 'Declared checkpoint set' 'FAIL' "Duplicate checkpoint name(s) in configuration: $($duplicateDeclared.Name -join ', ')"
} else {
    $missingCheckpoints = @($declaredCheckpoints | Where-Object { $name = $_; -not ($checkpoints | Where-Object Name -eq $name) })
    $duplicateRuntime = @($declaredCheckpoints | Where-Object { $name = $_; @($checkpoints | Where-Object Name -eq $name).Count -gt 1 })
    if ($missingCheckpoints.Count -gt 0) {
        Add-Result 'Declared checkpoint set' 'NOT-ASSESSED' "Missing required checkpoint(s): $($missingCheckpoints -join ', ')"
    } elseif ($duplicateRuntime.Count -gt 0) {
        Add-Result 'Declared checkpoint set' 'FAIL' "Duplicate runtime checkpoint name(s): $($duplicateRuntime -join ', ')"
    } else {
        Add-Result 'Declared checkpoint set' 'PASS' "$($declaredCheckpoints.Count) unique declared checkpoints present"
    }
}

$goldenCheckpoint = $declaredCheckpoints[-1]
if ($goldenCheckpoint) {
    $golden = @($checkpoints | Where-Object Name -eq $goldenCheckpoint)
    if ($golden.Count -eq 1) { Add-Result 'Golden checkpoint presence' 'PASS' "$goldenCheckpoint exists uniquely; recovery still requires the separate restore test" }
    elseif ($golden.Count -eq 0) { Add-Result 'Golden checkpoint presence' 'NOT-ASSESSED' "$goldenCheckpoint expected before final acceptance only" }
    else { Add-Result 'Golden checkpoint presence' 'FAIL' "$goldenCheckpoint exists $($golden.Count) times; expected exactly once" }
} else {
    Add-Result 'Golden checkpoint presence' 'FAIL' 'No golden checkpoint can be derived from configuration'
}

Add-Result 'Guest Defender' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'Guest Firewall' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'CUAgent local-admin membership' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'RDP/OpenSSH/SMB/Network Discovery' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'Clipboard/drive containment' 'NOT-ASSESSED' 'Requires manual containment test'

$results | Format-Table -AutoSize
$counts = $results | Group-Object Status | ForEach-Object { [pscustomobject]@{ Status=$_.Name; Count=$_.Count } }
$summary = @{}
foreach ($status in 'PASS','WARNING','FAIL','NOT-ASSESSED') { $match=$counts | Where-Object Status -eq $status; $summary[$status]=if($match){$match.Count}else{0} }
Write-Output "Summary: $($results.Count) controls; $($summary['PASS']) PASS; $($summary['WARNING']) WARNING; $($summary['FAIL']) FAIL; $($summary['NOT-ASSESSED']) NOT-ASSESSED"

if ($summary['FAIL'] -gt 0) { exit 1 }
if ($summary['NOT-ASSESSED'] -gt 0) {
    if ($AllowNotAssessed) {
        Write-Warning "INTERIM DIAGNOSTIC ONLY: $($summary['NOT-ASSESSED']) control(s) remain NOT-ASSESSED. This run is not acceptance evidence."
        exit 0
    }
    Write-Error "Compliance is incomplete: $($summary['NOT-ASSESSED']) control(s) remain NOT-ASSESSED. Final compliance fails closed until all required controls are assessed." -ErrorAction Continue
    exit 2
}
exit 0
