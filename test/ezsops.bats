#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export HOME="$TEST_TMPDIR/home"
  export MOCK_BIN_DIR="$TEST_TMPDIR/bin"
  mkdir -p "$HOME" "$MOCK_BIN_DIR"
  export PATH="$MOCK_BIN_DIR:/bin:/usr/bin:/opt/homebrew/bin"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

write_mock_yq() {
  cat > "$MOCK_BIN_DIR/yq" <<'EOF'
#!/bin/bash
printf '%s\n' "${MOCK_YQ_KEYS:-data}"
EOF
  chmod +x "$MOCK_BIN_DIR/yq"
}

write_mock_sops_success() {
  cat > "$MOCK_BIN_DIR/sops" <<'EOF'
#!/bin/bash
cat "${MOCK_SOPS_OUTPUT_FILE}"
EOF
  chmod +x "$MOCK_BIN_DIR/sops"
}

write_mock_sops_failure() {
  cat > "$MOCK_BIN_DIR/sops" <<'EOF'
#!/bin/bash
printf '%s' "${MOCK_SOPS_STDOUT:-}" 
exit "${MOCK_SOPS_EXIT_CODE:-1}"
EOF
  chmod +x "$MOCK_BIN_DIR/sops"
}

write_mock_date() {
  cat > "$MOCK_BIN_DIR/date" <<'EOF'
#!/bin/bash
printf '%s\n' "${MOCK_DATE_OUTPUT:-2026-03-26}"
EOF
  chmod +x "$MOCK_BIN_DIR/date"
}

@test "encrypt writes output next to the source file" {
  mkdir -p "$TEST_TMPDIR/nested"
  printf 'data:\n  foo: bar\n' > "$TEST_TMPDIR/nested/secret.yml"
  printf 'encrypted-content\n' > "$TEST_TMPDIR/mock-sops-output.txt"
  export MOCK_SOPS_OUTPUT_FILE="$TEST_TMPDIR/mock-sops-output.txt"
  export MOCK_DATE_OUTPUT="2026-03-26"
  write_mock_yq
  write_mock_sops_success
  write_mock_date

  run /bin/bash -c 'printf "n\narn:aws:kms:eu-west-1:123456789012:key/test\nmain\n" | exec "$1" encrypt "$2"' -- "$PROJECT_ROOT/ezsops.sh" "$TEST_TMPDIR/nested/secret.yml"

  [ "$status" -eq 0 ]
  [ -f "$TEST_TMPDIR/nested/sops.secret.yml" ]
  [ ! -f "$PROJECT_ROOT/sops.secret.yml" ]
  run cat "$TEST_TMPDIR/nested/sops.secret.yml"
  [ "$output" = "encrypted-content" ]
}

@test "decrypt failure does not overwrite an existing plaintext file" {
  printf 'encrypted-placeholder\n' > "$TEST_TMPDIR/sops.secret.yml"
  printf 'original-content\n' > "$TEST_TMPDIR/secret.yml"
  export MOCK_SOPS_STDOUT="should-not-persist"
  export MOCK_SOPS_EXIT_CODE="1"
  write_mock_sops_failure

  run "$PROJECT_ROOT/ezsops.sh" decrypt "$TEST_TMPDIR/sops.secret.yml"

  [ "$status" -eq 1 ]
  run cat "$TEST_TMPDIR/secret.yml"
  [ "$output" = "original-content" ]
}

@test "encrypt fails early when yq is unavailable" {
  printf 'data:\n  foo: bar\n' > "$TEST_TMPDIR/secret.yml"
  printf 'encrypted-content\n' > "$TEST_TMPDIR/mock-sops-output.txt"
  export MOCK_SOPS_OUTPUT_FILE="$TEST_TMPDIR/mock-sops-output.txt"
  write_mock_sops_success

  run "$PROJECT_ROOT/ezsops.sh" encrypt "$TEST_TMPDIR/secret.yml"

  [ "$status" -eq 1 ]
  [ "$output" = "Error: Required command 'yq' is not installed or not in PATH." ]
}

@test "encrypt rejects using an empty saved KMS key list" {
  printf 'data:\n  foo: bar\n' > "$TEST_TMPDIR/secret.yml"
  printf 'encrypted-content\n' > "$TEST_TMPDIR/mock-sops-output.txt"
  export MOCK_SOPS_OUTPUT_FILE="$TEST_TMPDIR/mock-sops-output.txt"
  write_mock_yq
  write_mock_sops_success

  run /bin/bash -c 'printf "y\n" | exec "$1" encrypt "$2"' -- "$PROJECT_ROOT/ezsops.sh" "$TEST_TMPDIR/secret.yml"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: No pre-existing KMS keys were found"* ]]
}

@test "encrypt rejects out-of-range KMS selections" {
  printf 'data:\n  foo: bar\n' > "$TEST_TMPDIR/secret.yml"
  printf '2026-03-26\tarn:aws:kms:eu-west-1:123456789012:key/test\tmain\n' > "$HOME/.sops_kms_arns"
  printf 'encrypted-content\n' > "$TEST_TMPDIR/mock-sops-output.txt"
  export MOCK_SOPS_OUTPUT_FILE="$TEST_TMPDIR/mock-sops-output.txt"
  write_mock_yq
  write_mock_sops_success

  run /bin/bash -c 'printf "y\n9\n" | exec "$1" encrypt "$2"' -- "$PROJECT_ROOT/ezsops.sh" "$TEST_TMPDIR/secret.yml"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: Selection '9' is out of range."* ]]
}
