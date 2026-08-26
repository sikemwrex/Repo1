# CU-VM01 Acceptance Plan

Mandatory tests before golden-baseline acceptance:

1. Functional guest control — Computer Use operates guest Notepad, File Explorer and browser.
2. Host desktop separation — Computer Use cannot operate a clearly identified host application.
3. Clipboard isolation — unique clipboard data does not cross the host/guest boundary during baseline testing.
4. Filesystem isolation — host drives and personal folders are unavailable inside the guest.
5. Network isolation — guest Internet works; unauthorised private-LAN resources do not.
6. Privilege boundary — CUAgent cannot perform administrative changes without elevation.
7. Recovery — checkpoint restore returns the expected prior state.
8. Reproducibility — documented configuration is sufficient for rebuild by a competent administrator.

For each test capture: Test ID, timestamp, preconditions, steps, expected result, observed result, PASS/FAIL/BLOCKED, and sanitized evidence reference.

A failed containment test blocks golden checkpoint acceptance.
