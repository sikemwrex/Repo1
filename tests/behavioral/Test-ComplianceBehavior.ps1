[CmdletBinding()]
param(
    [string]$ValidatorPath = (Join-Path $PSScriptRoot '..\..\scripts\validation\Test-CUVMCompliance.ps1'),
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\config\vm-spec.psd1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ValidatorPath)) { throw "Validator not found: $ValidatorPath" }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config not found: $ConfigPath" }

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$validatorLiteral = $ValidatorPath.Replace("'", "''")
$configLiteral = $ConfigPath.Replace("'", "''")

function Invoke-Scenario {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$ProcessorCount = 4,
        [string]$RootVhdType = 'Dynamic',
        [int64]$VhdSize = 100GB,
        [switch]$UseDifferencingChain,
        [switch]$BrokenDifferencingParent,
        [string]$SwitchType = 'Internal',
        [string]$AdapterSwitch = 'CU-NAT',
        [bool]$GuestServiceEnabled = $false,
        [switch]$MissingDeclaredCheckpoints,
        [ValidateSet('Ordered','Misordered','Branched','MissingParent')][string]$CheckpointLineage = 'Ordered',
        [switch]$AllowNotAssessed,
        [string]$ExpectedOutputContains,
        [Parameter(Mandatory)][int]$ExpectedExitCode
    )

    $allowArg = if ($AllowNotAssessed) { '-AllowNotAssessed' } else { '' }
    $guestServiceLiteral = if ($GuestServiceEnabled) { '$true' } else { '$false' }
    $attachedPath = if ($UseDifferencingChain) { 'C:\fake\CU-VM01-AutoRecovery.avhdx' } else { 'C:\fake\CU-VM01.vhdx' }
    $parentPath = if ($BrokenDifferencingParent) { 'C:\fake\missing-parent.vhdx' } else { 'C:\fake\CU-VM01.vhdx' }

    $getVhdFunction = if ($UseDifferencingChain) {
@"
function Get-VHD {
    param([string]`$Path)
    if (`$Path -like '*.avhdx') {
        return [pscustomobject]@{ VhdType='Differencing'; Size=[int64]$VhdSize; ParentPath='$parentPath' }
    }
    if (`$Path -eq 'C:\fake\CU-VM01.vhdx') {
        return [pscustomobject]@{ VhdType='$RootVhdType'; Size=[int64]$VhdSize; ParentPath=`$null }
    }
    throw "VHD not found: `$Path"
}
"@
    } else {
@"
function Get-VHD {
    param([string]`$Path)
    return [pscustomobject]@{ VhdType='$RootVhdType'; Size=[int64]$VhdSize; ParentPath=`$null }
}
"@
    }

    $snapshotRows = if ($MissingDeclaredCheckpoints) {
        "        [pscustomobject]@{ Name='03-COMPUTER-USE-VERIFIED'; Id=[guid]'00000000-0000-0000-0000-000000000004' }"
    } else {
@"
        [pscustomobject]@{ Name='00-WIN11-CLEAN'; Id=[guid]'00000000-0000-0000-0000-000000000001' },
        [pscustomobject]@{ Name='01-WIN11-HARDENED'; Id=[guid]'00000000-0000-0000-0000-000000000002' },
        [pscustomobject]@{ Name='02-CHATGPT-INSTALLED'; Id=[guid]'00000000-0000-0000-0000-000000000003' },
        [pscustomobject]@{ Name='03-COMPUTER-USE-VERIFIED'; Id=[guid]'00000000-0000-0000-0000-000000000004' }
"@
    }

    $parentMapLiteral = switch ($CheckpointLineage) {
        'Ordered' { "'01-WIN11-HARDENED'='00-WIN11-CLEAN';'02-CHATGPT-INSTALLED'='01-WIN11-HARDENED';'03-COMPUTER-USE-VERIFIED'='02-CHATGPT-INSTALLED'" }
        'Misordered' { "'01-WIN11-HARDENED'='00-WIN11-CLEAN';'02-CHATGPT-INSTALLED'='00-WIN11-CLEAN';'03-COMPUTER-USE-VERIFIED'='02-CHATGPT-INSTALLED'" }
        'Branched' { "'01-WIN11-HARDENED'='00-WIN11-CLEAN';'02-CHATGPT-INSTALLED'='01-WIN11-HARDENED';'03-COMPUTER-USE-VERIFIED'='01-WIN11-HARDENED'" }
        'MissingParent' { '' }
    }

    $snapshotFunction = @"
`$snapshots = @(
$snapshotRows
)
`$parentMap = @{$parentMapLiteral}

function Get-VMSnapshot {
    [CmdletBinding(DefaultParameterSetName='All')]
    param(
        [Parameter(ParameterSetName='All')][string[]]`$VMName,
        [Parameter(ParameterSetName='Parent',Mandatory)][object]`$ParentOf,
        [string]`$Name
    )

    if (`$PSCmdlet.ParameterSetName -eq 'Parent') {
        `$parentName = `$parentMap[[string]`$ParentOf.Name]
        if (-not `$parentName) { return }
        return `$snapshots | Where-Object Name -eq `$parentName
    }

    if (`$Name) { return `$snapshots | Where-Object Name -eq `$Name }
    return `$snapshots
}
"@

    $child = @"
function Get-VM { [pscustomobject]@{ Name='CU-VM01'; Generation=2; MemoryStartup=8GB; DynamicMemoryEnabled=`$false } }
function Get-VMProcessor { [pscustomobject]@{ Count=$ProcessorCount } }
function Get-VMHardDiskDrive { [pscustomobject]@{ Path='$attachedPath' } }
$getVhdFunction
function Get-VMFirmware { [pscustomobject]@{ SecureBoot='On' } }
function Get-VMSecurity { [pscustomobject]@{ TpmEnabled=`$true } }
function Get-VMIntegrationService { [pscustomobject]@{ Enabled=$guestServiceLiteral } }
function Get-VMNetworkAdapter { [pscustomobject]@{ SwitchName='$AdapterSwitch' } }
function Get-VMSwitch { [pscustomobject]@{ SwitchType='$SwitchType' } }
$snapshotFunction
& '$validatorLiteral' -ConfigPath '$configLiteral' $allowArg
exit `$LASTEXITCODE
"@

    $output = (& $pwsh -NoLogo -NoProfile -NonInteractive -Command $child 2>&1 | Out-String)
    $actual = $LASTEXITCODE
    Write-Output $output
    if ($actual -ne $ExpectedExitCode) {
        throw "Scenario '$Name' exit code $actual; expected $ExpectedExitCode"
    }
    if ($ExpectedOutputContains -and $output -notlike "*$ExpectedOutputContains*") {
        throw "Scenario '$Name' did not emit expected text: $ExpectedOutputContains"
    }
    Write-Output "Behavioral scenario PASS: $Name -> exit $actual"
}

Invoke-Scenario -Name 'Compliant base VHD, interim diagnostic explicitly allowed' -AllowNotAssessed -ExpectedExitCode 0
Invoke-Scenario -Name 'Golden checkpoint differencing chain is rooted in declared base VHD' -UseDifferencingChain -AllowNotAssessed -ExpectedExitCode 0
Invoke-Scenario -Name 'Missing declared recovery checkpoints fail even in diagnostic mode' -MissingDeclaredCheckpoints -AllowNotAssessed -ExpectedOutputContains 'Missing required checkpoint(s)' -ExpectedExitCode 1
Invoke-Scenario -Name 'Misordered declared checkpoint lineage fails' -CheckpointLineage 'Misordered' -AllowNotAssessed -ExpectedOutputContains 'Checkpoint recovery lineage' -ExpectedExitCode 1
Invoke-Scenario -Name 'Branched declared checkpoint lineage fails' -CheckpointLineage 'Branched' -AllowNotAssessed -ExpectedOutputContains 'Checkpoint recovery lineage' -ExpectedExitCode 1
Invoke-Scenario -Name 'Missing immediate checkpoint parent fails' -CheckpointLineage 'MissingParent' -AllowNotAssessed -ExpectedOutputContains 'Checkpoint recovery lineage' -ExpectedExitCode 1
Invoke-Scenario -Name 'Incomplete final assessment fails closed' -ExpectedExitCode 2
Invoke-Scenario -Name 'vCPU drift fails' -ProcessorCount 2 -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Base VHD type drift fails' -RootVhdType 'Fixed' -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Differencing chain with wrong base type fails' -UseDifferencingChain -RootVhdType 'Fixed' -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Broken differencing parent fails closed' -UseDifferencingChain -BrokenDifferencingParent -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Virtual switch type drift fails' -SwitchType 'External' -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Network attachment drift fails' -AdapterSwitch 'WrongSwitch' -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Guest Services file-copy drift fails' -GuestServiceEnabled $true -AllowNotAssessed -ExpectedExitCode 1

Write-Output 'Runtime compliance behavioral regression suite: PASS'
exit 0
