#!/usr/bin/env bash
# Red-check evidence for the three patterns. One promised encryption property
# per pattern is changed or removed in a temp copy of the module; the module's
# check.sh must then fail, and the pristine file is restored afterwards and
# verified byte-identical. The caller-provided example is also re-validated
# without its key, which must fail before any resource is created. Runs
# terraform init and validate only: no plan, no apply, no AWS credentials, no
# live resources.
set -u
cd "$(dirname "$0")"

failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

if ! command -v terraform >/dev/null 2>&1; then
  fail 'terraform not found: the mutation checks cannot run'
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# mutate_and_expect_fail: $1 = module dir, $2 = sed expression applied to the
# copy's main.tf, $3 = fragment of the check.sh FAIL message that must appear
mutate_and_expect_fail() {
  module="$1" expr="$2" label="$3"
  cp -a "$module" "$work/$module"
  cp "$work/$module/main.tf" "$work/main.tf.pristine"
  sed -i "$expr" "$work/$module/main.tf"
  out=$(cd "$work/$module" && ./check.sh 2>&1)
  status=$?
  cp "$work/main.tf.pristine" "$work/$module/main.tf"
  failed_line=$(printf '%s\n' "$out" | grep '^FAIL' | grep -F "$label" | head -1)
  other_fails=$(printf '%s\n' "$out" | grep '^FAIL' | grep -vF "$label")
  if [ "$status" -ne 0 ] && [ -n "$failed_line" ]; then
    pass "mutation in $module made the relevant check fail: $failed_line"
    if [ -n "$other_fails" ]; then
      printf '%s\n' "$other_fails" | sed 's/^/  also failed: /'
    fi
  elif [ "$status" -ne 0 ] && [ -n "$other_fails" ]; then
    fail "mutation in $module made other checks fail, not $label:"
    printf '%s\n' "$other_fails" | sed 's/^/  /'
  elif [ "$status" -ne 0 ]; then
    fail "mutation in $module: check.sh exited non-zero without any FAIL line:"
    printf '%s\n' "$out" | grep -v '^$' | head -4
  else
    fail "mutation in $module did not make any check fail (check.sh passed the mutated copy)"
  fi
  if diff -q "$work/$module/main.tf" "$module/main.tf" >/dev/null 2>&1; then
    pass "$module/main.tf restored byte-identical to the original"
  else
    fail "$module/main.tf was not restored byte-identical to the original"
  fi
}

# AWS-managed: change the promised AWS-managed algorithm to a KMS one.
mutate_and_expect_fail aws-managed-sse \
  's/sse_algorithm = "AES256"/sse_algorithm = "aws:kms"/' \
  'sse_algorithm = "AES256"'

# Caller-provided: remove the promised use of the supplied key.
mutate_and_expect_fail caller-provided-kms \
  '/kms_master_key_id/d' \
  'kms_master_key_id = var.kms_key_id'

# Pattern-managed: replace the promised use of the module's own key.
mutate_and_expect_fail pattern-managed-kms \
  's|aws_kms_key.storage.arn|"arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"|' \
  'kms_master_key_id = aws_kms_key.storage.arn'

# The caller-provided example without its key must fail before any resource
# is created.
cp -a example-caller-provided-kms "$work/example-caller-provided-kms"
cp "$work/example-caller-provided-kms/main.tf" "$work/example-main.tf.pristine"
sed -i '/kms_key_id/d' "$work/example-caller-provided-kms/main.tf"
out=$(cd "$work/example-caller-provided-kms" && terraform init -no-color >/dev/null 2>&1; terraform validate -no-color 2>&1)
status=$?
cp "$work/example-main.tf.pristine" "$work/example-caller-provided-kms/main.tf"
line=$(printf '%s\n' "$out" | grep -iE 'is required' | head -1 | sed 's/^[[:space:]]*//')
if [ "$status" -ne 0 ] && [ -n "$line" ]; then
  pass "caller-provided example without its key rejected before any resource is created: $line"
else
  fail 'caller-provided example without its key was accepted or failed unexpectedly:'
  printf '%s\n' "$out" | grep -v '^$' | head -4
fi
if diff -q "$work/example-caller-provided-kms/main.tf" example-caller-provided-kms/main.tf >/dev/null 2>&1; then
  pass 'example-caller-provided-kms/main.tf restored byte-identical to the original'
else
  fail 'example-caller-provided-kms/main.tf was not restored byte-identical to the original'
fi

if [ "$failures" -eq 0 ]; then
  printf 'mutation check passed: every mutated property made its check fail, every file was restored byte-identical, and the keyless example was rejected\n'
else
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
