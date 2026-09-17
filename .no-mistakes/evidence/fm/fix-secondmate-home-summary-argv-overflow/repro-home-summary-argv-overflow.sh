#!/usr/bin/env bash
# Manual end-to-end reproduction for fm/fix-secondmate-home-summary-argv-overflow.
#
# Builds ONE identical firstmate home fixture whose single in-flight task has
# accumulated a large never-resolved open-decision fold in its status log, then
# publishes that home's summary and renders the human fleet view twice:
#   before/  - bin/fm-fleet-snapshot.sh from the base commit
#   after/   - bin/fm-fleet-snapshot.sh from the branch head
# Everything else (writer, renderer, sibling libs, fixture bytes) is identical.
#
# Usage: repro-home-summary-argv-overflow.sh <repo-root> <base-bin-dir> <out-dir>
set -u

REPO=$1
BASE_BIN=$2
OUT=$3

# shellcheck source=/dev/null
. "$REPO/tests/lib.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-argv-repro.XXXXXX")
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN" "$OUT"
cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'fixture pane\n> \n' ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/tmux"

NOW=2026-09-02T09:00:00Z
EPOCH=1788339600

seed_home() {  # <home>
  local home=$1 note i gen
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects/task"
  printf '# Seeded Firstmate home\n' > "$home/AGENTS.md"
  printf 'ccc-mate\n' > "$home/.fm-secondmate-home"
  fm_git_init_commit "$home/projects/task" >/dev/null 2>&1
  cat > "$home/data/backlog.md" <<'EOF'
## In flight
- [ ] held-task - Rollout gate awaiting captain calls (repo: firstmate) (kind: ship) (since 2026-08-28)

## Queued

## Done
EOF
  fm_write_meta "$home/state/held-task.meta" \
    "window=fmtest:fm-held-task" \
    "worktree=$home/projects/task" \
    "project=firstmate" \
    "harness=claude" \
    "kind=ship" \
    "mode=no-mistakes" \
    "spawn_gen=fm.held123456"
  gen=$("$REPO/bin/fm-busy-event.sh" arm "$home/state" held-task)
  "$REPO/bin/fm-busy-event.sh" apply "$home/state" held-task idle \
    --gen "$gen" --source claude-hook --event stop >/dev/null
  # A long-lived task keeps every still-open needs-decision note until it is
  # resolved, so the folded open-decision set grows without bound.
  note=$(printf 'z%.0s' $(seq 1 2500))
  i=1
  while [ "$i" -le 60 ]; do
    printf 'needs-decision [key=decision-%s]: %s\n' "$i" "$note"
    i=$((i + 1))
  done > "$home/state/held-task.status"
}

run_variant() {  # <label> <bin-dir>
  local label=$1 bin=$2 home dir
  home="$WORK/$label-home"
  dir="$OUT/$label"
  mkdir -p "$dir"
  seed_home "$home"
  printf '$ bin/fm-home-summary-refresh.sh   # publish this home summary (%s snapshot producer)\n' \
    "$label" > "$dir/transcript.txt"
  PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$REPO" FM_HOME="$home" \
    FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
    "$bin/fm-home-summary-refresh.sh" >> "$dir/transcript.txt" 2>&1
  printf 'exit status: %s\n\n' "$?" >> "$dir/transcript.txt"

  if [ -f "$home/state/home-summary.json" ]; then
    cp "$home/state/home-summary.json" "$dir/home-summary.json"
    printf '$ jq "{valid,invalidity,counts,endpoints,first_decision}" state/home-summary.json\n' \
      >> "$dir/transcript.txt"
    jq '{valid, invalidity, counts,
         endpoints: [.endpoints[] | {id, state: .current_state.state, source: .current_state.source}],
         first_decision: (.decisions_open[0] | {id, key, verb, summary_bytes: (.summary | length)})}' \
      "$home/state/home-summary.json" >> "$dir/transcript.txt" 2>&1
  else
    printf 'state/home-summary.json was never published\n' >> "$dir/transcript.txt"
  fi

  printf '\n$ bin/fm-fleet-view.sh   # what the captain actually reads\n' >> "$dir/transcript.txt"
  PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$REPO" FM_HOME="$home" \
    FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
    "$bin/fm-fleet-view.sh" >> "$dir/transcript.txt" 2>&1
  printf 'exit status: %s\n' "$?" >> "$dir/transcript.txt"

  printf '\n$ bin/fm-bearings-snapshot.sh   # the pick-up-where-I-left-off brief\n' \
    >> "$dir/transcript.txt"
  PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$REPO" FM_HOME="$home" \
    FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" FM_BEARINGS_NOW="$NOW" \
    "$bin/fm-bearings-snapshot.sh" 2>&1 \
    | sed -n '1,40p' >> "$dir/transcript.txt"
}

run_variant before "$BASE_BIN"
run_variant after "$REPO/bin"

rm -rf "$WORK"
printf 'wrote %s/before and %s/after\n' "$OUT" "$OUT"
