#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Stub llm to return a mocked response for deterministic tests
cat <<'STUB' > "$TMP_DIR/llm"
#!/usr/bin/env bash
if [[ -n "${LLM_CAPTURE_ARGS:-}" ]]; then
  printf '%s\n' "$@" > "$LLM_CAPTURE_ARGS"
fi
if [[ -n "${LLM_MOCK_RESPONSE:-}" ]]; then
  printf '%s' "$LLM_MOCK_RESPONSE"
fi
STUB
chmod +x "$TMP_DIR/llm"

LAST_OUT=""
LAST_ERR=""
LAST_STATUS=0

run_asksh() {
  local resp="$1"
  shift
  local stderr_file
  stderr_file="$(mktemp)"
  set +e
  LAST_OUT=$(PATH="$TMP_DIR:$PATH" LLM_MOCK_RESPONSE="$resp" "$ROOT_DIR/bin/asksh" "$@" 2>"$stderr_file")
  LAST_STATUS=$?
  set -e
  LAST_ERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local context="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $context" >&2
    echo "  expected: [$expected]" >&2
    echo "  actual:   [$actual]" >&2
    exit 1
  fi
}

# Test: default output is command only
run_asksh $'CMD: ls -la\nWHY: list files' \"list files\"
assert_eq 0 "$LAST_STATUS" "default exits 0"
assert_eq "ls -la" "$LAST_OUT" "default outputs command only"

# Test: --explain includes explanation
run_asksh $'CMD: ls -la\nWHY: list files' --explain \"list files\"
assert_eq 0 "$LAST_STATUS" "--explain exits 0"
assert_eq $'ls -la\nlist files' "$LAST_OUT" "--explain outputs command and explanation"

# Test: NEED_MORE_INFO passes through and exits 2
run_asksh $'NEED_MORE_INFO: which directory?' \"list files\"
assert_eq 2 "$LAST_STATUS" "needs more info exits 2"
assert_eq "NEED_MORE_INFO: which directory?" "$LAST_OUT" "needs more info output"

# Test: --raw prints output verbatim
run_asksh $'hello\nworld' --raw \"list files\"
assert_eq 0 "$LAST_STATUS" "--raw exits 0"
assert_eq $'hello\nworld' "$LAST_OUT" "--raw prints verbatim"

# Test: no args prints usage to stderr and exits 1
run_asksh ""
assert_eq 1 "$LAST_STATUS" "no args exits 1"
if [[ "$LAST_ERR" != Usage:* ]]; then
  echo "FAIL: usage message not found" >&2
  echo "  stderr: [$LAST_ERR]" >&2
  exit 1
fi

echo "OK"
