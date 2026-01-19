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
if [[ -n "${LLM_MOCK_RESPONSES_FILE:-}" ]]; then
  sep="<<<LLM>>>"
  tmp_file="$(mktemp)"
  found_sep=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $found_sep -eq 0 && "$line" == "$sep" ]]; then
      found_sep=1
      continue
    fi
    if [[ $found_sep -eq 0 ]]; then
      printf '%s\n' "$line"
    else
      printf '%s\n' "$line" >> "$tmp_file"
    fi
  done < "$LLM_MOCK_RESPONSES_FILE"
  mv "$tmp_file" "$LLM_MOCK_RESPONSES_FILE"
  exit 0
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
  LAST_OUT=$(PATH="$TMP_DIR:$PATH" LLM_MOCK_RESPONSE="$resp" "$ROOT_DIR/bin/shask" "$@" 2>"$stderr_file")
  LAST_STATUS=$?
  set -e
  LAST_ERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

run_asksh_tty() {
  local resp_file="$1"
  local user_input="$2"
  shift 2
  local stderr_file
  stderr_file="$(mktemp)"
  set +e
  LAST_OUT=$(ASKSH_TTY_INPUT="$user_input" PATH="$TMP_DIR:$PATH" LLM_MOCK_RESPONSES_FILE="$resp_file" python3 - "$ROOT_DIR/bin/shask" "$@" 2>"$stderr_file" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

cmd = [sys.argv[1]] + sys.argv[2:]
env = os.environ.copy()
master, slave = pty.openpty()
proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, env=env)
os.close(slave)

data = env.get("ASKSH_TTY_INPUT", "").encode()
if data:
    time.sleep(0.05)
    os.write(master, data)

out = bytearray()
while True:
    if proc.poll() is not None:
        try:
            while True:
                chunk = os.read(master, 1024)
                if not chunk:
                    break
                out.extend(chunk)
        except OSError:
            pass
        break
    r, _, _ = select.select([master], [], [], 0.1)
    if master in r:
        try:
            chunk = os.read(master, 1024)
        except OSError:
            break
        if not chunk:
            break
        out.extend(chunk)

sys.stdout.buffer.write(out)
sys.exit(proc.returncode or 0)
PY
)
  LAST_STATUS=$?
  set -e
  LAST_OUT=$(printf '%s\n' "$LAST_OUT" | tr -d '\r' | awk 'NF{last=$0} END{print last}')
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

# Test: NEED_MORE_INFO in TTY prompts and retries
resp_file="$(mktemp)"
cat <<'RESP' > "$resp_file"
NEED_MORE_INFO: which directory?
<<<LLM>>>
CMD: ls -la /tmp
WHY: list tmp
RESP
run_asksh_tty "$resp_file" $'/tmp\n' \"list files\"
assert_eq "ls -la /tmp" "$LAST_OUT" "tty returns command after clarification"
rm -f "$resp_file"

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
