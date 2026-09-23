[CmdletBinding()]
param(
    [string]$PlanPath = (Join-Path $PSScriptRoot '..\..\scripts\hyperv\Get-CUVMBuildPlan.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PlanPath)) {
    throw "Build plan script not found: $PlanPath"
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $PlanPath).Path,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw "Build plan has syntax errors: $($parseErrors -join '; ')"
}

$forbidden = @(
    'Checkpoint-VM',
    'Disable-WindowsOptionalFeature',
    'Enable-WindowsOptionalFeature',
    'Install-WindowsFeature',
    'New-NetNat',
    'New-VM',
    'New-VMSwitch',
    'Remove-VM',
    'Set-VM',
    'Set-VMSwitch'
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
            $_ -in $forbidden -or $_ -match $stateChangingPattern
        }
)
if ($violations.Count -gt 0) {
    throw "Build plan script contains forbidden state-changing commands: $($violations -join ', ')"
}

$output = & $PlanPath
if ($LASTEXITCODE -ne 0) {
    throw "Build plan script exited with code $LASTEXITCODE"
}

$plan = $output | ConvertFrom-Json
if ($null -eq $plan) {
    throw 'Build plan did not produce JSON.'
}

if ($plan.Mode -ne 'ReadOnlyPlan') {
    throw "Build plan mode must be ReadOnlyPlan, got '$($plan.Mode)'."
}
if ($plan.ImplementationAuthorized -ne $false -or $plan.AuthorizationStatus -ne 'NOT AUTHORIZED') {
    throw 'Current revision must remain unauthorized.'
}
if ($plan.SubnetResolved -ne $false) {
    throw 'Current spec must report Network.Subnet as unresolved.'
}
if ($plan.ReviewedCreatorPresent -ne $false) {
    throw 'Current revision must report the reviewed creator as missing.'
}
if (@($plan.Blockers) -notcontains 'Reviewed creator is missing: New-CUVM.ps1 is not present in this revision.') {
    throw 'Build plan output is missing the reviewed creator blocker.'
}
if (@($plan.Blockers) -notcontains 'Network.Subnet remains unresolved until Gate A host-route evidence selects a non-overlapping NAT subnet.') {
    throw 'Build plan output is missing the unresolved subnet blocker.'
}

Write-Output 'Build plan read-only guard: PASS'
exit 0
