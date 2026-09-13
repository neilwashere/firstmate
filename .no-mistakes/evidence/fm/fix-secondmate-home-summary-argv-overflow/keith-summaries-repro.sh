#!/usr/bin/env bash
# Reproduction driver for the "both Keith second-mate summaries unreadable" failure.
#
# Builds a captain main home with TWO registered local second mates, each holding
# real in-flight work, a captain call, recent landings, and status streams whose
# unbounded payloads exceed Linux's 128 KiB MAX_ARG_STRLEN cap on ONE exec
# argument (keith-web accumulates many long still-open decisions; keith-api
# carries one oversized mirrored remote payload line). It then:
#   1. publishes each second mate's own state/home-summary.json with the tree
#      under test (bin/fm-home-summary-refresh.sh), and
#   2. renders the captain-facing Bearings projection from the parent home
#      (bin/fm-bearings-snapshot.sh), which is what /bearings reads.
#
# usage: keith-summaries-repro.sh <repo-tree> <out-dir> <label>
set -u

TREE=$1
OUT=$2
LABEL=$3

FLEET=$(mktemp -d "${TMPDIR:-/tmp}/keith-repro-$LABEL.XXXXXX")
trap '[ -n "${KEEP_FLEET:-}" ] || rm -rf "$FLEET"' EXIT
mkdir -p "$OUT"

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

write_meta() {  # <file> <kv>...
  local file=$1
  shift
  : > "$file"
  printf '%s\n' "$@" >> "$file"
}

git_repo() {  # <dir>
  mkdir -p "$1"
  git -C "$1" init -q -b main
  printf '# fixture\n' > "$1/README.md"
  git -C "$1" add README.md
  git -C "$1" -c user.name='Fixture' -c user.email='fixture@example.invalid' commit -qm initial
}

mark_working() {  # <state-dir> <id>
  local gen
  gen=$("$TREE/bin/fm-busy-event.sh" arm "$1" "$2")
  "$TREE/bin/fm-busy-event.sh" apply "$1" "$2" busy --gen "$gen" \
    --source claude-hook --event user-prompt-submit
}

mark_idle() {  # <state-dir> <id>
  local gen
  gen=$("$TREE/bin/fm-busy-event.sh" arm "$1" "$2")
  "$TREE/bin/fm-busy-event.sh" apply "$1" "$2" idle --gen "$gen" \
    --source claude-hook --event stop
}

long_note=$(printf 'the client wants the completion-fee wording signed off before we ship; %.0s' $(seq 1 45))
huge_note=$(head -c 200000 /dev/zero | LC_ALL=C tr '\0' 'q')

# --- second mate homes ------------------------------------------------------
for mate in keith-web keith-api; do
  home="$FLEET/$mate"
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/bin" \
    "$home/projects/checkout" "$home/projects/held"
  printf '# Seeded Firstmate home\n' > "$home/AGENTS.md"
  printf '%s\n' "$mate" > "$home/.fm-secondmate-home"
  git_repo "$home/projects/checkout"
  git_repo "$home/projects/held"
  cat > "$home/data/backlog.md" <<EOF
## In flight
- [ ] $mate-checkout - Rework the checkout fee schedule (repo: keith) (kind: ship) (since 2026-08-26)
- [ ] $mate-fees - Confirm the completion fee wording (repo: keith) (kind: ship) (since 2026-08-25)

## Queued
- [ ] $mate-copy-call - Choose the client-facing fee copy (repo: keith) (kind: captain) (hold: captain choice pending) (hold-kind: captain)

## Done
- [x] $mate-search - Ship title search caching https://github.com/keith/keith/pull/701 (repo: keith) (kind: ship) (merged 2026-08-27)
- [x] $mate-audit - Land the audit-log migration https://github.com/keith/keith/pull/698 (repo: keith) (kind: ship) (merged 2026-08-26)
EOF
  write_meta "$home/state/$mate-checkout.meta" \
    "window=fmtest:fm-$mate-checkout" \
    "worktree=$home/projects/checkout" \
    "project=keith" "harness=claude" "kind=ship" "mode=no-mistakes" \
    "spawn_gen=fm.$mate.checkout.1"
  write_meta "$home/state/$mate-fees.meta" \
    "window=fmtest:fm-$mate-fees" \
    "worktree=$home/projects/held" \
    "project=keith" "harness=claude" "kind=ship" "mode=no-mistakes" \
    "spawn_gen=fm.$mate.fees.1"
  mark_working "$home/state" "$mate-checkout"
  mark_idle "$home/state" "$mate-fees"
done

# keith-web: 60 still-open keyed decisions on the parked task, each note long, so
# the whole-status-log fold grows past the per-exec-argument limit.
{
  i=1
  while [ "$i" -le 60 ]; do
    printf 'needs-decision [key=fee-%s]: %s\n' "$i" "$long_note"
    i=$((i + 1))
  done
} > "$FLEET/keith-web/state/keith-web-fees.status"
printf 'working [key=checkout]: reworking the checkout fee schedule\n' \
  > "$FLEET/keith-web/state/keith-web-checkout.status"

# keith-api: ONE oversized mirrored remote payload line on the live task, the
# other unbounded status shape (fm-procevent-remote-reply.sh mirrors with no cap).
printf 'working [key=mirror]: %s\n' "$huge_note" \
  > "$FLEET/keith-api/state/keith-api-checkout.status"
printf 'needs-decision [key=fee-copy]: confirm the completion fee wording\n' \
  > "$FLEET/keith-api/state/keith-api-fees.status"

printf '=== %s: each Keith second mate publishes its own state/home-summary.json ===\n' "$LABEL"
for mate in keith-web keith-api; do
  printf '\n--- %s: bin/fm-home-summary-refresh.sh\n' "$mate"
  PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$TREE" FM_HOME="$FLEET/$mate" \
    FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
    "$TREE/bin/fm-home-summary-refresh.sh" 2>&1 | sed 's/^/    /'
  printf '    exit: %s\n' "${PIPESTATUS[0]}"
  if [ -f "$FLEET/$mate/state/home-summary.json" ]; then
    jq '{readable: .valid, invalidity: .invalidity.kind, reason,
         home_state: .state,
         current_work: [.active_children[] | {id, doing}],
         decisions_open: (.counts.decisions_open),
         first_decisions: [.decisions_open[0:2][] | {id, key, verb}],
         recent_landings: [.landed[] | {id, what: .title, artifact}],
         counts}' \
      "$FLEET/$mate/state/home-summary.json" 2>&1 | sed 's/^/    /'
    cp "$FLEET/$mate/state/home-summary.json" "$OUT/$LABEL-$mate-home-summary.json"
  else
    printf '    NO state/home-summary.json PUBLISHED - summary unreadable\n'
  fi
done

# --- captain main home ------------------------------------------------------
PARENT="$FLEET/main"
mkdir -p "$PARENT/state" "$PARENT/data" "$PARENT/config" "$PARENT/projects"
printf '# Seeded Firstmate home\n' > "$PARENT/AGENTS.md"
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$PARENT/data/backlog.md"
{
  printf -- '- keith-web - Keith web second mate (home: %s; scope: web surface; projects: keith; added 2026-08-20)\n' \
    "$FLEET/keith-web"
  printf -- '- keith-api - Keith api second mate (home: %s; scope: api surface; projects: keith; added 2026-08-20)\n' \
    "$FLEET/keith-api"
} > "$PARENT/data/secondmates.md"
for mate in keith-web keith-api; do
  write_meta "$PARENT/state/$mate.meta" \
    "window=fmtest:fm-$mate" \
    "endpoint_task_id=$mate" \
    "worktree=$FLEET/$mate" \
    "project=$FLEET/$mate" \
    "harness=claude" "kind=secondmate" "mode=secondmate" "yolo=off" \
    "home=$FLEET/$mate" "projects=keith"
  mark_working "$PARENT/state" "$mate"
done

printf '\n=== %s: captain view - bin/fm-bearings-snapshot.sh (what /bearings reads) ===\n' "$LABEL"
PATH="$FAKEBIN:$PATH" FM_ROOT_OVERRIDE="$TREE" FM_HOME="$PARENT" \
  FM_SNAPSHOT_NOW="$NOW" FM_SNAPSHOT_NOW_EPOCH="$EPOCH" \
  "$TREE/bin/fm-bearings-snapshot.sh" > "$OUT/$LABEL-bearings.toon" 2> "$OUT/$LABEL-bearings.err"
printf '    exit: %s\n' "$?"
[ -s "$OUT/$LABEL-bearings.err" ] && sed 's/^/    stderr: /' "$OUT/$LABEL-bearings.err"
sed -e "s#$FLEET#<fleet>#g" "$OUT/$LABEL-bearings.toon" | sed 's/^/    /'
