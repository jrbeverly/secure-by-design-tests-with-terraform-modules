#!/usr/bin/env bash
# Configuration-level check for the pattern-managed KMS pattern. Static checks
# use only bash and core utilities. The prohibited-choice attempts run
# terraform init and terraform validate on throwaway consumer configs in a
# temp dir: no plan, no apply, no AWS credentials, no live resources. The
# locked aws provider binary is installed once into the terraform plugin cache
# (TF_PLUGIN_CACHE_DIR) when the check first runs.
set -u
cd "$(dirname "$0")"

failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

# Declared inputs: exactly bucket_name, nothing else.
declared=$(grep -Eo '^variable "[a-z_]+"' variables.tf | sort -u || true)
if [ "$declared" = 'variable "bucket_name"' ]; then
  pass 'declared inputs: bucket_name (nothing else)'
else
  fail "declared inputs are: $(printf '%s ' "$declared")— expected only variable \"bucket_name\""
fi

# No declared input mentions encryption, keys, KMS, SSE, or an enable/disable switch.
tokens=$(grep -nEiw 'kms|key|encrypt|sse|enable|disable' variables.tf || true)
if [ -z "$tokens" ]; then
  pass 'no declared input carries an encryption or key-related choice'
else
  fail 'variables.tf mentions a security-related token:'
  printf '%s\n' "$tokens"
fi

# The module provisions its own key, unconditionally, exactly once.
count=$(grep -REo 'resource "aws_kms_key"' --include='*.tf' . | wc -l)
if [ "$count" -eq 1 ]; then
  pass 'module provisions exactly one KMS key resource'
else
  fail "expected exactly one aws_kms_key resource; found $count"
fi

# Lifecycle attributes are set in the source, not exposed as variables.
rotation=$(grep -n 'enable_key_rotation' main.tf || true)
window=$(grep -n 'deletion_window_in_days' main.tf || true)
if [ -n "$rotation" ] && printf '%s\n' "$rotation" | grep -q 'enable_key_rotation[[:space:]]*=[[:space:]]*true' \
  && [ -n "$window" ]; then
  pass "declared lifecycle: $(printf '%s' "$rotation" | sed 's/^[0-9]*: *//'), $(printf '%s' "$window" | sed 's/^[0-9]*: *//')"
else
  fail 'expected enable_key_rotation = true and a deletion_window_in_days value in main.tf'
fi
if printf '%s\n' "$(grep -nEiw 'rotat|delet' variables.tf || true)" | grep -q .; then
  fail 'lifecycle attributes appear in variables.tf: they must be fixed in the source'
else
  pass 'lifecycle attributes are not caller-controllable'
fi

# The key policy is defined in the module source; no variable supplies one.
policy=$(grep -n 'policy[[:space:]]*=' main.tf || true)
if [ -n "$policy" ] && ! printf '%s\n' "$policy" | grep -q 'var\.'; then
  pass "key policy is defined in the module source: $(printf '%s' "$policy" | sed 's/^[0-9]*: *//')"
else
  fail 'expected a key policy assignment in main.tf that references no variable'
fi

# Encryption is configured once, unconditionally, with the module's own key.
line=$(grep -n 'sse_algorithm' main.tf || true)
if [ -n "$line" ] \
  && [ "$(printf '%s\n' "$line" | wc -l)" -eq 1 ] \
  && printf '%s\n' "$line" | grep -q 'sse_algorithm[[:space:]]*=[[:space:]]*"aws:kms"'; then
  pass "encryption uses a customer-managed KMS key: $(printf '%s' "$line" | sed 's/^[0-9]*: *//')"
else
  fail "expected exactly one sse_algorithm = \"aws:kms\" line; got: $line"
fi

line=$(grep -n 'kms_master_key_id' main.tf || true)
if [ -n "$line" ] \
  && [ "$(printf '%s\n' "$line" | wc -l)" -eq 1 ] \
  && printf '%s\n' "$line" | grep -q 'kms_master_key_id[[:space:]]*=[[:space:]]*aws_kms_key.storage.arn'; then
  pass "the module's key is the key used: $(printf '%s' "$line" | sed 's/^[0-9]*: *//')"
else
  fail "expected exactly one kms_master_key_id = aws_kms_key.storage.arn line; got: $line"
fi

# Every resource is unconditional: the key and encryption cannot be skipped.
hits=$(grep -RnE '^[[:space:]]*(count|for_each)[[:space:]]*=' --include='*.tf' . || true)
if [ -z "$hits" ]; then
  pass 'resources are unconditional (no count, no for_each)'
else
  fail 'conditional configuration found:'
  printf '%s\n' "$hits"
fi

# Resource inventory: the key, the bucket, and its SSE configuration.
expected=$(printf 'resource "aws_kms_key"\nresource "aws_s3_bucket"\nresource "aws_s3_bucket_server_side_encryption_configuration"')
resources=$(grep -REo 'resource "aws_[a-z0-9_]+"' --include='*.tf' . | sed 's/^[^:]*://' | sort -u || true)
if [ "$resources" = "$expected" ]; then
  pass 'module defines exactly the key, the bucket, and its SSE configuration'
else
  fail 'unexpected resource set:'
  printf '%s\n' "$resources"
fi

# Prohibited-choice attempts: each must be rejected by terraform before any
# resource operation. Consumers are generated under a temp dir and removed
# when the check exits.
if ! command -v terraform >/dev/null 2>&1; then
  fail 'terraform not found: the prohibited-choice attempts cannot run'
else
  export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  write_consumer() { # $1 = dir, $2 = module block body
    printf 'module "encrypted_bucket" {\n  source = "%s"\n%s}\n' "$(pwd)" "$2" > "$1/main.tf"
  }

  attempt_rejected() { # $1 = label, $2 = module block body
    dir="$tmp/$(printf '%s' "$1" | tr ' ' '-')"
    mkdir -p "$dir"
    write_consumer "$dir" "$2"
    out=$(cd "$dir" && terraform init -no-color 2>&1; terraform validate -no-color 2>&1)
    status=$?
    line=$(printf '%s\n' "$out" | grep -iE 'unsupported argument|is required' | head -1 | sed 's/^[[:space:]]*//')
    if [ "$status" -ne 0 ] && [ -n "$line" ]; then
      pass "$1 rejected before any resource is created: $line"
    elif [ "$status" -ne 0 ]; then
      fail "$1 failed for an unexpected reason (not the prohibited-choice rejection):"
      printf '%s\n' "$out" | grep -v '^$' | head -4
    else
      fail "$1 was accepted: the prohibited choice is expressible"
    fi
  }

  # A caller choice to switch to caller-provided key mode must be rejected.
  attempt_rejected 'switching to caller-provided key mode (kms_key_id)' \
    '  bucket_name = "check-bucket"
  kms_key_id  = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
'

  # A caller choice to disable encryption must be rejected.
  attempt_rejected 'disabling encryption (encryption_enabled = false)' \
    '  bucket_name        = "check-bucket"
  encryption_enabled = false
'

  # A caller choice to switch to AWS-managed key mode must be rejected.
  attempt_rejected 'switching to AWS-managed key mode (use_aws_managed_key = true)' \
    '  bucket_name         = "check-bucket"
  use_aws_managed_key = true
'

  # Control: the minimal valid consumer must be accepted, so the rejections
  # above are attributable to the prohibited choice, not to the harness.
  dir="$tmp/control"
  mkdir -p "$dir"
  write_consumer "$dir" \
    '  bucket_name = "check-bucket"
'
  out=$(cd "$dir" && terraform init -no-color >/dev/null 2>&1; terraform validate -no-color 2>&1)
  if [ "$?" -eq 0 ]; then
    pass 'control consumer (bucket_name only) validates: Success!'
  else
    fail 'control consumer did not validate:'
    printf '%s\n' "$out" | grep -v '^$' | head -4
  fi
fi

if [ "$failures" -eq 0 ]; then
  printf 'check passed: the pattern provisions and uses its own key with a fixed lifecycle, and no caller choice can replace the key, disable encryption, or switch key mode\n'
else
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
