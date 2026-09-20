[CmdletBinding()]
param(
    [string]$PlanPath = (Join-Path $PSScriptRoot '..\..\scripts\hyperv\Get-CUVMBuildPlan.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PlanPath)) {
    throw "Build plan script not found: $PlanPath"
}

$source = Get-Content -LiteralPath $PlanPath -Raw
$forbidden = @(
    'New-VM',
    'Set-VM',
    'New-VMSwitch',
    'Set-VMSwitch',
    'New-NetNat',
    'Enable-WindowsOptionalFeature',
    'Disable-WindowsOptionalFeature',
    'Install-WindowsFeature',
    'Checkpoint-VM',
    'Remove-VM'
)

$violations = @($forbidden | Where-Object { $source -match [regex]::Escape($_) })
if ($violations.Count -gt 0) {
    throw "Build plan script contains forbidden state-changing commands: $($violations -join ', ')"
}

$output = & $PlanPath | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "Build plan script exited $LASTEXITCODE"
}

if ($output -notmatch 'ImplementationAuthorized') {
    throw 'Build plan output missing ImplementationAuthorized.'
}

if ($output -notmatch 'NOT AUTHORIZED') {
    throw 'Current spec must remain unauthorized until Gate A resolves Network.Subnet and a reviewed creator exists.'
}

Write-Output 'Build plan read-only guard: PASS'
exit 0
