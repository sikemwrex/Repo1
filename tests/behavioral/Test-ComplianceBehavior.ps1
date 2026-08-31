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
        [string]$VhdType = 'Dynamic',
        [int64]$VhdSize = 100GB,
        [string]$SwitchType = 'Internal',
        [string]$AdapterSwitch = 'CU-NAT',
        [bool]$GuestServiceEnabled = $false,
        [switch]$AllowNotAssessed,
        [Parameter(Mandatory)][int]$ExpectedExitCode
    )

    $allowArg = if ($AllowNotAssessed) { '-AllowNotAssessed' } else { '' }
    $guestServiceLiteral = if ($GuestServiceEnabled) { '$true' } else { '$false' }
    $child = @"
function Get-VM { [pscustomobject]@{ Name='CU-VM01'; Generation=2; MemoryStartup=8GB; DynamicMemoryEnabled=`$false } }
function Get-VMProcessor { [pscustomobject]@{ Count=$ProcessorCount } }
function Get-VMHardDiskDrive { [pscustomobject]@{ Path='C:\fake\CU-VM01.vhdx' } }
function Get-VHD { [pscustomobject]@{ VhdType='$VhdType'; Size=[int64]$VhdSize } }
function Get-VMFirmware { [pscustomobject]@{ SecureBoot='On' } }
function Get-VMSecurity { [pscustomobject]@{ TpmEnabled=`$true } }
function Get-VMIntegrationService { [pscustomobject]@{ Enabled=$guestServiceLiteral } }
function Get-VMNetworkAdapter { [pscustomobject]@{ SwitchName='$AdapterSwitch' } }
function Get-VMSwitch { [pscustomobject]@{ SwitchType='$SwitchType' } }
function Get-VMSnapshot { [pscustomobject]@{ Name='03-COMPUTER-USE-VERIFIED' } }
& '$validatorLiteral' -ConfigPath '$configLiteral' $allowArg
exit `$LASTEXITCODE
"@

    & $pwsh -NoLogo -NoProfile -NonInteractive -Command $child | Out-Host
    $actual = $LASTEXITCODE
    if ($actual -ne $ExpectedExitCode) {
        throw "Scenario '$Name' exit code $actual; expected $ExpectedExitCode"
    }
    Write-Output "Behavioral scenario PASS: $Name -> exit $actual"
}

Invoke-Scenario -Name 'Compliant host-side state, interim diagnostic explicitly allowed' -AllowNotAssessed -ExpectedExitCode 0
Invoke-Scenario -Name 'Incomplete final assessment fails closed' -ExpectedExitCode 2
Invoke-Scenario -Name 'vCPU drift fails' -ProcessorCount 2 -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'VHD type drift fails' -VhdType 'Fixed' -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Virtual switch type drift fails' -SwitchType 'External' -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Network attachment drift fails' -AdapterSwitch 'WrongSwitch' -AllowNotAssessed -ExpectedExitCode 1
Invoke-Scenario -Name 'Guest Services file-copy drift fails' -GuestServiceEnabled $true -AllowNotAssessed -ExpectedExitCode 1

Write-Output 'Runtime compliance behavioral regression suite: PASS'
exit 0
