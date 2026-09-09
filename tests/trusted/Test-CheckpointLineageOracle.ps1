[CmdletBinding()]
param(
    [string]$CandidateValidatorPath,
    [string]$TrustedConfigPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Invoke-LineageOracle {
    param(
        [Parameter(Mandatory)][string]$ValidatorPath,
        [Parameter(Mandatory)][string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ValidatorPath)) { throw "Candidate validator not found: $ValidatorPath" }
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Trusted config not found: $ConfigPath" }

    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $validatorLiteral = (Resolve-Path -LiteralPath $ValidatorPath).Path.Replace("'", "''")
    $configLiteral = (Resolve-Path -LiteralPath $ConfigPath).Path.Replace("'", "''")

    function Invoke-Scenario {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][hashtable]$ParentMap,
            [Parameter(Mandatory)][int]$ExpectedExitCode
        )

        $mapLiteral = ($ParentMap.GetEnumerator() | Sort-Object Name | ForEach-Object {
            $k = [string]$_.Key
            $v = [string]$_.Value
            "'$($k.Replace("'","''"))'='$($v.Replace("'","''"))'"
        }) -join ';'

        $child = @"
function Get-VM { [pscustomobject]@{ Name='CU-VM01'; Generation=2; MemoryStartup=8GB; DynamicMemoryEnabled=`$false } }
function Get-VMProcessor { [pscustomobject]@{ Count=4 } }
function Get-VMHardDiskDrive { [pscustomobject]@{ Path='C:\fake\CU-VM01.vhdx' } }
function Get-VHD { param([string]`$Path) [pscustomobject]@{ VhdType='Dynamic'; Size=[int64]100GB; ParentPath=`$null } }
function Get-VMFirmware { [pscustomobject]@{ SecureBoot='On' } }
function Get-VMSecurity { [pscustomobject]@{ TpmEnabled=`$true } }
function Get-VMIntegrationService { [CmdletBinding()] param([string]`$VMName,[string]`$Name) [pscustomobject]@{ Enabled=`$false } }
function Get-VMNetworkAdapter { [pscustomobject]@{ SwitchName='CU-NAT' } }
function Get-VMSwitch { [pscustomobject]@{ SwitchType='Internal' } }

`$snapshots = @(
    [pscustomobject]@{ Name='00-WIN11-CLEAN'; Id=[guid]'00000000-0000-0000-0000-000000000001' },
    [pscustomobject]@{ Name='01-WIN11-HARDENED'; Id=[guid]'00000000-0000-0000-0000-000000000002' },
    [pscustomobject]@{ Name='02-CHATGPT-INSTALLED'; Id=[guid]'00000000-0000-0000-0000-000000000003' },
    [pscustomobject]@{ Name='03-COMPUTER-USE-VERIFIED'; Id=[guid]'00000000-0000-0000-0000-000000000004' }
)
`$parentMap = @{$mapLiteral}

function Get-VMSnapshot {
    [CmdletBinding(DefaultParameterSetName='All')]
    param(
        [Parameter(ParameterSetName='All')][string[]]`$VMName,
        [Parameter(ParameterSetName='Parent',Mandatory)][object]`$ParentOf,
        [Parameter(ParameterSetName='Child',Mandatory)][object]`$ChildOf,
        [string]`$Name
    )

    if (`$PSCmdlet.ParameterSetName -eq 'Parent') {
        `$parentName = `$parentMap[[string]`$ParentOf.Name]
        if (-not `$parentName) { return }
        return `$snapshots | Where-Object Name -eq `$parentName
    }

    if (`$PSCmdlet.ParameterSetName -eq 'Child') {
        return `$snapshots | Where-Object { `$parentMap[[string]`$_.Name] -eq [string]`$ChildOf.Name }
    }

    if (`$Name) { return `$snapshots | Where-Object Name -eq `$Name }
    return `$snapshots
}

& '$validatorLiteral' -ConfigPath '$configLiteral' -AllowNotAssessed
exit `$LASTEXITCODE
"@

        $output = (& $pwsh -NoLogo -NoProfile -NonInteractive -Command $child 2>&1 | Out-String)
        $actual = $LASTEXITCODE
        Write-Output $output

        if ($actual -ne $ExpectedExitCode) {
            throw "Trusted lineage oracle scenario '$Name' exit code $actual; expected $ExpectedExitCode"
        }

        Write-Output "Trusted lineage oracle scenario PASS: $Name -> exit $actual"
    }

    Invoke-Scenario -Name 'Declared checkpoint chain is ordered' -ParentMap @{
        '01-WIN11-HARDENED'='00-WIN11-CLEAN'
        '02-CHATGPT-INSTALLED'='01-WIN11-HARDENED'
        '03-COMPUTER-USE-VERIFIED'='02-CHATGPT-INSTALLED'
    } -ExpectedExitCode 0

    Invoke-Scenario -Name 'Misordered middle checkpoint must fail' -ParentMap @{
        '01-WIN11-HARDENED'='00-WIN11-CLEAN'
        '02-CHATGPT-INSTALLED'='00-WIN11-CLEAN'
        '03-COMPUTER-USE-VERIFIED'='02-CHATGPT-INSTALLED'
    } -ExpectedExitCode 1

    Invoke-Scenario -Name 'Branched golden checkpoint must fail' -ParentMap @{
        '01-WIN11-HARDENED'='00-WIN11-CLEAN'
        '02-CHATGPT-INSTALLED'='01-WIN11-HARDENED'
        '03-COMPUTER-USE-VERIFIED'='01-WIN11-HARDENED'
    } -ExpectedExitCode 1

    Invoke-Scenario -Name 'Missing immediate parent evidence must fail' -ParentMap @{} -ExpectedExitCode 1

    Write-Output 'Trusted checkpoint-lineage oracle: PASS'
}

if ($SelfTest) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cu-oracle-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $config = Join-Path $tempRoot 'vm-spec.psd1'
        @"
@{
    VMName='CU-VM01'
    Generation=2
    Compute=@{ ProcessorCount=4; StartupMemoryGB=8; DynamicMemory=`$false }
    Storage=@{ VHDType='Dynamic'; SizeGB=100 }
    Firmware=@{ SecureBoot=`$true; VirtualTPM=`$true }
    Network=@{ Mode='InternalNAT'; SwitchName='CU-NAT' }
    Isolation=@{ GuestServicesFileCopy=`$false }
    Checkpoints=@('00-WIN11-CLEAN','01-WIN11-HARDENED','02-CHATGPT-INSTALLED','03-COMPUTER-USE-VERIFIED')
}
"@ | Set-Content -LiteralPath $config -Encoding utf8

        $good = Join-Path $tempRoot 'good.ps1'
        @'
param([string]$ConfigPath,[switch]$AllowNotAssessed)
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$all = @(Get-VMSnapshot -VMName $config.VMName)
for ($i=1; $i -lt $config.Checkpoints.Count; $i++) {
    $child = $all | Where-Object Name -eq $config.Checkpoints[$i]
    $parent = @(Get-VMSnapshot -ParentOf $child)
    if ($parent.Count -ne 1 -or $parent[0].Name -ne $config.Checkpoints[$i-1]) { exit 1 }
}
exit 0
'@ | Set-Content -LiteralPath $good -Encoding utf8

        $bad = Join-Path $tempRoot 'bad.ps1'
        @'
param([string]$ConfigPath,[switch]$AllowNotAssessed)
$null = Import-PowerShellDataFile -LiteralPath $ConfigPath
$null = Get-VMSnapshot -VMName 'CU-VM01'
exit 0
'@ | Set-Content -LiteralPath $bad -Encoding utf8

        Invoke-LineageOracle -ValidatorPath $good -ConfigPath $config

        $rejected = $false
        try {
            Invoke-LineageOracle -ValidatorPath $bad -ConfigPath $config
        } catch {
            $rejected = $true
            Write-Output "Trusted oracle negative self-test PASS: vulnerable fixture rejected"
        }
        if (-not $rejected) { throw 'Trusted oracle self-test failed: vulnerable fixture was not rejected' }

        Write-Output 'Trusted checkpoint-lineage oracle self-test: PASS'
        exit 0
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $CandidateValidatorPath -or -not $TrustedConfigPath) {
    throw 'CandidateValidatorPath and TrustedConfigPath are required unless -SelfTest is used.'
}

Invoke-LineageOracle -ValidatorPath $CandidateValidatorPath -ConfigPath $TrustedConfigPath
