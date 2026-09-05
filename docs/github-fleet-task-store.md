# GitHub-backed fleet task store

Status: proposed and spike-informed, not implemented.

This document specifies how Firstmate can expose its operational backlog and task issuance through GitHub Issues and GitHub Projects without creating a second writable source of truth.
It owns the proposed cross-repository contract between Firstmate and `tasks-axi`.
Current backlog behavior remains owned by [`configuration.md`](configuration.md#backlog-backend-taskstoml--configbacklog-backend) until this proposal is implemented.

## Decision

GitHub Issues and one GitHub Project become the canonical store and control plane for ordinary fleet work when the GitHub backend is selected.
The Markdown backend remains supported and continues to be the default until the GitHub path passes migration and recovery verification.
The GitHub implementation belongs upstream in `tasks-axi` behind its existing `Store` interface.
Firstmate consumes only released `tasks-axi` commands and structured output rather than importing or copying backend implementation.
A task's owning home becomes a first-class portable `Task` field and query filter because it is the fleet's partition and write-authority key.
Backend-specific identifiers and runtime details remain in extensible metadata.

A synchronization mirror between `data/backlog.md` and GitHub is rejected.
Two writable stores would make conflicts, partial updates, and authority ambiguous, which would recreate the visibility problem this change is intended to solve.
A local cache and a durable mutation journal are allowed because neither accepts independent task edits.

## Outcomes

The design must provide these outcomes.

- The captain can see and prioritise every ordinary fleet work item without asking Firstmate for a summary.
- Main Firstmate can see all routed work, including work owned by a secondmate.
- Each secondmate can select only the work assigned to its stable home identity.
- A task remains visible while it moves from intake through dispatch, review, landing, and completion.
- Follow-up work discovered by a scout or worker is recorded before the originating task is retired.
- An issue that already represents the work is reused rather than wrapped in a duplicate fleet issue.
- Existing repository issues can appear in their product project and the fleet project at the same time.
- A GitHub outage cannot silently dispatch work, lose a completion, or report a partial handoff as complete.
- Future upstream `tasks-axi` features remain available to Firstmate without maintaining a private fork.

## Non-goals

This proposal does not make GitHub the source of runtime process truth.
Firstmate runtime records remain authoritative for live worker endpoints, worktrees, current execution state, and supervision leases.
This proposal does not expose private Relay request context, credentials, terminal transcripts, or other home-private records in issues.
This proposal does not require every historical entry in `done-archive.md` to become an issue.
This proposal does not make a board drag directly launch, interrupt, or stop a worker.
This proposal does not remove the Markdown backend.

## Current seams and leaks

`tasks-axi` already defines a narrow `Store` interface for CRUD, queries, transitions, dependencies, and optional capabilities.
Its model carries stable task ids, explicit queued, in-flight, and done states, dependencies, holds, priorities, links, and extensible metadata.
The current released implementation constructs only `MarkdownStore`, and its roadmap lists remote trackers as planned.

Firstmate already delegates routine mutations to `tasks-axi`.
`bin/fm-spawn.sh` and `bin/fm-teardown.sh` pair runtime record changes with `tasks-axi start`, `done`, or `reopen` under the task lock.
This is the right lifecycle seam and should remain intact.

Several Firstmate paths currently bypass or constrain the store seam.

- `bin/fm-fleet-snapshot.sh` parses `data/backlog.md` directly.
- `bin/fm-backlog-transition-lib.sh` requires a backlog file before enabling automatic transitions.
- `bin/fm-backlog-handoff.sh` and `bin/fm-backlog-receive.sh` transfer dependency-closed sets between Markdown files through `tasks-axi mv`.
- The `mv` command reaches around the Store interface with an `instanceof MarkdownStore` branch and constructs its destination adapter directly.
- `bin/fm-tasks-axi-lib.sh` treats atomic multi-id Markdown moves as a universal compatibility requirement.
- Session-start fallback rendering reads the Markdown file when structured `tasks-axi` access is unavailable.

These paths must move to backend-neutral commands or capability checks before a GitHub backend can be selected safely.

## GitHub topology

One private repository should own fleet-only issues.
The initial suggested name is `keithteam/fleet-ops`, but the repository name is deployment configuration rather than part of the interface.

One private organization Project should contain every fleet-controlled work item.
The project is a collection with several views, not the sole owner of an issue.
An existing repository issue can be added to this project while remaining in any product project.

Fleet-only work is created in the fleet operations repository.
Examples include Firstmate maintenance, fleet administration, and a captain decision with no natural product issue.

Existing product work reuses its natural issue when one issue is also one executable unit of work.
If a product issue needs several independently dispatchable units, it remains the parent and those units are represented as sub-issues.
A scout followed by an implementation is therefore either one reopened task with an auditable transition or two sub-issues when they can be scheduled independently.

Project-specific fields are canonical for fleet planning state.
Global issue properties remain shared with every project containing the issue.
The backend must not assume that another project's Status field has the same identity, options, or meaning as the fleet project's status field.

## Identity

Every adopted project item has one stable, file-safe `tasks-axi` id in a required project text field named `Task ID`.
The id remains stable when the issue is transferred, renamed, reopened, or added to another project.
The issue node id and URL are stored as external identity in task metadata.

The backend must reject duplicate non-empty Task ID values within the configured fleet project and report every conflicting issue URL.
The backend must never choose one duplicate arbitrarily.

An issue added by a human or auto-add workflow without a Task ID is an Inbox item.
It is visible but not dispatchable.
An explicit adopt operation assigns or accepts a valid Task ID, fills required fleet fields, and verifies the resulting item before it can become Ready.

Server-minted issue numbers are not used as the sole task id.
Firstmate uses task ids in filenames, locks, runtime records, dependency references, and recovery records, while issue numbers are only unique inside one repository.

## Task and project mapping

The GitHub backend maps portable task data onto issue and project surfaces.

| Task value | GitHub representation |
| --- | --- |
| `id` | Fleet project text field `Task ID`. |
| `title` | Issue title. |
| `body` | Human-owned issue body, with only a fleet-only creation marker hidden from the returned task text. |
| `state` | Fleet project single-select field `Fleet status`. |
| `kind` | Fleet project single-select or text field `Task kind`. |
| `repo` | Fleet project text field `Target repository`. |
| `priority` | Fleet project single-select field `Priority`. |
| `home` | Fleet project text field `Owning home`. |
| `hold.kind` | Fleet project single-select field `Wait kind`. |
| `hold.reason` | Fleet project text field `Wait reason`. |
| `hold.until` | Fleet project date field `Wait until`. |
| `blocked-by` | GitHub's native blocked-by issue relationship. |
| `parent` | GitHub's native sub-issue parent relationship. |
| `discovered-from` | Native sub-issue parent when singular, with additional typed origins retained as idempotently marked relationship comments. |
| PR and document links | Native linked pull requests, project fields where suitable, or idempotently marked event comments. |
| `created`, `updated`, and `closed` | Project transition metadata and GitHub timestamps, without treating issue closure as the only task state. |

The backend-owned creation marker must be bounded, versioned, and present only on fleet-only issues created by the adapter.
It lets a retry recover an issue whose successful create response was lost before its project fields were written.
Native fields, relationships, and idempotently marked comments preserve all other portable task data.
No backend-owned surface may contain credentials, raw Relay context, signed URLs, terminal output, or private runtime records.

Human edits to the issue title and body are valid issue edits.
GitHub provides no conditional write for issue updates, so the first GitHub adapter refuses wholesale body replacement rather than risk overwriting a concurrent human edit.
Append-only operational notes and retained deliverables use idempotently marked issue comments or structured links.
State-only and field-only transitions never rewrite the issue body.
Title updates use last-write verification and report drift, but callers must treat the issue body as human-owned.

## Fleet status

The portable `tasks-axi` state remains `queued`, `in_flight`, or `done`.
The richer board presentation is a deterministic projection of state, dependencies, holds, and validated landing evidence.
The adapter maps Inbox, Backlog, Ready, Blocked, and Awaiting captain to queued, maps In progress and Awaiting landing to in-flight, and maps Done to done with a delivered outcome.
Cancelled maps to done with a cancelled outcome, so retirement remains visible without claiming delivery.

| Fleet status | Portable meaning |
| --- | --- |
| Inbox | The project item has not been adopted as a task. |
| Backlog | The task is queued with an active `parked`, `future`, or `load` wait. |
| Ready | The task is queued, unblocked, and has no active wait. |
| Blocked | The task is queued with unresolved `blocked-by` relationships or an external wait. |
| Awaiting captain | The task is queued with an actionable captain wait. |
| In progress | The task is in flight. |
| Awaiting landing | The execution deliverable exists but the selected delivery contract is not yet landed. |
| Done | The task is done under its selected delivery contract. |
| Cancelled | The task was explicitly retired without delivery and retains an audit trail. |

`Awaiting landing` is a Firstmate projection over an in-flight task with a recorded PR or comparable deliverable.
It prevents a worker's successful PR creation from closing a product issue before the PR is merged or otherwise accepted.

Issue open or closed state is not the canonical fleet state.
A product issue is closed only when its repository completion policy says the work is complete.
A fleet-only issue may be closed when its fleet task reaches Done or Cancelled.
This distinction avoids globally closing an issue that still belongs on another project's active board.
GitHub Done items remain in the project for history and views, and the adapter reports that retention is backend-managed instead of applying Markdown's `done_keep` pruning.

The captain may change priority and may move an Inbox or Backlog item to Ready.
A board edit never starts a worker directly.
Firstmate validates the next observed state, records the task transition through `tasks-axi`, and then dispatches through its existing guarded path.

Firstmate owns In progress, Awaiting landing, and Done transitions because those values assert runtime or delivery evidence.
A human edit that asserts one of those states without matching evidence is reported as drift and is not treated as proof.
A captain or external wait cannot be cleared by a generic Ready drag because those waits have their own explicit resolution paths.

## Ownership and secondmate routing

Every operational home has one stable home id.
The main home uses `main`.
A seeded secondmate receives its registered id in a small home-local identity file rather than deriving authority from a mutable path or display name.

`home` is a first-class task field and maps to the fleet project's `Owning home` field.
Main Firstmate queries the whole fleet project.
A secondmate queries tasks whose home equals its stable home id.
Only the current owning home may mutate execution fields, while the captain may mutate the explicitly captain-owned planning fields.

A handoff changes ownership on the same task and same issue.
It does not copy or delete the issue and does not remove the task from the fleet project.
Dependencies remain globally resolvable because the tasks no longer live in isolated files.
The Markdown backend keeps its current dependency-closed `mv` behavior because separate files still require that protection.

A multi-task handoff does not rely on GitHub transactionality.
Firstmate writes a durable local handoff intent, accepts both the source and intended destination as replay states, applies idempotent owner changes, verifies every selected item, and sends the receiver notification only after all items match the destination.
A partial update remains visible and replayable, and the batch is not reported complete or notified until verification succeeds.
The central dependency graph means a temporarily split owner set never strands or erases dependency records.
A secondmate treats the ownership assignment as durable routed work, so an individually transferred queued task is safe even before the whole batch finishes.

## Authority and consistency

GitHub is authoritative for ordinary task planning data when the GitHub backend is selected.
Firstmate runtime records are authoritative for live execution and landing evidence.
The adapter reconciles the two only at defined lifecycle seams.

Every remote mutation follows read, plan, mutate, verify, and acknowledge.
The mutation is successful only when a fresh read proves the intended postcondition.
That fresh read resolves the item node id returned by the mutation and never the project search index, because the index lags a write by seconds and would report a successful write as absent.
Search is a discovery mechanism for locating an item whose handle is not already held.
Repeated execution with the same intent is idempotent.

GitHub GraphQL mutations are not treated as transactions, even when several fields are submitted in one request.
The backend must expect partial success, rate limiting, stale project field ids, and ambiguous network outcomes.
GitHub issue creation has no idempotency key, so a fleet-only issue is created with an exact hidden creation marker and an ambiguous retry scans recent issues back to the recorded intent time before creating again.
Ambiguous creation is the only recovery path with no item handle to verify against, so it must treat absence as unproven until a bounded retry window expires rather than creating again on the first empty result.

Project field authority is partitioned to reduce write races.
The captain owns priority and intake disposition, the current task home owns execution fields, and the routing operation owns the home field while a queued task has no live worker.
Mutations update only the field they own and verify that field after writing.
A conflicting owner or execution value stops reconciliation instead of being overwritten.

Firstmate retains a bounded durable mutation intent before changing a lifecycle assertion that cannot be reconstructed after local cleanup.
The intent names the task id, expected prior projection, desired projection, target project identity, and an idempotency digest.
Reconciliation re-reads GitHub and either confirms, safely completes, or reports a conflict.
It never overwrites a conflicting human edit without surfacing it.

A GitHub outage prevents new dispatch and final cleanup because those operations would otherwise diverge from the canonical task store.
Already-running workers continue to be supervised.
Their terminal evidence remains local until the store is reachable, after which the pending transition is replayed.

Read-only views may use a bounded local cache when GitHub is unavailable.
Every cached view states its observation time and degraded provenance.
A cached view never authorizes a mutation or dispatch.

## Projection and query ownership

The `tasks-axi` domain layer owns portable state, hold activity, dependency resolution, and the Ready, Blocked, and Held projections.
Adapters return a complete active-task snapshot plus the dependency closure needed for those derivations.
The GitHub adapter may satisfy that contract with server-side project queries and batched issue-node reads rather than a full project scan.

Firstmate owns fleet-specific projections such as current role, whether child runtime metadata is required, and whether a captain wait is actionable today.
Those projections consume structured task and runtime fields rather than GitHub details.
The existing prose-derived deferred marker is not portable and must be converted to structured waits during migration rather than reimplemented against issue-body excerpts.

An exact task lookup uses the Project items query filter for the configured Task ID field and then verifies an exact field value.
Field-scoped narrowing is exact rather than prefix, but it is case-insensitive, so task ids are minted from a case-normalised alphabet and the returned values are still compared exactly.
It returns every exact match so duplicate ids remain a hard error without scanning the full project.
A full active snapshot runs outside per-task runtime locks, excludes historical Done items unless requested, paginates to completion inside a declared time and item bound, and records observation freshness.
A per-task transition uses an exact lookup and a hard network timeout while its local lifecycle lock is held.
No dispatch path performs an unfiltered project scan.

## Proposed portable interface

The CLI command layer should call a backend-neutral task module, and that module should be the only caller of Store adapters.
The task module owns idempotent command semantics and portable projections, while each Store adapter owns persistence mechanics and query planning.

The following TypeScript shape is the intended interface, with naming open to upstream review but responsibilities fixed.

```ts
interface Capabilities {
  backend: string;
  bodyReplace: boolean;
  collectionTransfer: boolean;
  comments: boolean;
  customStates: boolean;
  dependencies: boolean;
  fullTextSearch: boolean;
  hardRemove: boolean;
  ownershipTransfer: boolean;
  prune: boolean;
  publicFollowups: boolean;
  realtimeSync: boolean;
  serverMintsIds: boolean;
  structuredSnapshot: boolean;
}

interface Task {
  id: string;
  title: string;
  state: "queued" | "in_flight" | "done";
  home?: string;
  repo?: string;
  kind?: string;
  body?: string;
  deps: Dep[];
  links: TaskLink[];
  hold?: Hold;
  priority?: number;
  created?: string;
  updated?: string;
  closed?: string;
  outcome?: "delivered" | "cancelled";
  public_followup?: PublicFollowup;
  meta?: Record<string, unknown>;
}

interface TaskQuery {
  state?: "queued" | "in_flight" | "done";
  home?: string;
  repo?: string;
  kind?: string;
  limit?: number;
}

interface TaskSnapshot {
  items: Task[];
  dependencyClosure: Task[];
  total: number;
  complete: boolean;
  observedAt: string;
  source: "live" | "cache";
}

interface TaskEvent {
  key: string;
  kind: "note" | "deliverable" | "resolution";
  body: string;
  links?: TaskLink[];
}

interface OwnershipTransfer {
  operationId: string;
  taskIds: string[];
  from: string;
  to: string;
}

interface Store {
  capabilities(): Capabilities;
  create(input: TaskInput): Promise<Task>;
  get(id: string): Promise<Task | null>;
  update(id: string, patch: TaskPatch): Promise<TaskUpdateResult>;
  cancel(id: string, reason: string): Promise<Task>;
  remove?(id: string): Promise<Task>;
  snapshot(query: TaskQuery): Promise<TaskSnapshot>;
  transition(id: string, to: State, opts?: TransitionOpts): Promise<Task>;
  addDep(id: string, dep: Dep): Promise<boolean>;
  removeDep(id: string, dep: Dep): Promise<boolean>;
  appendEvent?(id: string, event: TaskEvent): Promise<Task>;
  transferOwnership?(intent: OwnershipTransfer): Promise<Task[]>;
  transferCollection?(ids: string[], target: Store): Promise<Task[]>;
  updatePublicFollowup(id: string, mutation: PublicFollowupMutation): Promise<Task>;
  prune?(options: PruneOptions): Promise<PruneResult>;
}
```

A capability set is part of the interface rather than documentation about an adapter.
The task module refuses a command before mutation when its required capability is false or its optional method is absent.
The Markdown adapter implements collection transfer, body replacement, hard removal, pruning, and public follow-ups.
The first GitHub adapter implements ownership transfer, cancellation, and comments, but not collection transfer, body replacement, hard removal, pruning, or public follow-ups.

The structured snapshot is deliberately deeper than a page of tasks.
It gives the portable task module all dependency states needed to derive readiness without forcing the command layer to fetch an entire remote project or learn adapter pagination.

## Proposed GitHub configuration

GitHub configuration names durable resources and expected field shapes rather than storing field node ids as authority.
A representative project configuration is as follows.

```toml
backend = "github"

[github]
issue_repository = "keithteam/fleet-ops"
project_owner = "keithteam"
project_number = 10
task_id_field = "Task ID"
status_field = "Fleet status"
home_field = "Owning home"
kind_field = "Task kind"
priority_field = "Priority"
target_repository_field = "Target repository"
wait_kind_field = "Wait kind"
wait_reason_field = "Wait reason"
wait_until_field = "Wait until"
cache_ttl_seconds = 30
request_timeout_seconds = 10
snapshot_timeout_seconds = 30
```

The home identity is supplied by Firstmate's home-local identity record rather than duplicated in shared project configuration.
The adapter resolves field and option node ids by configured name and expected type, caches them as an optimisation, and invalidates the cache after any not-found or type-mismatch response.

## Required `tasks-axi` work

The implementation should be proposed upstream in small portable changes.

1. Add a structured snapshot surface that returns complete, untruncated tasks, dependency closure, total counts, completeness, observation time, and active capabilities.
2. Add a machine-readable capability command so callers probe named features rather than infer them from version numbers or help text.
3. Make `home` a first-class field on `Task`, `TaskInput`, `TaskPatch`, and `TaskQuery`.
4. Add a backend-neutral ownership-transfer operation and command with explicit source, destination, batch results, and idempotent replay semantics.
5. Add separate `collectionTransfer`, `ownershipTransfer`, `bodyReplace`, `hardRemove`, `comments`, `prune`, and `publicFollowups` capabilities rather than type-testing an adapter.
6. Separate retained cancellation from physical removal, with a portable delivered-or-cancelled outcome that does not require issue deletion.
7. Add an append-only, idempotent comment or event operation so remote backends can record notes and retained deliverables without replacing a human-owned issue body.
8. Make `done` report that retention is backend-managed when `prune` is false, and never silently delete, close, remove, or archive project items to emulate `done_keep`.
9. Extend configuration with a `[github]` table for issue repository, project owner and number, field names, status mappings, and bounded cache settings.
10. Replace the hard-coded Markdown constructor in `resolveTasksContext` with a backend registry or factory seam.
11. Implement `GithubStore` CRUD, snapshots, native dependency relationships, ownership transfer, cancellation, comments, pagination, bounded retries, creation-marker recovery, and postcondition verification.
12. Refuse wholesale body replacement in the first GitHub adapter because GitHub offers no conditional issue-update operation.
13. Declare receipt-gated public follow-ups unsupported until their atomic compare-and-swap revision and completion contract has an equivalent remote implementation.
14. Keep Markdown collection transfer behind its declared capability, but remove every command-layer `instanceof MarkdownStore` branch.

The portable Store interface should remain small and express domain operations rather than file paths or GraphQL mechanics.
GitHub field ids, GraphQL queries, pagination, retries, issue adoption, and project provisioning stay inside the adapter implementation.
Firstmate should not learn those details.

## Required Firstmate work

Firstmate needs backend-neutral changes around the existing lifecycle calls.

1. Change `bin/fm-fleet-snapshot.sh` to consume the structured active-task snapshot and retain only Firstmate-specific derivations.
2. Change `bin/fm-backlog-transition-lib.sh` to detect configured store availability rather than require `data/backlog.md` for every backend.
3. Replace the scalar compatibility verdict in `bin/fm-tasks-axi-lib.sh` with per-operation capability checks whose process-hop memo cannot survive an executable change.
4. Make session-start rendering use structured task output and disclose cache age, completeness, or store unavailability.
5. Keep one handoff and receiver-notification protocol, but select Markdown collection transfer or GitHub ownership transfer through declared capabilities.
6. Persist one stable home id during home seeding and pass it to task queries and ownership mutations.
7. Preserve the current paired-transition and close-marker recovery invariants while remote calls become bounded and replayable.
8. Move captain-held teardown deliverables onto a structured link or idempotent event before GitHub work, while still running on Markdown.
9. Make Bearings and fleet views render Inbox, ownership, Ready, Blocked, Awaiting captain, Awaiting landing, and data freshness from one snapshot contract.
10. Publish Awaiting landing only from validated PR metadata recorded by the PR check, never from a URL scraped from status prose.
11. Make migration refuse while any participating home has an unresolved backlog-close marker or a task transition under way.
12. Make Relay activation and each public-followup creation check the active backend capability before any public promise is made.

The first GitHub release refuses configuration on a Relay-enabled home because it cannot preserve receipt-gated public obligations.
Adding a Relay token after startup also prevents Relay activation, and the obligation-creation command refuses before a promise is recorded or sent.
A future composite store may route private obligation kinds to a local adapter and ordinary tasks to GitHub, but it is not required to make ordinary GitHub tasks safe.

## Project provisioning

Provisioning is explicit and idempotent.
It verifies the repository, project, field types, option names, visibility, and caller permissions before importing tasks.
It resolves field and option node ids from configured names on each cold start and may cache them with the project node id.
A missing, duplicated, or wrong-typed required field is a configuration error rather than an invitation to create or rename production fields automatically.

The recommended views are as follows.

- Captain prioritisation shows Inbox, Backlog, and Ready grouped by Priority.
- Underway shows In progress and Awaiting landing grouped by Owning home.
- Waiting on captain filters actionable captain waits and issues assigned to the captain.
- Blocked shows external waits and unresolved dependencies.
- Recently done orders completed work by the fleet completion timestamp.
- All fleet work shows every item, including cancelled and parked work.

Auto-add workflows may place repository issues assigned to the captain into Inbox.
Auto-add does not make them dispatchable until adoption supplies the required fleet identity and ownership fields.

## Migration

Migration runs as a dry-run inventory before any GitHub mutation.
The inventory classifies each live Markdown task as adopt an existing issue, create a fleet issue, conflict, or unsupported.

An existing issue is adopted only from an exact unambiguous issue link or an explicit mapping supplied by the captain.
Task ids are preserved in the Task ID field.
Task bodies are not used for fuzzy issue matching.
Multiple tasks pointing at one issue are a conflict unless one is intentionally represented as a sub-issue or recorded execution attempt.

Queued and in-flight tasks are migrated first.
The recent Done window may be migrated for continuity.
The historical done archive remains an immutable local export unless a separate archival import is requested.

Cutover requires a quiet dispatch window.
It refuses while any participating home has an unresolved `state/*.backlog-close` record, live transition intent, or task whose runtime record and backlog state disagree.
The migrator snapshots Markdown bytes, writes or adopts every issue, verifies a complete GitHub projection, switches configuration, runs the backend-neutral fleet snapshot, and retains the original files read-only for rollback evidence.
Rollback changes configuration back to Markdown only before any GitHub-originated task edit has been accepted.
After GitHub accepts edits, rollback is an explicit reverse migration rather than a blind config flip.

## Acceptance scenarios

The approach is acceptable only when the following scenarios pass through public commands.

1. A fleet-only task is created, appears in Inbox, is adopted, prioritised, made Ready, dispatched, and completed with its issue and project history intact.
2. A lost successful issue-create response is retried without creating a duplicate issue.
3. An existing product issue appears in both its product project and the fleet project, while changing Fleet status leaves the other project's status unchanged.
4. A product issue reaches Awaiting landing only from validated PR metadata and remains globally open until the configured landing evidence arrives.
5. A secondmate handoff changes home on the same issue, survives a failure after one remote owner write, and wakes the receiver only after verification.
6. A crashed sender can replay a partially applied ownership batch when some items already name the destination.
7. A dependency remains resolvable when blocker and dependent have different owning homes.
8. A captain-held task can retire its worker, record the deliverable without rewriting the issue body, remain open, and replay the retained transition idempotently.
9. A captain wait remains visible and cannot be cleared by an unrelated Ready edit.
10. A duplicate Task ID prevents dispatch and reports every exactly matching issue without an unfiltered project scan.
11. An unadopted auto-added issue remains visible but cannot be dispatched.
12. A GitHub outage prevents new dispatch, preserves running work, and later replays completion without duplicate comments or transitions.
13. A rate limit or ambiguous response between local runtime publication and remote start preserves or reconstructs the runtime-to-task invariant.
14. A stale project field id is refreshed by name or reported as a typed configuration error without writing another field.
15. Active-task pagination returns every matching task and reports an explicit bound rather than silently truncating the backlog.
16. Exact task lookup and transition complete inside the declared network and lock-hold budget on a board larger than the expected fleet.
17. The same structured task set produces the same Ready, Blocked, Held, and captain-actionable sets on Markdown and GitHub, including a due-today wait and a missing blocker id.
18. With `done_keep = 10` and eleven GitHub Done tasks, the eleventh remains available and `done` reports that retention is backend-managed.
19. Cancelling a task retains a visible cancelled outcome without deleting its issue, while unsupported hard removal refuses before mutation.
20. The Markdown backend continues to pass its existing command and cross-file handoff tests unchanged.
21. GitHub selection and later Relay activation both refuse before any unsupported public promise can be made.
22. Migration refuses while any participating home has a pending close marker.
23. A mid-session `tasks-axi` executable or capability change invalidates the inherited compatibility memo before another mutation.
24. A human body containing Markdown that resembles task metadata is preserved as prose and never parsed as a dependency.
25. A future released `tasks-axi` backend improvement is consumed by upgrading the dependency without copying adapter code into Firstmate.

## Rollout

The rollout should remain reversible until the first captain-authored GitHub task edit is accepted.

1. Upstream the structured read and capability surfaces without changing Markdown behavior.
2. Make Firstmate snapshots and compatibility checks backend-neutral while still running on Markdown.
3. Upstream the GitHub adapter and verify it against a fake transport plus an isolated live project.
4. Add GitHub ownership routing while retaining Markdown `mv` for Markdown homes.
5. Dry-run migration and resolve every identity conflict.
6. Run one secondmate domain on GitHub while main remains able to render the whole fleet.
7. Switch ordinary main-home tasks after the canary survives dispatch, handoff, outage, replay, and landing.
8. Refuse GitHub selection or Relay activation when the home needs unsupported public follow-ups.
9. Add a composite store only when Relay support is deliberately brought into the GitHub-backed home.

## Rejected alternatives

A read-only GitHub mirror is rejected because captain edits would either be ignored or require a reverse synchronization protocol.
A bidirectional Markdown mirror is rejected because there is no deterministic conflict winner that preserves both human board edits and Firstmate's local lifecycle assertions.
A Firstmate-private GitHub implementation is rejected because it would duplicate the existing `tasks-axi` seam and miss future upstream backend improvements.
One GitHub project per secondmate is rejected because ownership transfer would again move work out of the captain's single fleet view.
Using global issue closure as the fleet state is rejected because the same issue may remain active in another project until delivery lands.
Using issue assignees to represent secondmates is rejected because operational homes are not GitHub users and assignee changes carry repository-wide meaning.
