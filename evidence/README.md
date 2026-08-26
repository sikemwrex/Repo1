# Evidence Handling

This directory defines evidence standards. Do not store raw sensitive evidence here while the repository is public.

## Evidence record format
Each accepted control should identify:
- Control/Test ID
- requirement
- configuration or implementation under test
- exact validation method
- expected result
- observed result
- date/time
- reviewer perspective: Build / Audit / Adversarial / Recovery
- evidence reference

## Allowed in this repository
- sanitized command summaries
- redacted test results
- non-sensitive screenshots only after review
- references to Airtable control/test records

## Never commit
- passwords or credentials
- API keys/tokens
- BitLocker/recovery keys
- private IP topology where unnecessary
- browser profiles/cookies
- raw VM exports or VHD/VHDX files
- sensitive logs
- personal or work documents

## Acceptance rule
Evidence must support the specific control being accepted. Configuration presence alone does not prove effective isolation or recovery.
