# Guest Scripts

Guest automation configures only the Windows 11 workload inside `CU-VM01`.

## Baseline scope
- Windows Update state verification
- Defender and firewall verification
- SmartScreen verification where scriptable
- network discovery/file sharing checks
- RDP, OpenSSH Server and PowerShell Remoting checks
- `CUAgent` local-group membership verification
- ChatGPT prerequisite/application checks where appropriate

## Security rule
Guest scripts must not embed host credentials, reusable passwords, tokens, API keys or recovery material.

Normal Computer Use operates as `CUAgent`; administrative maintenance is separated through `CUAdmin`.
