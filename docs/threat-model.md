# Threat and Failure Model

## Protected assets
- Physical Windows host and user data
- Host credentials and browser sessions
- Hyper-V management and recovery controls
- Local network devices and services
- Golden VM baseline and rebuild definitions

## Primary threat/failure cases
1. Computer Use attempts an unintended host interaction.
2. Guest receives access to host files, clipboard, devices or credentials.
3. Guest can reach private-LAN systems not required for the workload.
4. Routine Computer Use runs with unnecessary administrator privilege.
5. A VM task damages the guest and recovery is not proven.
6. Configuration drifts after initial acceptance.
7. Secrets or sensitive evidence are committed to the public repository.

## Required controls
- Run ChatGPT Desktop inside the guest rather than operating a host-side VM window.
- Keep Hyper-V management on the host only.
- Use `CUAgent` for routine operation and `CUAdmin` for maintenance.
- Disable host drive redirection/shared folders during baseline validation.
- Validate clipboard isolation before acceptance.
- Use NAT/internal networking and test private-LAN reachability explicitly.
- Maintain checkpoints as rollback controls and separate backups/rebuild definitions.
- Validate configuration after implementation; command success alone is not evidence of compliance.
- Never store secrets, credentials, private VM exports, sensitive logs or screenshots in this public repository.

## Review method
For each material change, assess four perspectives:
1. Build: did the change execute?
2. Audit: is resulting state actually compliant?
3. Adversarial: what unintended access remains possible?
4. Recovery: can the prior known-good state be restored?
