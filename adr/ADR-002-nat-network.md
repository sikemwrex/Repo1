# ADR-002 — Internal NAT Network

## Status
Accepted

## Decision
Use a Hyper-V Internal vSwitch with host NAT for `CU-VM01` rather than attaching the VM directly to an External/bridged switch.

## Rationale
- keeps the VM off the physical LAN as a normal peer
- provides required Internet access
- permits explicit host firewall/routing policy
- reduces accidental exposure to printers, NAS, routers and other LAN services
- remains reproducible with native PowerShell

## Alternatives considered
- Hyper-V External vSwitch / bridged networking
- Default Switch
- no networking

## Consequences
The host becomes part of the guest network path and the NAT subnet must be chosen only after host, VPN and existing Hyper-V routes are inspected for overlap.

## Validation
Internet access, DNS, private-LAN restrictions and rollback must be tested before acceptance.
