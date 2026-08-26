[CmdletBinding()]
param(
    [string]$VMName = 'CU-VM01'
)

$ErrorActionPreference = 'Stop'

$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [string]$Control,
        [ValidateSet('PASS','WARNING','FAIL','NOT-ASSESSED')]
        [string]$Status,
        [string]$Observed
    )
    $results.Add([pscustomobject]@{
        Control  = $Control
        Status   = $Status
        Observed = $Observed
    })
}

try {
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    Add-Result 'VM exists' 'PASS' $vm.Name
} catch {
    Add-Result 'VM exists' 'FAIL' $_.Exception.Message
    $results | Format-Table -AutoSize
    exit 1
}

$processor = Get-VMProcessor -VMName $VMName
if ($processor.Count -eq 4) {
    Add-Result 'vCPU baseline' 'PASS' "$($processor.Count) vCPU"
} else {
    Add-Result 'vCPU baseline' 'WARNING' "$($processor.Count) vCPU; declared baseline is 4 pending host sizing approval"
}

$firmware = Get-VMFirmware -VMName $VMName
if ($firmware.SecureBoot -eq 'On') {
    Add-Result 'Secure Boot' 'PASS' 'Enabled'
} else {
    Add-Result 'Secure Boot' 'FAIL' "$($firmware.SecureBoot)"
}

$tpm = Get-VMKeyProtector -VMName $VMName -ErrorAction SilentlyContinue
$security = Get-VMSecurity -VMName $VMName
if ($security.TpmEnabled) {
    Add-Result 'Virtual TPM' 'PASS' 'Enabled'
} else {
    Add-Result 'Virtual TPM' 'FAIL' 'Disabled'
}

$guestService = Get-VMIntegrationService -VMName $VMName -Name 'Guest Service Interface' -ErrorAction SilentlyContinue
if ($guestService -and -not $guestService.Enabled) {
    Add-Result 'Guest Services file copy' 'PASS' 'Disabled'
} elseif ($guestService) {
    Add-Result 'Guest Services file copy' 'WARNING' 'Enabled; baseline requires explicit justification'
} else {
    Add-Result 'Guest Services file copy' 'NOT-ASSESSED' 'Integration service not returned'
}

$adapters = Get-VMNetworkAdapter -VMName $VMName
if ($adapters.Count -eq 1) {
    Add-Result 'Network adapter count' 'PASS' "1 adapter on switch '$($adapters[0].SwitchName)'"
} else {
    Add-Result 'Network adapter count' 'WARNING' "$($adapters.Count) adapters detected"
}

$checkpoints = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue
$golden = $checkpoints | Where-Object Name -eq '03-COMPUTER-USE-VERIFIED'
if ($golden) {
    Add-Result 'Golden checkpoint presence' 'PASS' '03-COMPUTER-USE-VERIFIED exists'
} else {
    Add-Result 'Golden checkpoint presence' 'NOT-ASSESSED' 'Expected before final acceptance only'
}

Add-Result 'Guest Defender' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'Guest Firewall' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'CUAgent local-admin membership' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'RDP/OpenSSH/SMB/Network Discovery' 'NOT-ASSESSED' 'Requires guest-side validation'
Add-Result 'Clipboard/drive containment' 'NOT-ASSESSED' 'Requires manual containment test'

$results | Format-Table -AutoSize

if ($results.Status -contains 'FAIL') {
    exit 1
}
exit 0
