#!/usr/bin/env bash
# Manual end-to-end reproduction for the contribution-input half of
# fm/fix-secondmate-home-summary-argv-overflow.
#
# Builds ONE identical home fixture whose parsed backlog exceeds Linux's 128 KiB
# per-exec-argument limit and one whose canonical input cannot be read at all,
# then runs the captain-visible contribution commands twice:
#   before/  - bin/fm-fleet-snapshot.sh + bin/fm-contributions.sh from the base commit
#   after/   - the same two commands from the branch head
#
# Usage: repro-contribution-input.sh <repo-root> <base-bin-dir> <out-dir>
set -u

REPO=$1
BASE_BIN=$2
OUT=$3

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-argv-contrib.XXXXXX")
NOW=2026-09-16T08:00:00Z
HEAD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

seed_home() {  # <home>
  local home=$1 pad i
  mkdir -p "$home/data/delivery" "$home/state" "$home/config" "$home/projects" \
    "$home/fakebin" "$home/root/bin"
  printf '#!/bin/sh\nexit 1\n' > "$home/fakebin/tmux"
  printf '#!/bin/sh\nexit 0\n' > "$home/fakebin/no-mistakes"
  chmod +x "$home/fakebin/"*
  printf '# Backlog\n\n## Queued\n' > "$home/data/backlog.md"
  printf -- '- [ ] delivery - Contribution delivery https://github.com/o/r/pull/21 (repo: sample) (kind: ship)\n' \
    >> "$home/data/backlog.md"
  jq -n --arg task delivery --arg url https://github.com/o/r/pull/21 \
    --arg head "$HEAD_A" --arg at "$NOW" '
    {schema:"fm-contributions.v1",task:$task,records:[{
      url:$url,kind:"pr",checked_at:$at,error:null,pending:[],seen:[],verdict:null,
      observation:{head:$head,state:"open",draft:false,mergeable:"mergeable",
        review_decision:"APPROVED",can_merge:false,
        checks:[{name:"test",id:1,status:"completed",conclusion:"success",started_at:$at}],
        reviews:[],events:[]}}]}' > "$home/data/delivery/contributions.json"
  # A long-lived home accumulates queued rows; every structured field of every
  # row lands in the parsed backlog JSON, which has no contract size bound.
  pad=$(printf 'p%.0s' $(seq 1 160))
  i=1
  while [ "$i" -le 400 ]; do
    printf -- '- [ ] filler-%03d - Queued row %03d %s (repo: sample) (kind: ship) (since 2026-09-01)\n' \
      "$i" "$i" "$pad"
    i=$((i + 1))
  done >> "$home/data/backlog.md"
}

with_home() {  # <home> <cmd...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home/root" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" FM_CONTRIBUTIONS_NOW="$NOW" "$@"
}

run_variant() {  # <label> <bin-dir>
  local label=$1 bin=$2 home dir rc bytes
  home="$WORK/$label-home"
  dir="$OUT/$label"
  mkdir -p "$dir"
  seed_home "$home"
  printf '#!/bin/sh\nexit 0\n' > "$home/root/bin/fm-guard.sh"
  chmod +x "$home/root/bin/fm-guard.sh"

  {
    printf '$ wc -c data/backlog.md\n'
    wc -c < "$home/data/backlog.md"
    printf '\n$ bin/fm-fleet-snapshot.sh --contribution-input | wc -c   # canonical ownership pair\n'
    rc=0
    with_home "$home" "$bin/fm-fleet-snapshot.sh" --contribution-input \
      > "$WORK/$label-input.json" 2> "$WORK/$label-input.err" || rc=$?
    wc -c < "$WORK/$label-input.json"
    printf 'exit status: %s\n' "$rc"
    printf 'stderr: %s\n' "$(cat "$WORK/$label-input.err")"
    bytes=$(jq -c '.backlog' "$WORK/$label-input.json" 2>/dev/null | wc -c)
    printf 'parsed backlog JSON bytes: %s (Linux MAX_ARG_STRLEN is 131072)\n' "$bytes"
    printf 'backlog records carried: %s\n' \
      "$(jq -r '.backlog.records | length' "$WORK/$label-input.json" 2>/dev/null || printf 'unreadable')"

    printf '\n$ bin/fm-contributions.sh snapshot input.json --all   # coverage the captain reads\n'
    rc=0
    with_home "$home" "$bin/fm-contributions.sh" snapshot "$WORK/$label-input.json" --all \
      > "$WORK/$label-coverage.json" 2>&1 || rc=$?
    jq -c '{known,checked,complete,errors,rows:[.rows[]?|{task,url}]}' "$WORK/$label-coverage.json" \
      2>/dev/null || cat "$WORK/$label-coverage.json"
    printf 'exit status: %s\n' "$rc"

    printf '\n$ chmod 000 data/backlog.md && bin/fm-contributions.sh poll   # canonical input unreadable\n'
    chmod 000 "$home/data/backlog.md"
    rc=0
    with_home "$home" "$bin/fm-contributions.sh" poll > "$WORK/$label-poll.out" \
      2> "$WORK/$label-poll.err" || rc=$?
    chmod 644 "$home/data/backlog.md"
    printf 'stdout: %s\n' "$(cat "$WORK/$label-poll.out")"
    printf 'stderr: %s\n' "$(cat "$WORK/$label-poll.err")"
    printf 'exit status: %s\n' "$rc"
  } > "$dir/transcript.txt" 2>&1
  cp "$WORK/$label-coverage.json" "$dir/coverage.json" 2>/dev/null || true
}

run_variant before "$BASE_BIN"
run_variant after "$REPO/bin"

rm -rf "$WORK"
printf 'wrote %s/before and %s/after\n' "$OUT" "$OUT"
