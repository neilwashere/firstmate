# GitHub fleet task store spike

Verification date: 2026-09-03.

This record captures the throwaway code and read-only live API evidence used to test the proposed [`GitHub-backed fleet task store`](../github-fleet-task-store.md).
No GitHub issue, project, field, relationship, comment, or status was created or mutated during this spike.
The code lived in a temporary clone of `kunchenguid/tasks-axi` and is not part of the proposed production implementation.

## Question

The spike asked whether the existing `tasks-axi` Store seam and GitHub Projects GraphQL surface can support a single fleet control plane without a Markdown mirror.
It deliberately exercised ambiguous remote outcomes, project-specific state, product-issue closure, stable identity, native dependencies, ownership handoff, and concurrent body-edit risk.

## Environment

```text
$ tasks-axi --version
0.2.4

$ git -C /tmp/tasks-axi-goal-check rev-parse --short HEAD
d9175b6

$ node --version
v24.18.0

$ corepack pnpm --version
11.25.0
```

The temporary clone installed the repository's pinned dependencies through Corepack because `pnpm` was not directly on `PATH`.

## Store-interface spike

The spike implemented a `GithubStoreSpike` against the current upstream `Store` TypeScript interface.
A fake transport committed writes before injecting an ambiguous lost-response error, which models the failure class a remote adapter must reconcile.

The executable cases proved the following properties.

- An exact creation marker can recover an ambiguously successful fleet-only issue creation without producing a duplicate.
- A partially populated project item can converge missing fields on retry.
- Fleet-project status can change without changing another project's status on the same issue.
- Fleet completion can leave a reused product issue globally open.
- Fleet completion may close a fleet-only issue.
- Duplicate Task ID values can stop lookup and report every conflicting issue.
- A partially applied multi-task home transfer can converge without losing a native blocked-by relationship.
- The home field can act as the cross-home execution-authority key.
- Wholesale issue-body replacement must be refused, while append-only notes can use idempotently marked comments.
- Pruning and receipt-gated public follow-ups can be declared unsupported independently of ordinary task support.

The first handoff implementation was intentionally strict and failed its replay case after the first owner write committed but its response was lost.
On retry, the source rejected the first item because it already named the destination.
The corrected rule accepts each selected item only when its owner equals the recorded source or intended destination, mutates only source-owned items, and verifies the complete destination set before acknowledging the batch.

```text
$ corepack pnpm exec vitest run spike/github-store-spike.test.ts

 RUN  v3.2.6 /tmp/tasks-axi-goal-check

 ✓ spike/github-store-spike.test.ts (9 tests) 9ms

 Test Files  1 passed (1)
      Tests  9 passed (9)
```

The spike also passed the repository's strict TypeScript compiler and ESLint after its deliberately local implementation parameters were consumed explicitly.

```text
$ corepack pnpm exec tsc --noEmit --pretty false
$ corepack pnpm exec eslint spike/github-store-spike.test.ts
```

Both commands produced no output and exited zero.

## Live GraphQL shape

A read-only GraphQL query against `keithteam` project 1 confirmed these current GitHub capabilities.

- A project issue exposes a connection containing every project item for that issue, so one issue can participate in multiple projects.
- Each project item exposes project-specific field values.
- GitHub exposes native `blockedBy`, `blocking`, `parent`, and `subIssues` issue relationships.
- GitHub exposes `addBlockedBy`, `removeBlockedBy`, `addSubIssue`, and `removeSubIssue` mutations.
- `ProjectV2.items` accepts an advanced `query` filter in addition to pagination and ordering.
- The current caller had `viewerCanUpdate: true` on the inspected project.
- `UpdateIssueInput` has no expected version or conditional-write field.
- `CreateIssueInput` has a `clientMutationId`, but GitHub provides no documented idempotent create guarantee for that value.
- `UpdateProjectV2ItemFieldValueInput` changes one field value and has no expected prior value.

The issue-update limitation is material.
GitHub's REST guidance also states that conditional requests are unsupported for unsafe methods such as `PATCH` unless an endpoint says otherwise, and the issue endpoint provides no such exception.
The GitHub adapter therefore cannot preserve `tasks-axi` wholesale body replacement safely against a concurrent human edit.

The workable boundary is to keep the issue body human-owned, store ordinary task state in project fields and native relationships, append operational events as idempotently marked comments, and declare body replacement unsupported.
Captain-held teardown must record its deliverable through a structured link or event rather than a body rewrite before the GitHub adapter is enabled.

## Scale probe

The live project contained 839 items and 34 fields.
Fetching all project items and up to 50 field values per item required nine sequential pages and 17.688 seconds from this host.
The final request reported GraphQL cost 1 and 4,944 points remaining.

```json
{
  "items": 839,
  "pages": 9,
  "elapsed_ms": 17688,
  "final_request_cost": 1,
  "remaining": 4944
}
```

A server-side `status:Todo` query returned the first 100 of 571 matching items in 2.008 seconds.
A server-side `tier:P1-now` query returned the first 100 of 292 matching items in 2.397 seconds.
A plain text query returned broad title matches, which proves the query path exists but is not an exact identity guarantee.

The inspected project has no Task ID text field, so this spike did not mutate it merely to prove exact custom-text filtering.
That remaining uncertainty was closed separately by the Task ID canary recorded below.

An unfiltered project scan is too slow for a dispatch-time task probe and gets slower as Done history accumulates.
Exact task reads must use server-side narrowing, and full active snapshots must run outside per-task runtime locks with explicit pagination, time, completeness, and freshness bounds.

## Task ID canary

Exact custom-text filtering was the one activation blocker this spike could not settle by reading an existing project.
It was settled against a disposable personal project created and deleted for the purpose, so no shared board was mutated.
The fixture set was chosen to hunt false negatives rather than to confirm the happy path.

Field-scoped narrowing is exact and rejects every planted decoy.

```
query                total  matched Task ID values
task-id:fm-0007      2      fm-0007, FM-0007
fm-0007              4      fm-0007, fm-00071, FM-0007, fm-9999
task-id:fm-007       1      fm-007
task-id:fm-does-not-exist  0
no:task-id           1      the single untagged item of 17
```

The superstring `fm-00071`, the prefix `fm-007`, the separator variant `fm_0007`, and the embedded `xfm-0007` were all excluded.
The item whose title mentions `fm-0007` while carrying Task ID `fm-9999` was excluded by the field-scoped query and returned by the plain text query.
Plain text search therefore matches titles as well as fields and cannot be used for identity.
Matching is exact rather than prefix, which the reverse probe on the shorter id confirms.

The search index is not read-your-writes consistent.

```
direct node read by item id   0.26-0.46s   resolved on the first attempt in 5 of 5 trials
search index visibility       1.07-3.61s   n=5
```

A verification step that reads back through search can therefore observe its own successful write as absent.
Every mutation returns the item node id, so postcondition verification must read that handle and search must be reserved for discovery.
Only the ambiguous create path lacks a handle, and that path must treat absence as unproven until a bounded retry window expires.
The measured spread is a floor rather than a budget, because it was taken on a small project rather than under load.

Field-scoped matching is case-insensitive, so `task-id:fm-0007` returns both `fm-0007` and `FM-0007`.
Exact comparison after narrowing still separates them, but two homes minting ids that differ only by case would be indistinguishable to the index.
Task ids must therefore be minted from a case-normalised alphabet.

The canary ran on a 17-item personal project using draft issues, so it does not characterise an 839-item organisation project under concurrent writers.
It proves the identity mechanism rather than its behaviour at scale.

## Independent review

An independent Opus 5 review examined the proposal and the current Firstmate and `tasks-axi` implementations.
Its central verdict was that the direction is architecturally sound but the first draft understated five hard couplings.
The revised design incorporates all five.

1. Home is now a first-class task field and query key rather than arbitrary metadata.
2. Ownership transfer and collection transfer are explicit Store capabilities, and command code must stop type-testing `MarkdownStore`.
3. Captain-held cleanup records its deliverable without replacing the task body.
4. GitHub declares pruning unsupported and `done` reports backend-managed retention.
5. GitHub selection and later Relay activation refuse before an unsupported public-followup promise can be made.

The review also identified that Firstmate's fleet snapshot owns domain projections beyond Markdown parsing.
The revised design assigns portable Ready, Blocked, and Held derivation to the `tasks-axi` domain layer and leaves Firstmate-specific captain and runtime projections in Firstmate.

## Risks that would tank the effort if ignored

### Dual writable truth

A bidirectional Markdown and GitHub mirror has no safe conflict winner.
GitHub must be the canonical ordinary-task store after cutover, while local cache and journals remain non-authoritative recovery aids.

### Remote writes under local lifecycle locks

A full project scan inside spawn or cleanup would make fleet lifecycle latency unbounded and amplify GitHub outages.
Exact server-side lookup, hard timeouts, capability-aware recovery, and snapshot work outside the task lock are prerequisites.

### Human body clobbering

GitHub has no conditional issue-body update.
A direct mapping of `TaskPatch.body` would silently overwrite human edits, so the GitHub adapter must refuse it and Firstmate must use append-only events or structured links.

### False issue completion

Closing a reused product issue when a worker merely produced a PR would alter every board containing that issue.
Fleet status must remain a project field, and global closure must follow the repository's landing policy.

### Unsupported durable obligations

Receipt-gated public follow-ups need atomic expected-revision mutation and completion that the first GitHub adapter cannot provide.
A Relay-enabled home must reject GitHub selection or Relay activation until a composite or equivalent remote contract exists.

### Destructive removal mismatch

Markdown `rm` physically removes a task, while GitHub issue deletion is destructive, permission-sensitive, and contrary to retained fleet history.
Portable cancellation must be separated from optional hard removal, with cancellation retained as a non-delivery outcome.

### Hidden Markdown coupling

Current snapshot parsing, file-presence gating, scalar compatibility probing, `instanceof MarkdownStore`, archive pruning, and cross-file moves all bypass or constrain the intended Store seam.
A GitHub adapter added before those seams are corrected would force Firstmate into a private backend fork.

## Workable gotchas

- GitHub field and option node ids are configuration cache values rather than durable identities, so every cold start resolves names and types and rejects ambiguity.
- Project field writes are individually idempotent but not transactional, so every multi-field or multi-item operation requires postcondition verification.
- The current Markdown handoff and the future ownership handoff have different persistence mechanics, but one Firstmate notification and recovery protocol can own both.
- A source-or-destination replay rule is required for partially completed ownership batches.
- The stable task id cannot be replaced by the issue number because issue numbers are repository-scoped and Firstmate ids are filesystem keys.
- Duplicate identity checks must use a narrowed server query and exact value comparison rather than scanning or trusting the first match.
- Postcondition verification must read the item node id returned by the mutation, because the project search index lags the write by seconds and would report a successful write as absent.
- Task ids must be minted from a case-normalised alphabet, because field-scoped project search is case-insensitive.
- Project status fields in different projects are independent, while issue title, body, assignees, labels, and open state are global.
- Project administrators and repository administrators do not necessarily have issue or project deletion rights, so ordinary cancellation must not depend on deletion and provisioning must preflight the exact required mutations rather than infer authority from broad token scopes.
- Migration must refuse while any participating home has a pending backlog-close record or a runtime-to-backlog contradiction.
- A prose-derived deferred marker is not portable and must become a structured wait before cutover.

## Architecture verdict

The approach is viable with no discovered platform limitation that requires abandoning it.
The safe path is not to start with `GithubStore`.
The safe path starts by deepening the upstream `tasks-axi` interface and making Firstmate consume it while still using Markdown.
Those changes are independently useful and preserve the ability to absorb future upstream work.

The no-go conditions for a production canary are now explicit.

- No command-layer backend type test may remain on a lifecycle path used by GitHub.
- Exact Task ID lookup is proven correct in isolation and must still meet its dispatch-time bound on a large project.
- Captain-held cleanup must no longer require body replacement.
- Relay-enabled homes must have a supported obligation store or refuse GitHub.
- Cutover must have no pending close record or contradictory task inventory.
- The canary must prove ambiguous create, partial owner transfer, rate-limit replay, multi-project independence, and product-issue closure policy against an isolated live project.

None of those conditions requires a private Firstmate fork of `tasks-axi`.
They can be delivered as upstream interface improvements followed by the adapter, with Firstmate depending only on versioned commands and capability output.
