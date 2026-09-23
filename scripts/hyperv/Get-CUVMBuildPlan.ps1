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
    $blockers.Add('Reviewed creator is missing: New-CUVM.ps1 is not present in this revision.')
}

$plan = [ordered]@{
    SchemaVersion = '1.0'
    Mode = 'ReadOnlyPlan'
    ImplementationAuthorized = $false
    AuthorizationStatus = 'NOT AUTHORIZED'
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
    ReviewedCreatorPresent = Test-Path -LiteralPath $creatorPath
    DeclaredCheckpoints = @($config.Checkpoints)
    NextAuthorizedHostAction = 'Run Gate A read-only collector on the Windows host: ./scripts/host/Get-CUVMHostReadiness.ps1'
    Blockers = @($blockers)
}

$plan | ConvertTo-Json -Depth 6 | Write-Output
exit 0
