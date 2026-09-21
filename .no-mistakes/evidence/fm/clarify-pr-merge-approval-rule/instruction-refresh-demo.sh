#!/usr/bin/env bash
# Evidence demo: the reworded hard rule 2 as it is actually DELIVERED to a
# running firstmate.
#
# bin/fm-session-start.sh re-emits the complete on-disk AGENTS.md as the current
# instruction contract when a Pi session rebuilds context and the file has
# drifted from the baseline the session started with. This drives that real
# entrypoint in an isolated fixture home: baseline taken with the pre-change
# AGENTS.md (base 43bf6d3), then the branch's AGENTS.md (b26e616) put in place,
# then a Pi compact rebuild - so the transcript shows the instruction the agent
# receives after this change lands.
set -u

REPO=/home/neil_keith_com/.no-mistakes/worktrees/8d4e8e2579c7/01M31VA41A9SCJE21VA9HDE75C
BASE_AGENTS=${1:?usage: instruction-refresh-demo.sh <base-AGENTS.md>}
export PATH="/home/neil_keith_com/.nvm/versions/node/v24.18.0/bin:$PATH"

# The session-start fixture builders (new_world, make_fake_toolchain,
# make_fake_ps_harness, run_pi_session_start) live in the suite that owns them,
# so reuse them verbatim: take the file up to its test-invocation list, which
# defines every helper and runs none of the cases.
#
# tests/lib.sh derives ROOT from its own directory, so the slice has to sit in a
# tests/ dir beside it. The repo is never written to: a throwaway symlink mirror
# of the code root is built in a temp dir and the slice is dropped in there.
MIRROR=$(mktemp -d "${TMPDIR:-/tmp}/fm-mirror.XXXXXX")
trap 'rm -rf "$MIRROR"' EXIT
mkdir -p "$MIRROR/tests"
for entry in $(ls -A "$REPO"); do
  case "$entry" in tests | .git) continue ;; esac
  ln -s "$REPO/$entry" "$MIRROR/$entry"
done
for entry in "$REPO"/tests/*; do
  ln -s "$entry" "$MIRROR/tests/${entry##*/}"
done
SLICE="$MIRROR/tests/session-start-helpers.sh"
python3 - "$REPO/tests/fm-session-start.test.sh" "$SLICE" <<'PY'
import sys
from pathlib import Path
src, dest = sys.argv[1:3]
lines = Path(src).read_text().split('\n')
# The first bare `test_name` line is the start of the invocation list; every
# helper and test definition sits above it.
cut = next(i for i, line in enumerate(lines)
           if line.startswith('test_') and '(' not in line and '{' not in line)
Path(dest).write_text('\n'.join(lines[:cut]) + '\n')
PY
# shellcheck source=/dev/null
. "$SLICE"

section() { printf '\n=== %s ===\n' "$1"; }

rec=$(new_world instruction-refresh-demo)
IFS='|' read -r root home fakebin <<EOF
$rec
EOF
make_fake_toolchain "$fakebin"
make_fake_ps_harness "$fakebin" pi

section 'baseline: the session starts on the PRE-change instruction contract'
cp "$BASE_AGENTS" "$root/AGENTS.md"
grep -n 'Never merge a PR' "$root/AGENTS.md"
FM_FAKE_HARNESS=pi run_pi_session_start "$home" "$root" "$fakebin:$BASE_PATH" \
  --source startup > "$home/startup.out" 2>&1 \
  || { echo "session start failed"; tail -20 "$home/startup.out"; exit 1; }
printf 'baseline recorded: %s\n' \
  "$(sed -n 2p "$home/state/.session-start-agents-baseline")"

section 'the branch lands: AGENTS.md now carries the qualified rule'
cp "$REPO/AGENTS.md" "$root/AGENTS.md"
grep -n 'Never merge a PR' "$root/AGENTS.md"

section 'a Pi context rebuild: what the agent is handed'
FM_FAKE_HARNESS=pi run_pi_session_start "$home" "$root" "$fakebin:$BASE_PATH" \
  --reemit --source compact > "$home/compact.out" 2>&1 \
  || { echo "compact rebuild failed"; tail -20 "$home/compact.out"; exit 1; }
awk '/^CURRENT AGENTS.md - INSTRUCTION REFRESH$/,0' "$home/compact.out" |
  sed -n '1,8p;/^Hard rules, in priority order:/,/^3\. \*\*Never tear down/p'

section 'verdict'
delivered=$(awk '/^CURRENT AGENTS.md - INSTRUCTION REFRESH$/,0' "$home/compact.out")
if printf '%s' "$delivered" | grep -qF '2. **Never merge a PR without approval from the captain.**' \
  && ! printf '%s' "$delivered" | grep -qF "2. **Never merge a PR without the captain's explicit word.**"; then
  printf 'PASS: the emitted instruction contract carries the qualified merge rule.\n'
else
  printf 'FAIL: the emitted instruction contract did not carry the qualified merge rule.\n'
  exit 1
fi
