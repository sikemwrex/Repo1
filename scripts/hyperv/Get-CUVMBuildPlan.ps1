[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\config\vm-spec.psd1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "VM specification not found: $ConfigPath"
}

$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$blockers = [System.Collections.Generic.List[string]]::new()

if ([string]::IsNullOrWhiteSpace($config.VMName)) { $blockers.Add('VMName is missing.') }
if ($config.Network.Mode -ne 'InternalNAT') { $blockers.Add('Network mode is not InternalNAT.') }
if ([string]::IsNullOrWhiteSpace($config.Network.SwitchName)) { $blockers.Add('SwitchName is missing.') }
if ([string]::IsNullOrWhiteSpace([string]$config.Network.Subnet)) {
    $blockers.Add('Network.Subnet remains unresolved until Gate A host-route evidence selects a non-overlapping NAT subnet.')
}

$creatorPath = Join-Path $PSScriptRoot 'New-CUVM.ps1'
if (-not (Test-Path -LiteralPath $creatorPath)) {
    $blockers.Add('No reviewed New-CUVM.ps1 exists. Gate B implementation is not present in this revision.')
}

$plan = [ordered]@{
    SchemaVersion = '1.0'
    Mode = 'ReadOnlyPlan'
    ImplementationAuthorized = $false
    VMName = $config.VMName
    Generation = $config.Generation
    ProcessorCount = $config.Compute.ProcessorCount
    StartupMemoryGB = $config.Compute.StartupMemoryGB
    PreferredMemoryGB = $config.Compute.PreferredMemoryGB
    StorageGB = $config.Storage.SizeGB
    SecureBoot = [bool]$config.Firmware.SecureBoot
    VirtualTPM = [bool]$config.Firmware.VirtualTPM
    SwitchName = $config.Network.SwitchName
    NetworkMode = $config.Network.Mode
    SubnetResolved = -not [string]::IsNullOrWhiteSpace([string]$config.Network.Subnet)
    DeclaredCheckpoints = @($config.Checkpoints)
    NextAuthorizedHostAction = 'Run Gate A read-only collector on the Windows host: ./scripts/host/Get-CUVMHostReadiness.ps1'
    Blockers = @($blockers)
}

$plan | ConvertTo-Json -Depth 6 | Write-Output

if ($blockers.Count -gt 0) {
    Write-Output 'CU-VM01 build plan: NOT AUTHORIZED'
    exit 0
}

Write-Output 'CU-VM01 build plan: AUTHORIZED'
exit 0
