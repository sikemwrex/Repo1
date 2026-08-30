[CmdletBinding()]
param(
    [string]$ValidatorPath = (Join-Path $PSScriptRoot '..\..\scripts\validation\Test-CUVMCompliance.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ValidatorPath)) {
    Write-Error "Validator not found: $ValidatorPath"
    exit 1
}

$source = Get-Content -LiteralPath $ValidatorPath -Raw
$requiredTokens = @(
    'Get-VMHardDiskDrive',
    'Get-VHD',
    '$config.Storage.VHDType',
    '$config.Storage.SizeGB',
    'Get-VMSwitch',
    '$config.Network.Mode',
    "'InternalNAT'",
    "'Internal'",
    '[switch]$AllowNotAssessed',
    "$summary['NOT-ASSESSED'] -gt 0",
    'INTERIM DIAGNOSTIC ONLY',
    'Final compliance fails closed'
)

$missing = @($requiredTokens | Where-Object { -not $source.Contains($_) })
if ($missing.Count -gt 0) {
    $missing | ForEach-Object { Write-Error "Runtime compliance coverage missing required token: $_" }
    exit 1
}

Write-Output 'Runtime compliance coverage: PASS'
