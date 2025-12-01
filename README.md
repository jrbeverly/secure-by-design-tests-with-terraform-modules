# Secure-by-design Terraform Experiments

> [!WARNING]
> **AI-authored:** This change was autonomously planned and implemented by an AI software factory from a human-authored specification, with possible subsequent human review or modification.

This repository explores a constrained approach to Terraform module design.

Instead of building one highly configurable module, it uses multiple small modules where each module represents a specific infrastructure and security pattern.

The goal is to encode important security decisions directly into the module structure, reduce the number of valid configurations, and make it harder for callers to accidentally weaken the intended design.

- `aws-managed-sse/` — always uses AWS-managed server-side encryption.
- `caller-provided-kms/` — requires the caller to provide a KMS key.
- `pattern-managed-kms/` — provisions and manages the KMS key as part of the pattern.

```bash
aws-managed-sse/check.sh
caller-provided-kms/check.sh
pattern-managed-kms/check.sh
./mutation-check.sh
```

## Notes

- Example isn't really illustrating the area of interest
- Does show some of the concepts, in that it allows for stricter enforcement of constraints
- Needs more investigation
