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
        $vhd = Get-VHD -Path $disks[0].Path -ErrorAction Stop
        if ($vhd.VhdType.ToString() -eq $config.Storage.VHDType) { Add-Result 'VHD type' 'PASS' $vhd.VhdType.ToString() } else { Add-Result 'VHD type' 'FAIL' "$($vhd.VhdType); expected $($config.Storage.VHDType)" }
        $expectedDiskBytes = [int64]$config.Storage.SizeGB * 1GB
        if ($vhd.Size -eq $expectedDiskBytes) { Add-Result 'VHD size' 'PASS' "$($config.Storage.SizeGB) GB" } else { Add-Result 'VHD size' 'FAIL' "$([math]::Round($vhd.Size/1GB,2)) GB; expected $($config.Storage.SizeGB) GB" }
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
$goldenCheckpoint = $config.Checkpoints[-1]
$golden = $checkpoints | Where-Object Name -eq $goldenCheckpoint
if ($golden) { Add-Result 'Golden checkpoint presence' 'PASS' "$goldenCheckpoint exists; recovery still requires the separate restore test" } else { Add-Result 'Golden checkpoint presence' 'NOT-ASSESSED' "$goldenCheckpoint expected before final acceptance only" }

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
    Write-Error "Compliance is incomplete: $($summary['NOT-ASSESSED']) control(s) remain NOT-ASSESSED. Final compliance fails closed until all required controls are assessed."
    exit 2
}
exit 0
