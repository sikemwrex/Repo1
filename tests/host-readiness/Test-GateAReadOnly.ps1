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

$allowedEvidenceWrites = @(
    'New-Item',
    'Set-Content'
)

$stateChangingPattern = '^(Add|Clear|Disable|Enable|Install|New|Remove|Rename|Reset|Restart|Resume|Set|Start|Stop|Suspend|Uninstall|Update)-'

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

$violations = @(
    $commands |
        Where-Object {
            $_ -match $stateChangingPattern -and
            $_ -notin $allowedEvidenceWrites
        }
)

if ($violations.Count -gt 0) {
    throw "Gate A read-only boundary violated by state-changing command(s): $($violations -join ', ')"
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
    'Get-NetIPAddress',
    'Get-NetRoute'
)

$missingQueries = @($requiredQueries | Where-Object { $_ -notin $commands })
if ($missingQueries.Count -gt 0) {
    throw "Gate A collector is missing required read-only query coverage: $($missingQueries -join ', ')"
}

Write-Output 'Gate A collector read-only static guard: PASS'
