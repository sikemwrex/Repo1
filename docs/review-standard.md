# Engineering Review Standard

## Lifecycle
Every material change uses: `Proposed -> Reviewed -> Implemented -> Validated -> Accepted`.

Security-sensitive changes also require explicit rollback planning and evidence capture.

## Risk classes
- R0: read-only inspection; execute directly and report.
- R1: low-risk documentation or reversible metadata change; execute then verify.
- R2: VM/switch creation or similarly scoped infrastructure change; pre-check, execute, state-verify.
- R3: firewall, networking, identity or security-boundary change; review, rollback plan, execute, validate independently.
- R4: destructive, credential-bearing or host-wide change; explicit user approval before execution.

## Four-perspective review
1. Build — did the command/action complete?
2. Audit — does the resulting state match the intended control?
3. Adversarial — what unintended access or bypass remains?
4. Recovery — can the prior known-good state be restored?

## Evidence rule
Command success is not compliance evidence by itself. Evidence should record requirement, method, expected result, observed result, pass/fail state and a non-sensitive reference. Raw evidence containing hostnames, IPs, credentials, tokens, account identifiers, private screenshots or logs stays outside the public repository unless sanitized.

## Acceptance rule
No golden checkpoint may be labelled `03-COMPUTER-USE-VERIFIED` while a mandatory containment, privilege, network or recovery test is failed, blocked or not run.
