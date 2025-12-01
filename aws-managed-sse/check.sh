#!/usr/bin/env bash
# Configuration-level check for the AWS-managed SSE pattern. Static checks use
# only bash and core utilities. The prohibited-choice attempts run terraform
# init and terraform validate on throwaway consumer configs in a temp dir:
# no plan, no apply, no AWS credentials, no live resources. The locked aws
# provider binary is installed once into the terraform plugin cache
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

# Encryption is configured once, unconditionally, with the AWS-managed algorithm.
line=$(grep -n 'sse_algorithm' main.tf || true)
if [ -n "$line" ] \
  && [ "$(printf '%s\n' "$line" | wc -l)" -eq 1 ] \
  && printf '%s\n' "$line" | grep -q 'sse_algorithm = "AES256"'; then
  pass "encryption is AWS-managed SSE: $(printf '%s' "$line" | sed 's/^[0-9]*: *//')"
else
  fail "expected exactly one sse_algorithm = \"AES256\" line; got: $line"
fi

# No KMS reference anywhere in module source: no caller key, no provisioned key.
hits=$(grep -RniE 'kms' --include='*.tf' . || true)
if [ -z "$hits" ]; then
  pass 'no KMS reference in module source (no caller key, no provisioned key)'
else
  fail 'KMS reference found:'
  printf '%s\n' "$hits"
fi

# Every resource is unconditional: encryption cannot be skipped at apply time.
hits=$(grep -RnE '^[[:space:]]*(count|for_each)[[:space:]]*=' --include='*.tf' . || true)
if [ -z "$hits" ]; then
  pass 'resources are unconditional (no count, no for_each)'
else
  fail 'conditional configuration found:'
  printf '%s\n' "$hits"
fi

# Resource inventory: the bucket and its SSE configuration, and no key resource.
expected=$(printf 'resource "aws_s3_bucket"\nresource "aws_s3_bucket_server_side_encryption_configuration"')
resources=$(grep -REo 'resource "aws_[a-z0-9_]+"' --include='*.tf' . | sed 's/^[^:]*://' | sort -u || true)
if [ "$resources" = "$expected" ]; then
  pass 'module defines exactly the bucket and its SSE configuration'
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

  # A caller choice to disable encryption must be rejected.
  attempt_rejected 'disabling encryption (encryption_enabled = false)' \
    '  bucket_name        = "check-bucket"
  encryption_enabled = false
'

  # A caller choice to switch to caller-provided key mode must be rejected.
  attempt_rejected 'switching to caller-provided key mode (kms_key_id)' \
    '  bucket_name = "check-bucket"
  kms_key_id  = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
'

  # A caller choice to switch to pattern-managed key mode must be rejected.
  attempt_rejected 'switching to pattern-managed key mode (use_pattern_managed_key = true)' \
    '  bucket_name             = "check-bucket"
  use_pattern_managed_key = true
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
  printf 'check passed: no caller choice can disable encryption, select a caller key, or request a separately managed key\n'
else
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
