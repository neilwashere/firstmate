#!/usr/bin/env bash
# End-user reproduction for the SILENT task-drop variant of the same overflow.
#
# usage: repro-silent-task-drop.sh <firstmate-root> <label>
#
# One long-lived task accumulates many still-open needs-decision notes. The
# folded open-decision set (not any single line) crosses Linux's 128 KiB
# MAX_ARG_STRLEN, so the per-task jq that carried it on argv could not exec. The
# failure was swallowed by an unchecked pipe, so the task disappeared from the
# snapshot and the published home summary went invalid (orphan_in_flight),
# which is what made the home read as unreadable/orphaned to Bearings.
set -u

ROOT_UNDER_TEST=$1
LABEL=$2

# shellcheck source=/dev/null
. "$ROOT_UNDER_TEST/tests/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-argv-drop)
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
HOME_DIR="$TMP_ROOT/portal-mate-home"
PARENT="$TMP_ROOT/captain-home"

mkdir -p "$HOME_DIR/state" "$HOME_DIR/data" "$HOME_DIR/config" \
  "$HOME_DIR/projects/portal" "$HOME_DIR/bin"
printf '# Seeded Firstmate home\n' > "$HOME_DIR/AGENTS.md"
printf 'portal-mate\n' > "$HOME_DIR/.fm-secondmate-home"
fm_git_init_commit "$HOME_DIR/projects/portal" >/dev/null 2>&1
cat > "$HOME_DIR/data/backlog.md" <<'EOF'
## In flight
- [ ] migration-run - Long-lived migration holding many captain decisions (repo: portal) (kind: ship) (since 2026-08-20)
- [ ] docs-pass - Ordinary follow-up task (repo: portal) (kind: ship) (since 2026-08-28)

## Queued

## Done
EOF
for task_id in migration-run docs-pass; do
  fm_write_meta "$HOME_DIR/state/$task_id.meta" \
    "window=fmtest:fm-$task_id" \
    "worktree=$HOME_DIR/projects/portal" \
    "project=portal" \
    "harness=claude" \
    "kind=ship" \
    "mode=no-mistakes" \
    "spawn_gen=fm.$task_id.123456"
done

# 60 still-open decisions, each note long but individually well under the
# per-argument limit: only the accumulated fold crosses it.
note=$(printf 'x%.0s' $(seq 1 2500))
i=1
while [ "$i" -le 60 ]; do
  printf 'needs-decision [key=migration-step-%s]: %s\n' "$i" "$note"
  i=$((i + 1))
done > "$HOME_DIR/state/migration-run.status"
printf 'working: drafting the release notes\n' > "$HOME_DIR/state/docs-pass.status"
for task_id in migration-run docs-pass; do
  gen=$("$ROOT_UNDER_TEST/bin/fm-busy-event.sh" arm "$HOME_DIR/state" "$task_id")
  "$ROOT_UNDER_TEST/bin/fm-busy-event.sh" apply "$HOME_DIR/state" "$task_id" idle \
    --gen "$gen" --source claude-hook --event stop
done

mkdir -p "$PARENT/state" "$PARENT/data" "$PARENT/config" "$PARENT/projects/portal"
printf '# Seeded Firstmate home\n' > "$PARENT/AGENTS.md"
fm_git_init_commit "$PARENT/projects/portal" >/dev/null 2>&1
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$PARENT/data/backlog.md"
printf -- '- portal-mate - portal domain (home: %s; scope: portal work; projects: portal; added 2026-08-28)\n' \
  "$HOME_DIR" > "$PARENT/data/secondmates.md"
fm_write_secondmate_meta "$PARENT/state/portal-mate.meta" \
  "$HOME_DIR" "fmtest:fm-portal-mate" portal claude

printf '=== %s ===\n' "$LABEL"
printf 'firstmate root under test : %s\n' "$ROOT_UNDER_TEST"
printf 'fm-fleet-snapshot.sh sha1 : %s\n' \
  "$(sha1sum "$ROOT_UNDER_TEST/bin/fm-fleet-snapshot.sh" | cut -d' ' -f1)"
printf 'status log bytes          : %s across 60 open decisions (MAX_ARG_STRLEN is 131072)\n\n' \
  "$(wc -c < "$HOME_DIR/state/migration-run.status")"

printf -- '--- 1. the secondmate publishes its own home summary -----------------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$HOME_DIR" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-home-summary-refresh.sh" 2>&1
printf 'writer exit: %s\n\n' "$?"
jq '{valid, invalidity_kind: .invalidity.kind, invalidity_ids: .invalidity.ids,
     reason: .reason,
     state: .state,
     tasks_seen: [.endpoints[].id],
     decisions_open_count: .counts.decisions_open}' \
  "$HOME_DIR/state/home-summary.json" 2>&1 || printf 'summary unreadable\n'

printf -- '\n--- 2. the same read straight from the producer (stderr shown) --------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$HOME_DIR" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-fleet-snapshot.sh" --secondmate-home-summary \
  > "$TMP_ROOT/direct.json" 2> "$TMP_ROOT/direct.err"
printf 'producer exit: %s\n' "$?"
printf 'producer stderr: %s\n' "$(cat "$TMP_ROOT/direct.err")"
jq '{valid, invalidity_kind: .invalidity.kind, tasks_seen: [.endpoints[].id],
     decisions_open_count: .counts.decisions_open}' "$TMP_ROOT/direct.json" 2>&1

printf -- '\n--- 3. what the captain sees in Bearings -----------------------------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$PARENT" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-bearings-snapshot.sh" 2>&1 \
  | sed -n '/^secondmates/,/^landed/p'

printf -- '\n--- 4. the child home as the parent aggregation reports it ------------\n'
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$ROOT_UNDER_TEST" FM_HOME="$PARENT" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$ROOT_UNDER_TEST/bin/fm-fleet-snapshot.sh" --json 2>/dev/null \
  | jq '.secondmate_current.records[] | {id, state: .current.state,
      reason: .current.reason,
      child_tasks: [.children[]? | .id],
      child_open_decisions: [.decisions_open[]? | .key] | length}' 2>&1

printf '\n'
