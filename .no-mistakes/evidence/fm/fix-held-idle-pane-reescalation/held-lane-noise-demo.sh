#!/usr/bin/env bash
# Product-level demonstration of the change under test (branch
# fm/fix-held-idle-pane-reescalation): what a supervising turn actually SEES for
# a crewmate pane that is quiet because its own backlog row is held for the
# captain.
#
# The scenario is one real bin/fm-watch.sh process per "supervision round",
# driven against a hermetic firstmate home:
#   - one tmux-backed crew window whose pane content never changes (already
#     surfaced once, the suppressor holds its hash), so every poll goes straight
#     to the wedge timer;
#   - a worker status log whose last line ("working: still tidying the branch")
#     explains nothing;
#   - the crew's current state showing no positive working evidence;
#   - the task's own backlog row held for the captain, written by the real
#     bin/fm-captain-hold.sh.
# FM_STALE_ESCALATE_SECS=1 puts every round at the escalation threshold at once;
# the shipped default only changes how long that takes (240s).
#
# What each round prints is the watcher's own supervisor-facing output: the wake
# reason it emits, plus the durable wake queue a supervising turn drains.
#
# Usage: FM_DEMO_REPO=<worktree> held-lane-noise-demo.sh "<label>"
set -u

REPO=${FM_DEMO_REPO:?set FM_DEMO_REPO to the firstmate worktree}
LABEL=${1:-run}

# shellcheck source=/dev/null
. "$REPO/tests/wake-helpers.sh"
# shellcheck source=/dev/null
. "$REPO/bin/fm-classify-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-held-lane-demo)
WATCH="$REPO/bin/fm-watch.sh"
DRAIN="$REPO/bin/fm-wake-drain.sh"
WINDOW='crew:ship-docs'
TASK='ship-docs'
KEY=$(printf '%s' "$WINDOW" | tr ':/.' '___')
PANE_TEXT='waiting at the gate'

size_of() { LC_ALL=C wc -c < "$1" | tr -d '[:space:]'; }
file_mtime() { stat -c %Y "$1" 2>/dev/null; }
set_mtime() { touch -t "$(date -d "@$1" +%Y%m%d%H%M.%S)" "$2"; }
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

stale_wakes() { awk -F '\t' -v w="$WINDOW" '$3 == "stale" && $4 == w { n++ } END { print n + 0 }' \
  "$STATE/.wake-queue" 2>/dev/null || echo 0; }

# --- the home -----------------------------------------------------------------
DIR=$(make_case held-lane); STATE="$DIR/state"; OUT="$DIR/watch.out"
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
FM_HOME="$DIR" FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DIR/data" FM_CONFIG_OVERRIDE="$DIR/config" \
  "$REPO/bin/fm-captain-hold.sh" hold "$TASK" \
  --reason 'awaiting the captain on whether to land the docs rewrite' >/dev/null 2>&1 \
  || { echo "FATAL: could not record the captain hold"; exit 1; }

# Backdate the hold's own recorded set time by two days, so the transcript shows
# the age a recheck publishes for a hold the captain has really been sitting on.
HELD_SINCE=$(( $(date +%s) - 172800 ))
HELD_STAMP=$(date -u -d "@$HELD_SINCE" +%Y-%m-%dT%H:%M:%SZ)
sed -i "s/^  Captain hold set: .*Z\$/  Captain hold set: $HELD_STAMP/" "$DIR/data/backlog.md"

echo "================================================================"
echo "$LABEL"
echo "================================================================"
echo "crew window        : $WINDOW  (pane content unchanged every poll)"
echo "worker status line : $(cat "$STATE/$TASK.status")"
echo "crew current state : state: working - source: status-log - still tidying the branch"
echo "backlog row        : $(grep -A 3 -F "$TASK" "$DIR/data/backlog.md" | sed -n '1,4p' | tr '\n' '|')"
echo

OFFSET=0
round() {  # <label> <pause-resurface-secs>
  local label=$1 resurface=$2 pid cycles=0 exited=0 before after new
  before=$(stale_wakes)
  PATH="$DIR/fakebin:$PATH" FM_FAKE_TMUX_WINDOW="$WINDOW" FM_FAKE_TMUX_CAPTURE="$DIR/pane.txt" \
    FM_FAKE_TMUX_CURRENT_COMMAND=grok \
    FM_FAKE_CREW_STATE='state: working · source: status-log · still tidying the branch' \
    FM_WATCH_HANDLING_SUCCESSOR=1 \
    FM_HOME="$DIR" FM_DATA_OVERRIDE="$DIR/data" FM_CONFIG_OVERRIDE="$DIR/config" \
    FM_STATE_OVERRIDE="$STATE" FM_CREW_STATE_BIN="$DIR/fakebin/fm-crew-state.sh" \
    FM_STALE_ESCALATE_SECS=1 FM_PAUSE_RESURFACE_SECS="$resurface" \
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
  after=$(stale_wakes)
  printf -- '--- %s\n' "$label"
  if [ -n "$new" ]; then
    printf 'watcher surfaced and exited, waking the supervisor with:\n'
    printf '    %s\n' "$new"
  else
    printf 'watcher stayed running: nothing surfaced, no supervising turn spent\n'
  fi
  printf 'wake queue entries for this window: %s (was %s)\n' "$after" "$before"
  printf 'wedge escalation count on record   : %s\n' \
    "$(cat "$STATE/.wedge-escalations-$KEY" 2>/dev/null || echo '(none)')"
  if [ "$after" -gt "$before" ]; then
    printf 'what the supervising turn drains  :\n'
    FM_STATE_OVERRIDE="$STATE" "$DRAIN" 2>/dev/null | sed -n '1,12p' | sed 's/^/    /'
    ack_cycle
  fi
  echo
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

round 'supervision round 1 (idle threshold reached)' 999
round 'supervision round 2 (same unchanged pane)' 999
round 'supervision round 3 (same unchanged pane)' 999

echo '--- and then the long bounded recheck the absorb still owes'
if [ -e "$STATE/.waiting-since-$KEY" ]; then
  echo "settled-wait record on disk: state/.waiting-since-$KEY"
  echo "  identity: $(cat "$STATE/.waiting-since-$KEY")"
  echo "aging it past FM_PAUSE_RESURFACE_SECS (240s here, 14400s shipped default)"
  set_mtime "$(( $(date +%s) - 5000 ))" "$STATE/.waiting-since-$KEY"
  round 'supervision round 4 (recheck cadence elapsed)' 240
else
  echo 'no settled-wait record exists: this watcher has no bounded recheck for a'
  echo 'held lane at all, which is why the rounds above keep escalating instead.'
fi

echo '=== end of transcript ==='
