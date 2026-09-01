# CU-VM01 Acceptance Plan

Mandatory tests before golden-baseline acceptance:

0. Configuration contract — `tests/static/Test-VMConfigContract.ps1` passes against the exact `config/vm-spec.psd1` proposed for deployment.
1. Functional guest control — Computer Use operates guest Notepad, File Explorer and browser.
2. Host desktop separation — Computer Use cannot operate a clearly identified host application.
3. Clipboard isolation — unique clipboard data does not cross the host/guest boundary during baseline testing.
4. Filesystem isolation — host drives and personal folders are unavailable inside the guest.
5. Network isolation — guest Internet works; unauthorised private-LAN resources do not.
6. Privilege boundary — CUAgent cannot perform administrative changes without elevation.
7. Recovery — checkpoint restore returns the expected prior state.
8. Reproducibility — documented configuration is sufficient for rebuild by a competent administrator.
9. Evidence closure — guest-side/manual results required by final compliance are ingested through a reviewed mechanism that proves each result belongs to the exact VM/configuration/baseline state under evaluation. Until that mechanism exists, golden-baseline acceptance is BLOCKED.
10. Final compliance — `scripts/validation/Test-CUVMCompliance.ps1` is run without `-AllowNotAssessed` and exits 0 with zero FAIL and zero NOT-ASSESSED controls. A run using `-AllowNotAssessed` is interim diagnostic evidence only and can never satisfy final acceptance.

For each test capture: Test ID, timestamp, preconditions, exact VM/configuration/baseline identity, steps, expected result, observed result, PASS/FAIL/BLOCKED, and sanitized evidence reference.

A failed configuration-contract, containment, recovery, privilege, evidence-closure, or final-compliance test blocks golden checkpoint acceptance. Any required control left NOT-ASSESSED blocks final acceptance.
