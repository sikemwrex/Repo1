[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\config\vm-spec.psd1')
)

$ErrorActionPreference = 'Stop'
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        $failures.Add($Message)
    }
}

Assert-True (-not [string]::IsNullOrWhiteSpace($config.VMName)) 'VMName must be defined.'
Assert-True ($config.Generation -eq 2) 'Generation must be 2 for the accepted baseline.'
Assert-True ($config.Compute.ProcessorCount -gt 0) 'ProcessorCount must be greater than zero.'
Assert-True ($config.Compute.StartupMemoryGB -gt 0) 'StartupMemoryGB must be greater than zero.'
Assert-True (-not [bool]$config.Compute.DynamicMemory) 'Dynamic memory must remain disabled for the accepted baseline unless changed through reviewed architecture/configuration.'
Assert-True ($config.Storage.SizeGB -ge 64) 'Storage.SizeGB must be at least 64 GB.'
Assert-True ([bool]$config.Firmware.SecureBoot) 'Secure Boot must remain enabled.'
Assert-True ([bool]$config.Firmware.VirtualTPM) 'Virtual TPM must remain enabled.'
Assert-True ($config.Network.Mode -eq 'InternalNAT') 'Network mode must remain InternalNAT.'
Assert-True (-not [string]::IsNullOrWhiteSpace($config.Network.SwitchName)) 'Network switch name must be defined.'
Assert-True (-not [bool]$config.Identity.OperatorMustBeLocalAdmin) 'CUAgent must not be a local administrator.'
Assert-True (-not [bool]$config.Isolation.HostDriveRedirection) 'Host drive redirection must remain disabled.'
Assert-True (-not [bool]$config.Isolation.SharedFolders) 'Shared folders must remain disabled.'
Assert-True (-not [bool]$config.Isolation.SharedClipboardDuringBaseline) 'Shared clipboard must remain disabled during baseline validation.'
Assert-True (-not [bool]$config.Isolation.GuestServicesFileCopy) 'Guest Services file copy must remain disabled.'
Assert-True ($config.Checkpoints.Count -ge 1) 'At least one checkpoint stage must be declared.'
Assert-True ($config.Checkpoints[-1] -eq '03-COMPUTER-USE-VERIFIED') 'Final golden checkpoint name must remain 03-COMPUTER-USE-VERIFIED.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'VM configuration contract: PASS'
