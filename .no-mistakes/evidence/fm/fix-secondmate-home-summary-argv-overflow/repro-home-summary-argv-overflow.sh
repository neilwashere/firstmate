#!/usr/bin/env bash
# End-user reproduction for the secondmate home-summary argv overflow.
#
# usage: repro-home-summary-argv-overflow.sh <firstmate-root> <label>
#
# Seeds a realistic secondmate home whose in-flight task holds ONE oversized
# status line (a mirrored needs-decision note above Linux's 128 KiB
# MAX_ARG_STRLEN), publishes that home's summary with the real writer, and then
# renders the captain-facing parent surfaces (Bearings + fleet view) that read
# it. Run it against the base root and the fixed root to compare what a captain
# actually sees.
set -u

ROOT_UNDER_TEST=$1
LABEL=$2

# shellcheck source=/dev/null
. "$ROOT_UNDER_TEST/tests/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-argv-repro)
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'fixture pane\n> \n' ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/tmux"

NOW=2026-08-29T09:00:00Z
EPOCH=1787130000

CHILD="$TMP_ROOT/portal-mate-home"
PARENT="$TMP_ROOT/captain-home"

# --- the child secondmate home ---------------------------------------------
mkdir -p "$CHILD/state" "$CHILD/data" "$CHILD/config" "$CHILD/projects/portal" "$CHILD/bin"
printf '# Seeded Firstmate home\n' > "$CHILD/AGENTS.md"
printf 'portal-mate\n' > "$CHILD/.fm-secondmate-home"
fm_git_init_commit "$CHILD/projects/portal" >/dev/null 2>&1
cat > "$CHILD/data/backlog.md" <<'EOF'
## In flight
- [ ] release-gate - Ship the canary rollout gate (repo: portal) (kind: ship) (since 2026-08-28)
- [ ] docs-pass - Ordinary follow-up task (repo: portal) (kind: ship) (since 2026-08-28)

## Queued

## Done
EOF
fm_write_meta "$CHILD/state/release-gate.meta" \
  "window=fmtest:fm-release-gate" \
  "worktree=$CHILD/projects/portal" \
  "project=portal" \
  "harness=claude" \
  "kind=ship" \
  "mode=no-mistakes" \
  "spawn_gen=fm.release123456"
fm_write_meta "$CHILD/state/docs-pass.meta" \
  "window=fmtest:fm-docs-pass" \
  "worktree=$CHILD/projects/portal" \
  "project=portal" \
  "harness=claude" \
  "kind=ship" \
  "mode=no-mistakes" \
  "spawn_gen=fm.docs123456"

# One status line, no size bound: a mirrored remote reply payload appended whole.
long_detail=''
i=1
while [ "$i" -le 1600 ]; do
  long_detail="$long_detail canary step $i verified: latency 41ms, error budget intact, awaiting captain sign-off before widening the rollout."
  i=$((i + 1))
done
printf 'needs-decision [key=canary-rollout]: widen the canary to 50%%?%s\n' "$long_detail" \
  > "$CHILD/state/release-gate.status"
printf 'working: drafting the release notes\n' > "$CHILD/state/docs-pass.status"

# Both panes are idle (the agents stopped at their gates), so current state comes
# from the durable status log rather than a live pane read.
for task_id in release-gate docs-pass; do
  gen=$("$ROOT_UNDER_TEST/bin/fm-busy-event.sh" arm "$CHILD/state" "$task_id")
  "$ROOT_UNDER_TEST/bin/fm-busy-event.sh" apply "$CHILD/state" "$task_id" idle \
    --gen "$gen" --source claude-hook --event stop
done

STATUS_BYTES=$(wc -c < "$CHILD/state/release-gate.status")

# --- the captain's parent home, with that child registered ------------------
mkdir -p "$PARENT/state" "$PARENT/data" "$PARENT/config" "$PARENT/projects/portal"
printf '# Seeded Firstmate home\n' > "$PARENT/AGENTS.md"
fm_git_init_commit "$PARENT/projects/portal" >/dev/null 2>&1
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$PARENT/data/backlog.md"
printf -- '- portal-mate - portal domain (home: %s; scope: portal work; projects: portal; added 2026-08-28)\n' \
  "$CHILD" > "$PARENT/data/secondmates.md"
fm_write_secondmate_meta "$PARENT/state/portal-mate.meta" \
  "$CHILD" "fmtest:fm-portal-mate" portal claude

printf '=== %s ===\n' "$LABEL"
printf 'firstmate root under test : %s\n' "$ROOT_UNDER_TEST"
printf 'fm-fleet-snapshot.sh sha1 : %s\n' \
  "$(sha1sum "$ROOT_UNDER_TEST/bin/fm-fleet-snapshot.sh" | cut -d' ' -f1)"
printf 'one status line, bytes    : %s (MAX_ARG_STRLEN is 131072)\n\n' "$STATUS_BYTES"

printf -- '--- 1. the secondmate publishes its own home summary -----------------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$CHILD" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-home-summary-refresh.sh" 2>&1
printf 'writer exit: %s\n' "$?"
printf '\npublished %s:\n' "$CHILD/state/home-summary.json"
jq '{schema, valid, invalidity_kind: .invalidity.kind,
     orphan_in_flight: (.invalidity.orphan_in_flight // []),
     endpoint_ids: [.endpoints[].id],
     decisions_open: [.decisions_open[] | {id, key, verb, note_bytes: (.summary | length)}]}' \
  "$CHILD/state/home-summary.json" 2>&1 || printf 'summary unreadable\n'

printf -- '\n--- 2. what the captain sees in Bearings -----------------------------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$PARENT" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-bearings-snapshot.sh" 2>&1 \
  | sed -n '1,60p'

printf -- '\n--- 3. what the captain sees in the fleet view -----------------------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$PARENT" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-fleet-view.sh" 2>&1 | sed -n '1,40p'

printf -- '\n--- 4. the child home rows inside the parent snapshot ----------------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$PARENT" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-fleet-snapshot.sh" --json 2>/dev/null \
  | jq '.secondmate_current.records[] | {id, state: .current.state, reason: .current.reason,
      invalidity_kind: .invalidity.kind,
      children: [.children[]? | {id, state}],
      open_decisions: [.parent_event.open_decisions[]? | .key]}' 2>&1

printf '\n'
