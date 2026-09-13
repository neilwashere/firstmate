#!/usr/bin/env bash
# Focused check for the parent-side activity-scan transport bound.
#
# fm-fleet-snapshot.sh's parent activity window is operator-settable
# (FM_SNAPSHOT_PARENT_ACTIVITY_BYTES). Raised above Linux's 128 KiB
# MAX_ARG_STRLEN, the JSON-encoded scan of a mirrored remote payload line used to
# be handed to jq as one exec argument, which fails the whole registered
# secondmate aggregation - the captain then gets NO snapshot and no Bearings at all.
#
# usage: activity-bound-check.sh <repo-tree> <label>
set -u

TREE=$1
LABEL=$2

FLEET=$(mktemp -d "${TMPDIR:-/tmp}/keith-activity-$LABEL.XXXXXX")
trap 'rm -rf "$FLEET"' EXIT

FAKEBIN="$FLEET/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'fixture pane\n> \n' ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/tmux"

NOW=2026-08-28T10:00:00Z
EPOCH=1787911200

CHILD="$FLEET/keith-api"
mkdir -p "$CHILD/state" "$CHILD/data" "$CHILD/config" "$CHILD/bin" "$CHILD/projects"
printf '# Seeded Firstmate home\n' > "$CHILD/AGENTS.md"
printf 'keith-api\n' > "$CHILD/.fm-secondmate-home"
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$CHILD/data/backlog.md"
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$TREE" FM_HOME="$CHILD" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$TREE/bin/fm-home-summary-refresh.sh" || exit 1

PARENT="$FLEET/main"
mkdir -p "$PARENT/state" "$PARENT/data" "$PARENT/config" "$PARENT/projects"
printf '# Seeded Firstmate home\n' > "$PARENT/AGENTS.md"
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$PARENT/data/backlog.md"
printf -- '- keith-api - Keith api second mate (home: %s; scope: api surface; projects: keith; added 2026-08-20)\n' \
  "$CHILD" > "$PARENT/data/secondmates.md"
{
  printf 'window=fmtest:fm-keith-api\nendpoint_task_id=keith-api\nworktree=%s\n' "$CHILD"
  printf 'project=%s\nharness=claude\nkind=secondmate\nmode=secondmate\nyolo=off\n' "$CHILD"
  printf 'home=%s\nprojects=keith\n' "$CHILD"
} > "$PARENT/state/keith-api.meta"

# The parent's own status log for that second mate carries one mirrored remote
# payload line with no size cap (bin/fm-procevent-remote-reply.sh appends it).
huge=$(head -c 200000 /dev/zero | LC_ALL=C tr '\0' 'q')
printf 'working [key=mirror]: %s\n' "$huge" > "$PARENT/state/keith-api.status"

printf '=== %s: parent snapshot with FM_SNAPSHOT_PARENT_ACTIVITY_BYTES=300000 ===\n' "$LABEL"
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$TREE" FM_HOME="$PARENT" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  FM_SNAPSHOT_PARENT_ACTIVITY_BYTES=300000 \
  "$TREE/bin/fm-fleet-snapshot.sh" --json > "$FLEET/snapshot.json" 2> "$FLEET/snapshot.err"
rc=$?
printf '    exit: %s\n' "$rc"
[ -s "$FLEET/snapshot.err" ] && sed 's/^/    stderr: /' "$FLEET/snapshot.err"
if [ "$rc" -eq 0 ]; then
  jq -c '{secondmate_records: [.secondmate_current.records[] | .id],
          provenance: [.secondmate_current.records[] | .provenance.selected],
          parent_event_raw_bytes: [.secondmate_current.records[] | (.parent_event.raw | length)],
          activity_records: [.secondmate_current.records[] | (.parent_event.open_activities | length)],
          activity_record_bytes: [.secondmate_current.records[] | ([.parent_event.open_activities[].summary | length] | add // 0)],
          activity_scan: [.secondmate_current.records[] | .parent_event.activity_scan | {available, input_truncated, records_in_window, reasons}]}' \
    "$FLEET/snapshot.json" | sed 's/^/    /'
else
  printf '    NO SNAPSHOT - Bearings has nothing to render\n'
fi
exit 0
