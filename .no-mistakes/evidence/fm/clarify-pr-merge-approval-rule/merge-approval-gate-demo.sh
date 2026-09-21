#!/usr/bin/env bash
# Evidence demo for AGENTS.md hard rule 2, as reworded on this branch:
#   "Never merge a PR without approval from the captain."
#
# Drives the real merge entrypoint (bin/fm-pr-merge.sh) against an isolated
# fixture home with a mocked forge, and shows the captain-facing experience:
#   1. no captain approval recorded -> the merge is refused, the forge is never
#      called;
#   2. the captain's approval recorded through bin/fm-captain-hold.sh answer
#      --release -> the same merge lands and its authority is persisted.
set -u

REPO=/home/neil_keith_com/.no-mistakes/worktrees/8d4e8e2579c7/01M31VA41A9SCJE21VA9HDE75C
export PATH="/home/neil_keith_com/.nvm/versions/node/v24.18.0/bin:$PATH"

# shellcheck source=/dev/null
. "$REPO/tests/lib.sh"

TASKS_AXI_BIN=$(command -v tasks-axi)
TMP=$(fm_test_tmproot fm-merge-approval-demo)
home="$TMP/home"
mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
cp "$REPO/.tasks.toml" "$home/.tasks.toml"
printf '%s\n' '## In flight' '' '## Queued' '' '## Done' > "$home/data/backlog.md"

fakebin=$(fm_fakebin "$home")
fm_fake_exit0 "$fakebin" tmux treehouse no-mistakes

# A forge that would happily merge: every pre-merge condition is green, so the
# only thing that can stop this merge is the captain-approval gate.
cat > "$fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_LOG"
case "${1:-} ${2:-}" in
  "pr view")
    case " $* " in
      *statusCheckRollup*)
        printf '%s\n' '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"main","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}'
        ;;
      *headRefOid*) printf '%s\n' 1111111111111111111111111111111111111111 ;;
    esac
    ;;
  "pr merge") printf 'merged:\n  number: %s\n  status: ok\n' "${3:-}" ;;
  "api graphql") printf '%s\n' 'state=MERGED' 'merged=true' 'queued=false' 'base=main' ;;
esac
SH
cat > "$fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_AXI_LOG"
case "${1:-} ${2:-}" in
  "pr view") printf 'pull_request:\n  number: %s\n  state: merged\n' "${3:-}" ;;
esac
SH
chmod +x "$fakebin/gh" "$fakebin/gh-axi"
: > "$home/gh.log"
: > "$home/gh-axi.log"

ID=captain-approval-demo
PR=https://github.com/sample/sample/pull/31
REPO_DIR="$home/projects/sample-pr"
WT="$home/projects/$ID"
fm_git_worktree "$REPO_DIR" "$WT" "fm/$ID"

captain() {
  PATH="$fakebin:$PATH" REAL_TASKS_AXI="$TASKS_AXI_BIN" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$REPO/bin/fm-captain-hold.sh" "$@"
}

merge_pr() {
  PATH="$fakebin:$PATH" FM_ROOT_OVERRIDE="$REPO" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" FM_TEST_GH_LOG="$home/gh.log" \
    FM_TEST_GH_AXI_LOG="$home/gh-axi.log" "$REPO/bin/fm-pr-merge.sh" "$@"
}

section() { printf '\n=== %s ===\n' "$1"; }

printf 'AGENTS.md hard rule 2 on this branch:\n'
sed -n '32,33p' "$REPO/AGENTS.md"

section 'setup: a green ship PR waiting on the captain'
(cd "$home" && tasks-axi add "$ID" "Ship the sample change" --kind ship \
  --repo sample --start) > /dev/null
fm_write_meta "$home/state/$ID.meta" \
  "window=firstmate:fm-$ID" "endpoint_task_id=$ID" "worktree=$WT" \
  "project=$REPO_DIR" "harness=codex" "kind=ship" "mode=no-mistakes" \
  "pr=$PR" "spawn_gen=demo-$ID"
printf 'done: merge ready\n' > "$home/state/$ID.status"
captain hold "$ID" --reason "captain merge approval pending" > /dev/null
printf 'backlog row (captain-facing):\n'
(cd "$home" && tasks-axi show "$ID" --full) | sed -n '1,12p'

section 'attempt 1: merge with NO approval from the captain'
set +e
merge_pr "$ID" "$PR" > "$home/attempt1.out" 2> "$home/attempt1.err"
rc1=$?
set -e
printf 'exit status: %s\n' "$rc1"
printf 'stderr:\n'
grep -v '^●' "$home/attempt1.err" | sed '/^$/d'
printf 'forge merge calls recorded: %s\n' "$(grep -c 'pr merge' "$home/gh.log")"
printf 'persisted merge authority: %s\n' \
  "$( [ -e "$home/state/$ID.merge-authority" ] && echo present || echo none )"

section 'the captain approves'
printf 'Approved - merge it.\n' > "$home/approval.txt"
captain answer "$ID" --release --decision-file "$home/approval.txt"

section 'attempt 2: same merge, now WITH approval from the captain'
set +e
merge_pr "$ID" "$PR" > "$home/attempt2.out" 2> "$home/attempt2.err"
rc2=$?
set -e
printf 'exit status: %s\n' "$rc2"
printf 'stdout:\n'
grep -v '^●' "$home/attempt2.out" | sed '/^$/d'
printf 'forge merge calls recorded: %s\n' "$(grep -c 'pr merge' "$home/gh.log")"
printf 'gh merge command: %s\n' "$(grep 'pr merge' "$home/gh.log")"
printf 'persisted merge authority record (state/%s.merge-authority):\n' "$ID"
cat "$home/state/$ID.merge-authority"

section 'verdict'
if [ "$rc1" -ne 0 ] && [ "$rc2" -eq 0 ] \
  && [ "$(grep -c 'pr merge' "$home/gh.log")" -eq 1 ]; then
  printf 'PASS: the PR merged only after approval from the captain was recorded.\n'
else
  printf 'FAIL: unexpected gate behaviour (rc1=%s rc2=%s).\n' "$rc1" "$rc2"
  exit 1
fi
