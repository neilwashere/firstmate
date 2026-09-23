#!/usr/bin/env bash
# The other half of the change under test: what the supervising turn still gets
# woken for. Same hermetic firstmate home and same real bin/fm-watch.sh as
# held-lane-noise-demo.sh, one supervision round per variant, each variant being
# a lane the new suppression must NOT swallow.
#
# Usage: FM_DEMO_REPO=<worktree> still-alerts-demo.sh
set -u

REPO=${FM_DEMO_REPO:?set FM_DEMO_REPO to the firstmate worktree}

# shellcheck source=/dev/null
. "$REPO/tests/wake-helpers.sh"
# shellcheck source=/dev/null
. "$REPO/bin/fm-classify-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-still-alerts-demo)
WATCH="$REPO/bin/fm-watch.sh"
DRAIN="$REPO/bin/fm-wake-drain.sh"
WINDOW='crew:ship-docs'
TASK='ship-docs'
KEY=$(printf '%s' "$WINDOW" | tr ':/.' '___')
PANE_TEXT='waiting at the gate'
IDLE_STATE='state: working · source: status-log · still tidying the branch'
WORKING_STATE='state: working · source: run-step · ci running'

size_of() { LC_ALL=C wc -c < "$1" | tr -d '[:space:]'; }
file_mtime() { stat -c %Y "$1" 2>/dev/null; }
seen_sig() {
  printf 'v2\t%s\t%s@%s' "$(status_observed_signature "$1")" "$(size_of "$1")" \
    "$(_fm_open_decisions_file_ident "$1")"
}
wait_poll_cycle() {  # <state> <pid> [limit]
  local state=$1 pid=$2 limit=${3:-300} beat first now i=0
  beat="$state/.last-watcher-beat"
  rm -f "$beat"
  first=''
  while [ "$i" -lt "$limit" ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    first=$(file_mtime "$beat"); [ -n "$first" ] && break
    sleep 0.1; i=$((i + 1))
  done
  while [ "$i" -lt "$limit" ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    now=$(file_mtime "$beat")
    [ -n "$now" ] && [ "$now" != "$first" ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
reap() { kill "$1" 2>/dev/null || true; wait_for_exit "$1" 100 >/dev/null 2>&1 || true; }

# One hermetic home: an already-surfaced, unchanged, idle crew pane whose worker
# line explains nothing, plus an In flight backlog row.
build_home() {  # <name>
  DIR=$(make_case "$1"); STATE="$DIR/state"; OUT="$DIR/watch.out"; OFFSET=0
  mkdir -p "$DIR/config" "$DIR/data"
  printf '%s' "$PANE_TEXT" > "$DIR/pane.txt"
  printf 'window=%s\nkind=ship\nharness=grok\nbackend=tmux\n' "$WINDOW" > "$STATE/$TASK.meta"
  printf 'working: still tidying the branch\n' > "$STATE/$TASK.status"
  printf '%s' "$(seen_sig "$STATE/$TASK.status")" > "$STATE/.seen-${TASK}_status"
  printf '%s' "$(hash_text "$PANE_TEXT")" > "$STATE/.hash-$KEY"
  printf '1\n' > "$STATE/.count-$KEY"
  printf '%s' "$(hash_text "$PANE_TEXT")" > "$STATE/.stale-$KEY"
  cp "$REPO/.tasks.toml" "$DIR/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$DIR/data/backlog.md"
  ( cd "$DIR" && tasks-axi add "$TASK" 'refresh the architecture docs' --file data/backlog.md ) >/dev/null
  ( cd "$DIR" && tasks-axi start "$TASK" --file data/backlog.md ) >/dev/null
}

hold_for_captain() {
  FM_HOME="$DIR" FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DIR/data" \
    FM_CONFIG_OVERRIDE="$DIR/config" "$REPO/bin/fm-captain-hold.sh" hold "$TASK" \
    --reason 'awaiting the captain on whether to land the docs rewrite' >/dev/null 2>&1
}

answer_and_release() {
  printf 'go ahead and land it\n' > "$DIR/decision.txt"
  FM_HOME="$DIR" FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DIR/data" \
    FM_CONFIG_OVERRIDE="$DIR/config" "$REPO/bin/fm-captain-hold.sh" answer "$TASK" \
    --decision-file "$DIR/decision.txt" --release >/dev/null 2>&1
}

ack_cycle() {
  local err sequence generation
  err="$STATE/.demo-drain.err"
  FM_STATE_OVERRIDE="$STATE" "$DRAIN" >/dev/null 2> "$err" || true
  sequence=$(sed -n 's/.*--ack-through \([0-9][0-9]*\) --recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$err")
  generation=$(sed -n 's/.*--ack-through [0-9][0-9]* --recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$err")
  rm -f "$err"
  [ -n "$sequence" ] && [ -n "$generation" ] || return 0
  FM_STATE_OVERRIDE="$STATE" "$DRAIN" --ack-through "$sequence" \
    --recovery-generation "$generation" >/dev/null 2>&1 || true
}

round() {  # <crew-state> -> prints what the watcher surfaced, or nothing
  local verdict=$1 pid cycles=0 exited=0 new
  PATH="$DIR/fakebin:$PATH" FM_FAKE_TMUX_WINDOW="$WINDOW" FM_FAKE_TMUX_CAPTURE="$DIR/pane.txt" \
    FM_FAKE_TMUX_CURRENT_COMMAND=grok FM_FAKE_CREW_STATE="$verdict" \
    FM_WATCH_HANDLING_SUCCESSOR=1 \
    FM_HOME="$DIR" FM_DATA_OVERRIDE="$DIR/data" FM_CONFIG_OVERRIDE="$DIR/config" \
    FM_STATE_OVERRIDE="$STATE" FM_CREW_STATE_BIN="$DIR/fakebin/fm-crew-state.sh" \
    FM_STALE_ESCALATE_SECS=1 FM_PAUSE_RESURFACE_SECS=999 \
    FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
    "$WATCH" >> "$OUT" 2>&1 &
  pid=$!
  while [ "$cycles" -lt 3 ]; do
    if ! wait_poll_cycle "$STATE" "$pid" 300; then exited=1; break; fi
    cycles=$((cycles + 1))
  done
  [ "$exited" -eq 1 ] || reap "$pid"
  new=$(tail -c "+$((OFFSET + 1))" "$OUT" 2>/dev/null | sed '/^$/d')
  OFFSET=$(size_of "$OUT")
  if [ -n "$new" ]; then printf '%s\n' "$new"; fi
  ack_cycle
}

report() {  # <variant> <expectation> <surfaced-text>
  printf -- '--- %s\n' "$1"
  printf '    must still alert: %s\n' "$2"
  if [ -n "$3" ]; then
    printf '    supervisor woken: %s\n' "$3"
  else
    printf '    supervisor woken: (nothing surfaced)\n'
  fi
  printf '    wedge escalations on record: %s\n\n' \
    "$(cat "$STATE/.wedge-escalations-$KEY" 2>/dev/null || echo '(none)')"
}

echo '================================================================'
echo 'STILL ALERTS - lanes the authorised suppression must not swallow'
echo '================================================================'
echo "same unchanged idle pane and same real bin/fm-watch.sh as the held-lane"
echo "transcript; one supervision round each, FM_STALE_ESCALATE_SECS=1"
echo

build_home open-row
report 'backlog row In flight, not held (nothing explains the quiet)' \
  'possible wedge' "$(round "$IDLE_STATE")"

build_home held-but-working
hold_for_captain
report 'row held for the captain, but the crew IS working (run-step)' \
  'possible wedge - a working task that stops responding is the real wedge' \
  "$(round "$WORKING_STATE")"

build_home released-hold
hold_for_captain
printf '    (first round with the hold live, expected silent: "%s")\n' "$(round "$IDLE_STATE")"
answer_and_release
report 'the captain answered and released the hold: newly actionable' \
  'possible wedge again, within one FM_STALE_ESCALATE_SECS' \
  "$(round "$IDLE_STATE")"

build_home changed-pane
hold_for_captain
printf '    (first round with the hold live, expected silent: "%s")\n' "$(round "$IDLE_STATE")"
printf 'the worker printed something new' > "$DIR/pane.txt"
report 'held lane whose pane changed: a new sighting' \
  'the plain first-sight stale wake' "$(round "$IDLE_STATE")"

echo '=== end of transcript ==='
