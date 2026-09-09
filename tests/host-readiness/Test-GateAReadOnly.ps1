#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$collector = Join-Path $PSScriptRoot '..\..\scripts\host\Get-CUVMHostReadiness.ps1'
if (-not (Test-Path -LiteralPath $collector)) {
    throw "Gate A collector not found: $collector"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $collector).Path,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    throw "Gate A collector has syntax errors: $($parseErrors -join '; ')"
}

$blockedCommands = @(
    'Add-LocalGroupMember',
    'Disable-NetAdapter',
    'Disable-WindowsOptionalFeature',
    'Enable-NetAdapter',
    'Enable-WindowsOptionalFeature',
    'New-LocalUser',
    'New-NetFirewallRule',
    'New-NetNat',
    'New-VM',
    'New-VMSwitch',
    'Remove-LocalUser',
    'Remove-NetFirewallRule',
    'Remove-NetNat',
    'Remove-VM',
    'Remove-VMSwitch',
    'Restart-NetAdapter',
    'Set-LocalUser',
    'Set-NetFirewallRule',
    'Set-NetNat',
    'Set-VM',
    'Set-VMSwitch',
    'Stop-Service',
    'Start-Service'
)

$commandAsts = $ast.FindAll(
    {
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    },
    $true
)

$commands = @(
    $commandAsts |
        ForEach-Object { $_.GetCommandName() } |
        Where-Object { $_ } |
        Sort-Object -Unique
)

$violations = @($commands | Where-Object { $_ -in $blockedCommands })
if ($violations.Count -gt 0) {
    throw "Gate A read-only boundary violated by command(s): $($violations -join ', ')"
}

$requiredQueries = @(
    'Get-CimInstance',
    'Get-Volume',
    'Get-PhysicalDisk',
    'Get-WindowsOptionalFeature',
    'Confirm-SecureBootUEFI',
    'Get-Tpm',
    'Get-VM',
    'Get-VMSwitch',
    'Get-NetNat',
    'Get-NetAdapter',
    'Get-NetRoute'
)

$missingQueries = @($requiredQueries | Where-Object { $_ -notin $commands })
if ($missingQueries.Count -gt 0) {
    throw "Gate A collector is missing required read-only query coverage: $($missingQueries -join ', ')"
}

Write-Output 'Gate A collector read-only static guard: PASS'
