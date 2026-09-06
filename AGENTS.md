# AGENTS.md — Maintainer Guidelines for entwurf

For agents that own this repo: invariant principles and reproducible verification, not release-story archaeology.

> **Direction.** This repo is the **entwurf capability package**: a v2 garden-citizen dispatch substrate, native-harness bridges, an ACP plugin, and the pi adapter that hosts that plugin today. `entwurf` is the subject; pi is one harness adapter. ACP is a plugin, not the boundary (#38). V1 verbs are gone. V2 addresses existing citizens; fresh sibling creation is the separate `entwurf_fresh_call` capability. Current work and ordering live in [NEXT.md](./NEXT.md).

## North Star — One Forged Screwdriver

`entwurf`는 스위스 아미 나이프나 두 번째 하네스가 아니다. 이것은 **담금질된 드라이버 한 자루**다: 작고, 명시적이고, 맡은 접점에서만 강해야 한다.

- **entwurf가 주어이고 pi는 한 adapter다.** pi는 가장 깊게 붙은 하네스지만 다른 하네스보다 높은 정체성 계층이 아니다.
- **다른 하네스의 세션은 형제다.** Claude Code, Codex, Antigravity, pi는 각자의 transcript/auth/runtime을 소유한다. 증명된 lifecycle과 transport가 있을 때 같은 garden address space의 citizen이 된다.
- **능력을 surface 이름으로 재단하지 않는다.** 도구 이름이나 transport 비대칭은 capability 차이이지 존재의 등급이 아니다.
- **substrate는 결정적 dispatch만 맡는다.** record에서 identity를 읽고, rail별 liveness와 caller intent로 transport를 고른다. 숨은 hydration, ambient MCP scanning, 근거 없는 tool claim을 만들지 않는다.
- **좁은 tool surface는 규율이다.** entwurf가 backend를 몰 때 sub-agent/todo 없이 한 자루 드라이버로 움직인다. 두 번째 orchestrator로 자라지 않게 한다.
- **entwurf는 부속품이 아니라 분신을 연다.** resumed/spawned session은 runtime-isolated peer이지 disposable worker가 아니다.
- **증거가 말을 훈육한다.** README, source, gates, VERIFY, BASELINE이 받치지 않는 강한 주장은 멈춘다.

판단할 때 묻는다:

1. tool 이름을 보는가, capability를 보는가?
2. backend 비대칭을 정직하게 기록하는가, 형제성을 포기하는 핑계로 쓰는가?
3. 두 번째 하네스를 만드는가, 드라이버 한 자루를 단단하게 만드는가?
4. 이미 주어진 방향을 되묻는가, 실행 가능한 다음 증거를 만드는가?

## Architecture

- **entwurf-core (v2)** owns garden-id addressing, peer facts, liveness interfaces, dispatch decisions, rail choice, and delivery evidence.
- **Record authority** owns citizen identity. Every addressable citizen uses the same V3 `MetaIdentity` schema. `backend` selects capability/rail behavior; it does not create an identity hierarchy.
- **pi adapter** attaches a pi session to a record at `session_start`, hosts the record-keyed control socket, and exposes the native pi tool surface.
- **Native bridges** register already-running native sessions without taking over their transcript or auth: Claude Code and Copilot CLI are mailbox/self-fetch (a Claude hook arms the watch; a forked Copilot extension holds it); Antigravity is probe-backed native-push. Codex has archived probe evidence, but its managed native lane was declined because pi already supplies the official GPT provider path; do not duplicate it as a native citizen or ACP backend.
- **ACP plugin** registers provider `entwurf` inside a pi host session and drives a backend under an isolated overlay. The host pi session is already a record-backed socket citizen; the plugin does not mint another citizen/socket/peer layer.
- **mux is launch-only and deliberately small.** Shipped: the tmux placement leaf (`mux-placement.ts` — inspect/append/close inside the caller's own session), the visible runtime launch composition (`mux-launch.ts`), the fresh-call composition (`mux-fresh-call.ts`), and the cwd-aware resume placement composition (`mux-resume-call.ts`). Fresh call is exposed as `entwurf_fresh_call`; visible same-id resume is `entwurf_resume_call`, composed at the two public surfaces by injecting `mux-resume-call` into the v2-side `entwurf-v2-visible-resume.ts`. The exact import graph is enumerated in [docs/mux-launch-rail.md](./docs/mux-launch-rail.md) §11. `entwurf_v2` behavior is unchanged and delivery still never imports launch. Fresh call learns a new sibling's garden id from the CALLBACK it makes, never from a lookup — so the pre-injected-token → identity-lookup design (rail §6) is **closed, not paused**. Do not reopen it without new evidence and explicit GLG re-approval. Fresh-call requires one explicit model and passes it in each runtime's measured CLI dialect (Pi `--model <provider/model>`, Claude Code `--model=<id-or-alias>`, Copilot `--model <name>` beside `--interactive <prompt>` and the explicit `--yolo` policy — a GLG width decision, 2026-08-25, after a callback-only `--allow-tool` grant stopped the sibling at every task tool); the Copilot backend opens through entwurf's OWN managed invocation (`entwurf copilot`), never the bare vendor, and its four required capabilities — birth, MCP hand, receiver, visible footer — are decided by `copilot-fresh-preflight.ts` BEFORE the tmux mutation, so a missing unit is a named refusal instead of a dead window; it also takes ONE optional literal absolute `cwd` (#73 — omitted/`""` means the caller's own directory; no trim, no realpath, no project-name resolver; classified by the shared `classify-tmux-cwd.ts` leaf; the receipt echoes the REQUEST only), so a cross-repo fresh sibling is a fresh-call fact and never a reason to resume a dormant record. Resume takes only an existing target id and gets transcript/model/provider/cwd from its record. Do not grow either narrow carrier into a generic driver, harness profile, arbitrary command/env selection, or a second creation API. Ownership and import prohibitions: [docs/mux-launch-rail.md](./docs/mux-launch-rail.md) §11.
- **One delivery verb:** `entwurf_v2` addresses an existing garden id. Current routes are live control-socket send, active self-fetch mailbox enqueue, and probe-alive native-push. NO route starts a process: the hidden background resume for a dormant citizen was withdrawn under the visible-first rule, so a dormant in-domain citizen rejects as `dormant-fire-forget-unsupported` and the intent axis is single-valued. Every other complementary state pair rejects honestly too. Fresh creation is a separate verb — `entwurf_fresh_call` — and it returns a launch receipt only; the new sibling's address arrives asynchronously as the sender envelope of its nonce callback.

## Hard Rules

1. **One surface name, hard cut.** Runtime/provider/routing identity is `entwurf`. No permanent aliases, legacy readers, or hidden dual routing. One-shot migration or documented break only.
2. **The record is the sole garden address authority.** A socket, env var, marker, filename, model id, or transcript id is never an independent address axis. `PI_SESSION_ID` is only a child-process carrier for the garden id already established by pi's record birth.
3. **All citizens share one identity contract; rails differ by capability.** The control-socket liveness domain currently contains backend `pi`; self-fetch and native-push have different predicates. Branch on capability/domain, not on a privileged notion of “pi citizen.”
4. **Dispatch is computed from live facts.** Never store liveness. Never infer send/resume from session type before resolving the target and probing its rail.
5. **Rejects are real.** Wrong intent, dead/drifted identity, undeliverable mailbox, ambiguous address, or indeterminate probe returns a reject and mutates nothing. No cosmetic success or silent fallback.
6. **MCP is explicit.** Only explicit `mcpServers` wiring. No ambient `~/.mcp.json` scan or automatic retrieval.
7. **Meta-record store contract is one contract.** Record body is authority; filename must agree with the body; every active entry is a regular non-symlink file readable by the live V3 schema; `nativeSessionId` ownership is unique. Identity writers and doctor certify the whole active store before writing. Address-bearing reads use `readAddressableMetaIdentity`; targeted relay reads keep the documented per-entry contract. `readStoreRecordFile`/`O_NOFOLLOW` and the lstat policy layer are both load-bearing—do not merge or bypass them. No legacy reader/migrator: quiesce and run `entwurf meta-bridge-fresh-cut` when the generation is unreadable. An unknown-backend defect is a stale deployed reader, not a rotten generation: redeploy the sibling unit; do not fresh-cut. `doctor-meta-bridge` already names that — run it after `META_BACKENDS` changes. Source and gates: `meta-session.ts`, `check-meta-*`, `check-fresh-cut-gate`.
8. **GC reclaims process resources, never memory/data.** Records and transcripts are preserved or archived; they are not casually deleted.
9. **This is not a second harness.** No prompt reconstruction, transcript hydration, tool-result ledger, credential mediation, or harness emulation. Each backend owns auth and transcript state.
10. **Native-push is its own rail.** It is not a mailbox or pi socket in disguise. Antigravity replyability is record-backed plus probe-alive; no receiver marker, watch state, or resume authority is invented for it.
11. **Package proof must model a consumer.** Operator entrypoints reach compiled JS when installed; `run_ts` is the single TS crossing. Keep `check-install-surface`, `check-pack-install`, and the checkout-invisible `check-install-container` distinct. A green clone is not a green tarball or consumer.
12. **Offline verification never rewires the operator.** Sandbox `HOME`, `PI_CODING_AGENT_DIR`, and every writable `XDG_*` root. LIVE gates alone may touch the real host and must say so. Keep static tripwires and dynamic outer self-fences; neither substitutes for the other.
13. **Doctors report runtime truth and ownership truth separately.** Runtime coverage does not prove entwurf owns the configuration; broken ownership does not erase visibly working runtime configuration. Final verdict remains red when either required axis fails.
14. **Native hook ownership is structural.** Claude hooks use the shipped exec-form launcher and provenance token; marker writers/readers share `isPlausibleOwnerPid`; no shell-form fallback, ancestry guess, or retired pid carrier. entwurf requires Claude Code `>=2.1.217` and enforces that floor itself because upstream gives no fail-loud — an older Claude validates the exec manifest, then drops `args` at runtime and reports success. The number is derived from `package.json` `entwurf.claudeCodeFloor`, never retyped as a second source. Currently certified axis is Linux desktop/workstation. Source/gates: `hook-launch.sh`, `meta-session.ts`, `check-hook-launch-topology`, `check-claude-floor-coherence`, `check-meta-doctor-oracle`.
15. **Crash, don't warn.** Bad config/path/model/store state throws. Empty catches are only for bounded environment probing; operator diagnostics go to stderr.
16. **mux is launch, never delivery.** A tmux window/pane handle is an ephemeral operator view, not an address: it mints no garden id, stores no record, and reports no liveness. Screen text and keystrokes are never an `entwurf_v2` receipt. Mux owns only placement and fixed-runtime launch; fresh identity correlation stays in callback envelopes, while same-id resume identity/liveness/locking stays on the v2 side of an injected launch seam.
17. **Entwurf installs itself; setup composes what the operator already chose.** Package installation and source bootstrap supply Entwurf's own bytes, bins, dependencies and development fixtures only. They never install a harness binary, subscription, credential or login — `pi` has no privileged exception. `setup` detects already-present harnesses by capability and completes each detected integration; absence is an explicit zero-state SKIP, while a detected-but-incomplete integration is named non-green rather than cosmetic success. Source-only pinned Pi dev dependencies are build/test fixtures, not a product promise that neutral npm consumers receive Pi. Installation portability and rail/runtime support are separate evidence axes: Linux proof never certifies macOS or native Windows, and WSL counts as Linux rather than Windows.

Detailed incident histories belong in CHANGELOG/issues/BASELINE and source-adjacent comments, not in this prompt. When a concise rule and old archaeology disagree, verify source + gate and repair the stale prose.

## ACP Plugin Boundary

| Layer | Owns |
|---|---|
| **entwurf-core** | identity/fact interfaces · dispatch table · delivery evidence · rail choice |
| **ACP plugin** | backend process lifecycle · isolated overlay · tool narrowing · per-backend ACP dialect · turn evidence |
| **ACP plugin does not own** | citizen registration · socket registry · peer protocol · memory DB · planner/orchestrator · auth |

- One `entwurf` provider, model-id routing, adapter resolved once at turn entry. Backend-specific settings remain opaque behind `adapterSettings`.
- The common turn sequence stays backend-invariant: spawn → initialize → newSession → enforceModel → prompt → event map.
- Rich operator/project context rides the **first user message augment**, not a large system prompt. The actual callable schema is the tool truth; prose never grants a tool.
- A backend may have no carrier or use launch-time model pinning; those asymmetries stay inside its adapter.
- A streaming assistant message starts `pending`. ACP terminal reasons are mapped explicitly; refusal, exhausted turn budget, unknown, or absent reasons end as errors, and the raw reason is preserved. Never restore a default-to-success branch.
- Bootstrap steps carry wall-clock bounds; a running prompt does not. A turn ends only when the agent answers, the operator aborts (ACP `session/cancel` first, bounded cleanup after), or the child dies. Elapsed time is not evidence, and a prompt-phase failure we author must never read as transient to pi's retry classifier — a cutoff plus blind retry replays the whole prompt from cold.
- Claude is the reference adapter. Cortex is the second landed adapter (0.13.0): session-scoped dual-HOME containment, overlay-private `mcp.json` projection (its ACP server ignores the wire `mcpServers` param), `CORTEX_HOME` presence refusal, per-turn set-model. Current contract: `docs/acp-backend-rail.md` “Cortex Code audit (D1–D10)”.
- entwurf never supplies, copies, proxies, decrypts, or bypasses vendor credentials/subscriptions. It uses the operator's existing local authenticated backend.

## Citizen Identity and Dispatch

### One record axis

A `--entwurf-control` pi session is a citizen for the same reason a native bridge session is: it has a V3 meta-record.

- pi owns its native session id, filename, transcript, name, `/new`, `/fork`, `/clone`, and `/resume` lifecycle.
- `birthPiCitizen` upserts `(backend:"pi", nativeSessionId)` and receives the stable `gardenId` from the record.
- The control socket is `~/.pi/entwurf-control/<gardenId>.sock`; a record-less socket is a diagnostic, never a citizen.
- `PI_SESSION_ID` and `PI_AGENT_ID` propagate the record-established identity to child MCP processes. They are carriers, not a second authority.
- If record birth fails, no socket starts and no `PI_SESSION_ID` is exported.
- Reopening the same pi native session attaches to the same record; in-process replacement creates/attaches the replacement's own record.
- Resume is shipped as its OWN verb, `entwurf_resume_call {target}` — never as an intent on delivery. It reopens a DORMANT pi citizen under the same garden id in a visible window, and it runs no turn: the window comes back with the conversation and waits. The record supplies transcript, model, provider and cwd, so there is no prompt, no task and no model override. The record-authoritative preconditions live in `resume-launch-identity.ts` / `check-resume-launch-identity` (record existence, transcript-header ↔ `record.nativeSessionId` integrity, addressable-read uniqueness, an absolute recorded transcript, model preservation) and now have a consumer.

### Capability domains, not rank

- **control-socket domain (currently `pi`)**: socket liveness, per-target lock, live send, and a dormant cell that rejects.
- **No relaunch transport exists inside delivery.** `spawn-bg` — a detached, window-less resume child — was removed under the visible-first rule, not deprecated behind a reject, and `entwurf_v2` still starts no process: a dormant socket-domain citizen is refused as `dormant-fire-forget-unsupported`. Reopening one is the separate lifecycle verb `entwurf_resume_call`, which is pi-only (`target-not-pi` otherwise), returns a LAUNCH receipt and an OBSERVATION receipt that are never merged, releases its per-gid lock on every path, and on an unobserved socket leaves the visible window open rather than retrying. No watcher, no retry, no supervisor. Do not re-route it through `entwurf_v2` and do not describe a spawn domain that does not exist.
- **self-fetch domain (Claude Code, Copilot CLI)**: active receiver + mailbox deliverability; no resume authority. The two arm that receiver through different vendor surfaces — a Claude hook that emits watchPaths, a Copilot first-party extension that holds the watch in a forked child — and the marker records which, because the pid a reader verifies differs. A live marker is not by itself an armed doorbell: where the watch owner IS the process the sender marker is keyed to (`ownerKind: claude-code-cli`), that owner may switch sessions in place, so deliverability also requires its sender marker to still name the same garden. That join is `ownerKind`-scoped by construction — a Copilot watch lives in a forked child with its own pid, so the join does not exist there and must never be applied to it (#101).
- **native-push domain (currently Antigravity)**: adapter probe + direct injection; no mailbox and no resume authority.
- `origin: "pi-session" | "meta-session" | "external-mcp"` records sender provenance. It is not the citizen identity schema and not a hierarchy.
- `entwurf_peers` reports record citizens and liveness facts only. It never embeds routing verbs or socket addresses for peers.
- `entwurf_self` is identity-required. For pi, its env carrier must have been planted from record birth; native marker identity must be backed by the matching record. Replyability is derived from the active rail, never hardcoded.

### Send-is-throw

- Delivery returns an ack/receipt, not the peer's turn result. If a reply is wanted, say so and set `wants_reply`; that flag is etiquette, not ownership.
- Sender envelope: `{ sessionId, agentId, cwd, timestamp, origin?, replyable? }`.
- Human-opened and spawned/resumed siblings use the same addressing and messaging semantics.

## Issue queue — a manual sweeper, not a backlog

- **Two caps, and the inner one is what disciplines the work.** OPEN issues are capped at **ten** in total; of those, **implementation issues — the ones that will go out on a branch — are capped at five**. A sixth implementation issue means one closes first; that inner cap does not bend.
- **What sits outside the implementation five:** research issues, and issues GLG keeps open to look at. These are not slots to be earned or swept — a research lane may stay open across releases, and a north-star issue other repos read may never close. They still count toward the ten, so the queue cannot grow without limit.
- Classify by destination, not by size: if closing it produces a diff, it is an implementation issue. If closing it produces a decision, a document, or nothing, it is not.
- A slot is earned by a current defect or executable contract, not by importance, age, or possible future value.
- Direction, philosophy, frozen invariants and observations without a current action live in `ROADMAP.md`, durable docs, or closed history.
- Nothing stays open "in case." If a closed problem recurs, it returns as a new issue carrying the new evidence.
- Anything whose only value is knowing it gets moved to the document that owns it, then closed.
- A new issue brings the best available observation plus an executable next measurement. Recovering a missing signature may be the first acceptance; an idea with neither evidence nor a next measurement is not an issue.
- No collection points, umbrella trackers, or fallout buckets. Merge issues only when they share one cause and one acceptance.
- Sweep manually after a release and before opening an issue. Solved work closes at its durable SHA; it does not wait for the next release.
- **An issue body is a snapshot; the thread is the live contract.** A body written before GLG stated what the work is *for* will disagree with the thread, and a reader who opens only the body inherits the stale half — including its fences, which is how a fence once forbade the very deliverable the lane existed to produce (#82, 2026-08-20). When they disagree the thread wins. Whoever notices owes the body an edit that strikes the withdrawn clause and says why it was there; deleting it silently makes the queue tidy and the lesson invisible.

## Verification

Two axes are required: deterministic/package gates and opt-in LIVE evidence.

```bash
pnpm typecheck
pnpm check              # everyday core — prints total wall time; ≤60s on oracle
pnpm run check:full     # full deterministic floor — core + hermetic/package tiers
./run.sh check-entwurf-v2-matrix
./run.sh check-meta-session
./run.sh check-entwurf-bridge-boot
./run.sh check-install-surface
./run.sh check-install-container       # require Docker in release acceptance

LIVE=1 ./run.sh release-gate /path/to/scratch --cut
LIVE=1 ./run.sh smoke-acp-socket-citizen-live
LIVE=1 ./run.sh smoke-acp-bundled-mcp-live
LIVE=1 ./run.sh smoke-acp-v2-send-live
LIVE=1 ./run.sh smoke-mux-lifecycle-live
LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> ./run.sh smoke-acp-cortex-live   # on-demand; outside the claude release floor
LIVE=1 AGY_CONVERSATION_ID=<id> ./run.sh smoke-agy-native-push-live
```

- The deterministic floor is tiered (#70). `pnpm check` is the everyday core — toolchain (lint + typecheck), the vitest lanes, and the pure-unit / behavioral-contract / source-topology gates plus the cheap static coherence checks. It prints its own total wall time; acceptance is ≤60s on the reference host `oracle` (an operator measurement, never a hard wall-clock gate on arbitrary hosts). `pnpm run check:full` is the full deterministic floor — the core plus the hermetic-integration and package/install tiers — and is what the candidate protocol, push CI, release-gate, and `prepublishOnly` run. Exact membership is the named `check:*` group scripts in `package.json` (the executable SSOT); a gate changes tier by semantic-class decision, never because it happened to get faster or slower. The full tier carries `check-gate-manifests` (the qualification HEAD, through `check:hermetic`); the everyday core does not, and neither tier carries the mutant-executing `check-gate-qualification`, which is scheduled separately (below).
- **Kill-proof discipline (gate qualification).** A gate is a test only if re-planting a closed defect turns it red for the claimed reason. `check-gate-qualification` proves that automatically: committed mutants in `scripts/mutants/` must be KILLED at their `[QK:<claim>]` signature inside an isolated snapshot repo (control→mutant→restore→control; the real checkout is never written). Gates a release touches carry such manifests; assertion counts are never evidence — claim IDs + killed mutant IDs are. `check-agy-permission-matrix` holds the enumerated permission contract space; matrix cells change by axis/rule edits, never by appending cases.
- **When changing a contract/gate:** name the production subject and an oracle independent of it; give the failing assertion a stable `[QK:<claim>]` label and add/update the exact-once mutant in `scripts/mutants/*.json`; if the contract is combinatorial, update the literal matrix axes/cells/exclusions together with their declared counts; then verify the focused gate, and let qualification and the full floor follow the scheduling contract below — once on the frozen candidate, not once per amendment. `MUTANT-STALE`/`SURVIVED`/`WRONG-REASON`/`CONTROL-RED`/`HANG`/`IMPURE` are red — never substitute an assertion count for a kill.
- Run LIVE gates with `PWD` in scratch so session artifacts do not land in the repo. Strip `CLAUDE_CONFIG_DIR`, `PI_SESSION_ID`, and `PI_AGENT_ID` from the gate process — a live pi/ACP session exports them into children, where they strip Claude hooks or capture a fresh-call callback.
- Release acceptance and evidence levels are defined in [VERIFY.md](./VERIFY.md); recorded host evidence is in [BASELINE.md](./BASELINE.md).
- A failed gate or evidence downgrade blocks commit/release. Pipes can be connected and the water can still taste wrong.

### Verification scheduling — when the floor runs

Gate quality and gate scheduling are different axes: the gates above define *what* green means; this contract owns *when* each layer runs. It exists because repeating the full floor around every review amendment once cost more than the work it verified (history: CHANGELOG/git).

```text
implement → affected focused gates → independent review → one amendment bundle
          → [gate/mutant changed? check-gate-qualification once] → pnpm run check:full once on the frozen candidate → commit
```

- **Inner loop:** run only the gates whose subject changed. Do not open the full floor to learn what a focused gate already answers.
- **Review before floor:** independent review and its corrections close as one bundle before the full floor runs.
- **Qualification is scheduled, not ambient — but its HEAD is not.** The mutant-EXECUTING body, `check-gate-qualification`, is not in the default check chains (core or full), so the operator inner loop never re-pays the full mutant inventory. It runs standalone once when a lane changed a gate, mutant, or matrix; machine time re-proves it everywhere else — the CI `check` job runs it on a branch push whose two-dot range touched the qualification surface (`scripts/ci-qualify-decide.sh` derives that path set from the manifests themselves), unconditionally on `workflow_dispatch -f qualify=true` and a weekly schedule, and release-gate carries it as a MUST step. The exact-SHA release oracle refuses a SHA whose body step did not conclude success, so a filtered-out release commit is a named failure with a documented dispatch recovery, never a quiet pass. Its head — runner self-test, manifest-set validation, declared lane inventory — is `check-gate-manifests`, which executes no mutant and never snapshots the repo, and it IS in `check:hermetic`: three of the five reds qualification has ever produced in CI died there in under five seconds. A tag push runs no CI at all; the same SHA's branch run already carries every job, and that branch run is the exact-SHA evidence a release quotes.
- **Full floor once** (`pnpm run check:full`), on the frozen commit candidate. While it runs, nothing edits the worktree or index — including the NEXT boot sectors; a moved candidate voids the run's evidence.
- **pre-commit is not the floor.** `.husky/pre-commit` carries only fast static checks (whitespace, lint, typecheck); the full floor is owned by this protocol, not by the hook. Do not grow the hook back, and do not build receipt/cache machinery to prove the protocol was followed.
- **Release/LIVE acceptance is untouched.** VERIFY.md floors keep full strength; a shorter inner loop never lowers release evidence.

## Repository Map

| Path | Purpose |
|---|---|
| `pi-extensions/entwurf-control.ts` | pi adapter: record attach, record-keyed socket, RPC, native tools |
| `pi-extensions/lib/pi-citizen-birth.ts` | pi native session → shared V3 record → socket address |
| `pi-extensions/lib/meta-session.ts` | shared V3 record/store authority plus native marker/mailbox primitives |
| `pi-extensions/lib/entwurf-v2-*.ts` | v2 contract, decider, transports, runner, production wiring; visible resume keeps launch injected |
| `pi-extensions/lib/mux-*.ts` | same-tmux placement plus narrow fresh-call and visible-resume launch compositions |
| `pi-extensions/lib/entwurf-fact*.ts` | record citizens + transport-specific liveness facts |
| `pi-extensions/lib/entwurf-peer-observe.ts` | the IO half of the observed peer facts (receiver / transcript) |
| `pi-extensions/lib/native-push/` | native-push adapter/probe/register leaf |
| `pi-extensions/acp-provider.ts` | `entwurf` provider registration |
| `pi-extensions/lib/acp/` | ACP adapter rail, config/overlay, augment, turn loop, event mapping |
| `mcp/entwurf-bridge/` | MCP surface for v2/self/peers/inbox/native-register/fresh-call/resume-call |
| `scripts/` | deterministic gates, LIVE smokes, install/doctor surfaces |
| `run.sh` | installed command and gate dispatcher |

## Type and Runtime Boundaries

- Every `.ts` file belongs to one typecheck fence: root emit-capable config, MCP strip-types config, or scripts strip-types config. Do not hide files with `exclude`.
- Root pi extensions import TypeBox through `@earendil-works/pi-ai`; do not mix direct `@sinclair/typebox` types.
- MCP/scripts use explicit `.ts` imports where Node strip-types requires them. Installed operator surfaces route to compiled JS.
- pi runtime range is `>=0.85.1 <0.86` with devDep exact `0.85.1`; re-evaluate loader aliases and `/compat` at every minor ceiling. The ceiling moves on measurement, never on assumption, and a previous bump's argument is never reused: at 0.83.0→0.84.0 `compat.ts` was still byte-identical but `loader.ts` was NOT, so the diff itself had to be read and judged reachable-or-not. Per-bump hashes, diff judgments, and reachability findings live in the ROADMAP **Dep bump(별도 트랙)** ledger — keep them there, not here.
- ACP pins are recorded in `package.json` and owned by `check-acp-sdk-surface`, which is the vitest contract `test/acp-sdk-surface.contract.test.ts` (`./run.sh check-acp-sdk-surface` is a transition shim into it, not a `scripts/` gate). `check-dep-versions` is the **pi** pin's oracle and reads no ACP pin — do not cite it for one. Do not describe a dependency bump as a behavioral fix without evidence.

## Working Style

- Surgical changes, one contract at a time. Ask whether a change belongs in core, a harness adapter, a backend adapter, or the resident's own repo.
- Removal/repair changes source and their gates together. Do not leave a green gate that only proves retired behavior.
- Before commit, perform a **repo-wide** stale-prose sweep on two axes:
  1. retired symbols/authority vocabulary (`dual-read`, old schema names, removed commands, privileged identity wording);
  2. landed-plan future tense (`yet`, `will land`, `not here`, stale step headers).
- Judge each grep hit: historical CHANGELOG tombstones may remain; live claims, comments, usage text, gates, README, docs, NEXT, and source-module prose must agree with current behavior.
- Prefer capability/domain names (`control-socket domain`, `self-fetch`, `native-push`, `out-of-domain`) over identity-rank names (`pi-only citizen`, `non-pi citizen`).
- Keep docs calibrated and compact. Implementation archaeology belongs in git/CHANGELOG/issues; AGENTS keeps only invariants needed before acting.
- Use tabs unless the existing file/linter requires otherwise.
- GLG decides commit, push, and release gates. Never infer push from a commit request.

### Review triage and lane discipline

An overgrowth is built from locally correct steps; what fails is the absence of a budget and a stop rule. These are that budget.

- **Reproduce one manual operator action per step.** Measure → narrow leaf → visible composition → observe real pain → next step. Never pre-build the general future (orchestrator, watcher, manager, backlog, role system) ahead of an observed bottleneck, and never build structure to compensate for a current model's habits — both burn with the next model or billing change.
- **Triage review findings into three grades.** *Blocker* (false success, data loss, authority violation): fix in the current lane. *Defect* (real mismatch against the current explicit contract): fix in the amendment bundle. *Observation* (future risk, stronger-proof possibility): record it — it does not open work in the current lane.
- **One amendment bundle per review.** If the bundle itself surfaces two or more new architecture blockers, stop repairing and go back to the design.
- **Unrelated meta-infra never rides a capability lane.** The source-adjacent gate/mutant that proves a capability's contract belongs in the same change as that capability — the removal/repair rule above is untouched. What stays out of a feature commit candidate is unrelated verification machinery: scheduling rework, selectors, caches, receipts, floor restructuring. That pain is recorded and handled in its own subtraction lane later.
- **Stop signal — evidence outgrowing the product.** When verification/meta-tool changes grow larger than the capability change they serve, stop and report to GLG. This is an operator-judgment trigger, deliberately not a mechanized ratio gate.
- **Claim only what the evidence carries.** "The full floor was green once on the declared candidate" is strong enough; a stronger sentence mints proof obligations, and those obligations mint subsystems.
- **A claim that crosses sessions carries its evidence state.** Measured here (name the receipt), read at `file:line`, read from an external artifact (name the path), inherited and unchecked (name the source) — and design proposals in a box of their own, since a proposal is adopted or decided differently, never measured. This repo is where siblings from many models each get a few turns, so a bare sentence costs the next one its turn re-deriving the ground, and leaves it only "believe or refute" when the honest move is "that carries no receipt, so I measured it." Retire claims, not people. Receipts in host-local paths do not travel: paste the decisive lines into the artifact that crosses.
- **Risk classes are not equal.** Data loss, identity authority, false delivery success, install destruction, and secrets get fail-closed strength. Doc tense, future possibility, and total environment-byte binding get repaired when seen — they do not justify new gate machinery.

## Next and References

- [NEXT.md](./NEXT.md) — current priority and exact next move; branch work uses disposable `NEXT--<branch>.md`.
- [ROADMAP.md](./ROADMAP.md) — forward direction and deferred lanes.
- [docs/adding-a-harness.md](./docs/adding-a-harness.md) — **first entry point for putting a NEW harness in the garden.** The order the eight steps are actually walked in (lane choice, vendor measurement, backend registration, birth, statusline, MCP hand, sender identity, receive, grade), what each owes before the next may start, and which of the other docs owns each slice. It routes; it grants nothing — Hard Rule 7 remains the authority on the meta-record store contract its registration step touches, and the gates and doctors it names remain the truth.
- [docs/acp-backend-rail.md](./docs/acp-backend-rail.md) — ACP adapter contract and current entry conditions.
- [DELIVERY.md](./DELIVERY.md) — delivery capability/evidence coordinates.
- [VERIFY.md](./VERIFY.md) / [BASELINE.md](./BASELINE.md) — verification protocol and recorded evidence.
- [README.md](./README.md) — operator-facing package contract.
