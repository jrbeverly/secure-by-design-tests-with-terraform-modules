# Security Contracts

Security boundaries for the three encryption key-ownership patterns named in
`VISION.md`. Each contract states what its pattern promises, what the caller
must supply, and what the pattern does not address. Technical design belongs to
Product Engineering; this document defines outcomes only.

The catalogue is local to this experiment. It is not a framework shared with
other experiments.

## Evidence level

The first investigation covers expressible configuration and planned behavior.
Every `check:` below is a static configuration check — inspection of the
module's declared inputs and source, or a plan diff — observable without
applying the module. The contracts require no live deployment, subscriptions,
or standing infrastructure.

Configuration evidence does not imply runtime security or compliance. That
ciphertext is actually written, that the provider enforces the encryption path,
that key policies behave as written, and any regulatory status are external
assumptions unless a check demonstrates them here.

The concrete infrastructure use case (which storage service) is selected by
Product Engineering. These contracts define the encryption key-ownership
boundary; they bind to that use case unchanged.

## Notation

- `check:` — observable without deploying, in the module's declared inputs and
  source or a plan diff.
- `assumption:` — an external property this experiment does not demonstrate.
- Excluded threats are explicit non-claims; the pattern promises nothing about
  them.

## Pattern comparison

| Pattern | Module | Example | Encryption decision | Key ownership | Remaining caller choices | Forbidden configurations |
| --- | --- | --- | --- | --- | --- | --- |
| AWS-managed SSE | `aws-managed-sse/` | `example/` | always on, AWS-managed SSE (`AES256`) | AWS | `bucket_name` only | disable encryption; switch key mode (inexpressible) |
| Caller-provided KMS | `caller-provided-kms/` | `example-caller-provided-kms/` | always on, customer-managed KMS key (`aws:kms`) | caller | `bucket_name` + required `kms_key_id` | disable encryption; switch key mode (inexpressible) |
| Pattern-managed KMS | `pattern-managed-kms/` | `example-pattern-managed-kms/` | always on, customer-managed KMS key (`aws:kms`) | pattern | `bucket_name` only | disable encryption; switch key mode (inexpressible) |

Three separate constrained patterns were investigated rather than one universal
configurable module. `VISION.md`'s goal is to reduce the number of possible
configuration states, and a configurable module would admit the invalid
combinations this comparison forbids — it could be invoked with encryption
disabled or with a different key source selected. Each pattern's
`check.sh` shows those configurations being rejected by terraform before any
resource is created, so the pattern makes the violation inexpressible rather
than merely discouraged. The repetition across the modules is deliberate: it
is the cost of keeping each configuration domain minimal.

## AWS-managed server-side encryption

The module always encrypts the storage resource with the AWS-managed key for
that service. The AWS-managed pattern exposes no caller KMS choice.

**Protected asset.** Data at rest on the storage resource the pattern wraps.

**Threat addressed.** Disclosure of stored data when the storage medium or its
copies leave the service boundary (physical media, leaked snapshot or backup).
The medium carries ciphertext rather than plaintext.

**Unconditional properties.**

- Encryption is always on. `check:` the encryption configuration is present in
  the module source with no condition on it, and a plan with default input
  shows it applied.
- The AWS-managed pattern exposes no caller KMS choice. `check:` the declared
  variables contain no KMS-related input of any kind (key ARN, key ID, key
  alias, or KMS option).
- The module provisions no key. `check:` the module source defines no KMS key
  resource.
- The stored data is ciphertext at rest. `assumption:` provider behavior at
  runtime; configuration evidence does not establish it.

**Forbidden by configuration.**

- Disabling required encryption. `check:` inexpressible — no variable carries
  an enable/disable choice.
- Switching key-ownership mode. `check:` inexpressible — no variable selects a
  key source; a caller wanting another mode selects a different module.

**Caller responsibilities.** None. `check:` the input surface contains no
encryption-related input to supply.

**Excluded threats.**

- Plaintext access by any principal the account authorizes to read through the
  service: the AWS-managed key decrypts for every authorized reader, so data
  access and key access cannot be separated. `assumption:` follows from
  AWS-managed key semantics.
- Caller-controlled revocation: the caller cannot disable the key to stop
  access. `check:` no key input exists to revoke.
- Access by the provider itself. `assumption:` outside the caller's control
  plane.

## Caller-provided KMS key

The module requires the caller to supply a KMS key identifier, encrypts the
storage resource with that key, and provisions no key of its own.

**Protected asset.** Data at rest on the storage resource the pattern wraps.
The separation property below additionally depends on the caller's key.

**Threat addressed.** The medium-disclosure threat above, plus separation of
data access from key access: a reader needs both service-level read permission
and KMS Decrypt on the caller's key, and the caller can revoke access by
disabling the key.

**Unconditional properties.**

- The caller-provided pattern requires a supplied key. `check:` the key
  identifier is a required input with no default; a plan that omits it fails.
- The supplied key is the key used. `check:` the encryption configuration
  references the caller's key and the module source names no other key.
- No key provisioning and no fallback. `check:` the module source defines no
  KMS key resource and contains no branch substituting another key source when
  the input is absent or unsuitable.
- Encryption is always on. `check:` the encryption configuration is present in
  the module source with no condition on it; no variable disables it.
- A reader without Decrypt is denied plaintext, and disabling the key revokes
  access. `assumption:` provider runtime semantics and the caller's key policy.
- No key-ownership mode switch. `check:` no variable selects a key source; a
  different mode means a different module.

**Forbidden by configuration.**

- Disabling required encryption. `check:` inexpressible — no variable carries
  an enable/disable choice.
- Switching key-ownership mode, to AWS-managed or pattern-managed. `check:`
  inexpressible — no variable selects a key source.

**Caller responsibilities.** Each is an external assumption; supplying a key
identifier alone demonstrates none of them.

- Supply a key that exists, is enabled, and lives in the region and account
  context the module deploys into. `assumption:`
- Grant the storage service and the principals that must read the data the KMS
  permissions they need through the key policy. `assumption:`
- Manage the key lifecycle — rotation, deletion, revocation — including
  disabling the key when access must stop. `assumption:`
- Keep the Decrypt grant as narrow as intended: a key policy that grants
  Decrypt broadly silently removes the separation property, and the module
  cannot detect it from the identifier. `assumption:`

**Excluded threats.**

- Caller key hygiene failures: a disabled or deleted key is an outage, and a
  broadly granted key removes the separation property; the module cannot verify
  either from an identifier. `check:` the module source has no mechanism that
  inspects the key's state or policy.
- Runtime enforcement beyond configuration: that readers without Decrypt are
  actually denied is provider semantics. `assumption:` not established by
  configuration evidence.

## Pattern-managed KMS key

The module always provisions and manages its own KMS key, encrypts the storage
resource with it, and exposes no caller key input.

**Protected asset.** Data at rest on the storage resource the pattern wraps,
plus the key material and its policy, both under the pattern's control.

**Threat addressed.** The medium-disclosure threat above, plus separation of
data access from key access with the key policy owned by the pattern, plus a
key lifecycle that holds without caller-supplied key hygiene.

**Unconditional properties.**

- The pattern-managed alternative owns its key lifecycle. `check:` the module
  source defines a KMS key resource with no condition on it, and the lifecycle
  attributes (rotation, pending-deletion window) are set in the source rather
  than exposed as variables.
- Encryption is always on. `check:` the encryption configuration is present in
  the module source with no condition on it; no variable disables it.
- No caller key choice. `check:` the declared variables contain no KMS key
  parameter, and the encryption configuration references only the module's key.
- The key policy is the pattern's, not the caller's. `check:` the key's policy
  document is defined in the module source, and no variable supplies one.
- The stored data is ciphertext at rest, and Decrypt is limited to what the key
  policy grants. `assumption:` provider runtime semantics.

**Forbidden by configuration.**

- Disabling required encryption. `check:` inexpressible — no variable carries
  an enable/disable choice.
- Switching key-ownership mode, such as supplying another key or opting into
  AWS-managed. `check:` inexpressible — no variable selects a key source.

**Caller responsibilities.** None for encryption or key lifecycle. `check:` no
encryption-related input exists.

**Excluded threats.**

- Access by any principal the pattern's key policy or the account's
  administrators grant Decrypt to. `assumption:` the pattern controls the
  policy's configuration, not the account's IAM.
- Destruction or disabling of the key by anyone holding KMS permissions in the
  account. `assumption:`
- Caller-timed revocation: rotation and revocation follow the pattern's
  lifecycle, not caller demand. `check:` no input schedules or triggers them.
