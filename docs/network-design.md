# Network Design

## Decision intent
`CU-VM01` uses a Hyper-V Internal vSwitch with host-provided NAT. The guest receives outbound Internet access without becoming a normal peer on the physical LAN.

## Target traffic model

`CU-VM01 -> Hyper-V Internal vSwitch -> Host NAT -> Internet`

## Default policy
- Internet egress: allowed as required for ChatGPT and approved guest applications.
- Guest-to-host management access: deny unless explicitly required and documented.
- Guest-to-private-LAN access: deny by default after the actual host/LAN topology is inspected.
- Inbound connections from the physical LAN: not required for MVP.
- Bridged/external vSwitch: not part of the baseline.

## Pre-change validation
Before creating subnets, NAT objects, firewall rules, or routes, inspect:
- active host adapters and address ranges
- existing Hyper-V switches and NAT objects
- VPN/overlay networks
- corporate or home RFC1918 ranges
- routes that could overlap the proposed VM subnet

Do not blindly block all RFC1918 ranges before choosing the guest NAT subnet.

## Validation requirements
1. Guest obtains expected address and default route.
2. DNS resolution succeeds.
3. External HTTPS access succeeds.
4. Host management surfaces are not unintentionally reachable.
5. Disallowed private-LAN targets are unreachable.
6. No existing host/VPN route is broken.

## Rollback
Network implementation must record the exact objects created so Gate B can remove only project-owned switch, NAT, address and firewall objects without disturbing unrelated networking.
