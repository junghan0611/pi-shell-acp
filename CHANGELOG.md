# Changelog

All notable changes to this project will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The repo uses semver.

## Unreleased

## 0.18.1 - 2026-09-06

Two lanes, both landing on `main` after `v0.18.0`: the CI evidence-budget stage 1 (#102, from
research #99) and the dependency bump (#104 — pi, claude-agent-acp, and the OMP adoption rule
GLG decided to carry with them). They are not one cause; they are one release.

### Upgrade note — this one asks something of the operator

**The pi floor moved, and entwurf does not install harnesses.** The supported range is now
`>=0.85.1 <0.86`, so a host still carrying pi 0.84.x is BELOW it. `entwurf setup` says so by
name — `pi FAIL — detected pi <version> is outside the supported range >=0.85.1 <0.86 — Pi
wiring not written` — and writes no pi wiring rather than wiring a runtime it cannot vouch
for. That refusal is the design (Hard Rule 17), not a bug to work around.

The order matters:

1. **Upgrade pi yourself first.** `pi update`, or `pnpm add -g @earendil-works/pi-coding-agent@0.85.1`
   for a pnpm-global install. entwurf never does this for you.
2. **Then `entwurf setup`** — one command, as always. This release changes no deployment
   writer (`pi-extensions/lib/meta-session.ts`, the four `install-*` paths and the packaged
   plugins are byte-identical to 0.18.0), so unlike the 0.17.2 and 0.18.0 upgrades there is no
   stale-writer trap here. What setup does need to redo is the pi wiring it refused to write
   while the runtime was below floor.
3. **Restart any pi session you had open.** A running pi process keeps the binary it started
   with, and this release's changed extension surfaces (`entwurf-control.ts` and four ACP
   modules) are loaded at session start. A live 0.84.4 session stays a 0.84.4 session.

Hosts without pi are unaffected: absence is still an explicit setup SKIP, not a failure.

### Verification

All of the following ran on oracle (Linux, Claude Code 2.1.263, node 24.18.1, pi 0.85.1,
omp 18.0.0).

- **`LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.18.1.PtUm0r --cut` → `cut: OK`.**
  **MUST: PASS=23 FAIL=0 SKIP=0**, BEHAVIOR: PASS=1 FAIL=0 SKIP=0, exit 0.
  2026-09-06 18:30:51 → 19:23:40 KST (52m49s). Log preserved at
  `<scratch>/release-gate.log`.
  - `check-gate-qualification` as its MUST step: **369/369 KILLED**.
  - `smoke-acp-raw-turn-live` — the Dep-bump track's designated lock for an ACP adapter
    move — PASS on 0.75.1: launch source `package:@agentclientprotocol/claude-agent-acp`
    (not a PATH fallback), model `claude-sonnet-5`, `protocolVersion=1`,
    `stopReason=end_turn`, 65,780 bytes of NDJSON captured.
  - Both #91 drift sentinels green: `smoke-omp-receive-live`, and `smoke-omp-fresh-live`
    with 21 assertions (step 9 clause 7) — on omp **18.0.0**, below the documented weak
    floor of 18.1.10, which is exactly what "the floor records what was proven, not what is
    permitted" means.
- `pnpm run check:full` on the prepared tree: exit 0, 480s.
- Pre-push landing run for the implementation HEAD `c247594`: CI run `34018205091`,
  `check` + `install-surface` + `artifact-consumer` all `success` (`check` 34m14s,
  `check:full` 328s, qualification 369/369).

**The first `--cut` was BLOCKED, and the reason was not this release.** MUST PASS=20 FAIL=3
SKIP=0: `smoke-entwurf-chain-live`, `smoke-mux-lifecycle-live` and `smoke-omp-fresh-live`
each failed waiting on a sibling that never took its turn, and all three drive their sibling
on `openai-codex/*` while every Claude-rail step passed. Measured at the time: the codex
weekly window was at **100%**. The chain's own timeout instrumentation is what made this
readable rather than mysterious — it printed `terminus fixture at timeout: ownerPid=… alive=true
ownerAlive=true watchArmed=true`, so the mailbox was provably healthy and the chain had simply
stalled upstream. After the quota reset the same gate went green with no code change. Recorded
because an exhausted subscription rail looks exactly like a broken product until someone
measures it.

### Changed

- **The qualification HEAD runs in the everyday floor; the mutant BODY stays scheduled (#102).**
  Across 549 CI runs the qualification step went red five times and **none of the five came from
  mutant execution** — three died in the head in four or five seconds, two were a gate already red
  on a clean tree (#99 B-3). So the head stops waiting behind the ~28-minute body.
  `check-gate-qualification` gains a `--manifests-only` entrypoint, shipped as
  `run.sh check-gate-manifests` and placed in `check:hermetic` (~8s): runner self-test, manifest-set
  validation against the origin index, and the declared lane inventory — **zero mutants executed and
  no snapshot of this repo**. The body runs the same head first; its contract, output and
  mutant-execution semantics are unchanged.
- **CI push is filtered to branch refs (#102).** All 66 semver-tag runs in this repo's history
  rebuilt a SHA a branch push had already built, and not one reported a fact its branch run had not
  (the single non-green tag run failed at the same step as its main run, two seconds later). The
  exact-SHA evidence a release quotes is the branch run, which is what the release skill's oracle
  already selects.
- **`check-omp-birth-hook` joins `check:hermetic` (#102).** It was the one gate a committed mutant
  named that ran nowhere else, so the control-pre of a 28-minute run was the only thing in the repo
  that could notice it going red. `check-release-gate-outcomes` cell 9 now owns that as a contract:
  every mutant-named gate is inside `check:full` **or** states its exclusion in prose an operator
  reads (`scripts/check-setup-qualification.sh` takes the second arm, as its own header declared).
- **pi runtime 0.84.4 → 0.85.1** (#104): devDep exact ×3, peer range `>=0.85.1 <0.86` ×3, the
  `run.sh` pack-install pins, `pnpm-workspace.yaml`, the lockfile, and the five baseline docs
  `check-dep-versions` binds. **0.85.0 is deliberately skipped**: its published `exports` advertised
  `./client` and `./experimental/plugin` at `dist/*` paths the tarball does not contain, which
  upstream named and fixed in 0.85.1 ("SDK import failures caused by unintentionally publishing
  internal experimental code and dependencies in 0.85.0") by making both subpaths source-only.
  entwurf imports neither, so it never reached us — but the landing coordinate is 0.85.1.
- **`@agentclientprotocol/claude-agent-acp` 0.73.0 → 0.75.1** (#104). The other two ACP pins do
  **not** move: all four tags v0.73.0–v0.75.1 declare the same `@agentclientprotocol/sdk 1.4.0`,
  `@anthropic-ai/claude-agent-sdk 0.3.257`, `zod ^4.0.0` and `engines.node >=22`, so
  `@anthropic-ai/sdk` stays pinned at `0.100.1` against an unchanged `>=0.93.0` peer floor.
- **Compaction now reaches operators as a tool lifecycle, not assistant text** (upstream #991, in
  0.75.0). A compacting turn shows a `[tool:start] Compact conversation` / `[tool:…]` notice pair
  where 0.73.0 wrote `Compacting completed.` into the assistant's own text. No mapper change was
  needed and no accounting path is touched; the measurement, the join through the production event
  mapper, and the limits are in `scripts/raw-acp-compaction-measure/README.md` and
  `docs/acp-backend-rail.md` §11-8.
- **OMP gets a documented *weak* floor instead of a version gate (#91).** entwurf still detects omp
  by presence alone — no `entwurf.ompFloor`, no coherence gate, no exact pin — because a floor is
  the answer to a vendor that fails SILENTLY, which OMP has never been observed to do, and its
  contact surface is guarded by two release-gate MUST smokes that go loudly red. What is recorded
  instead is the last version with a LIVE receipt (**18.1.10**, 2026-09-04 thinkpad), the rule that
  the number moves only when a new receipt exists, and the two sentinels
  (`smoke-omp-fresh-live`, `smoke-omp-receive-live`). Code change: none.
  `docs/setup-clean-host.md` §4b.

### Fixed

- **An undeclared pi 0.85.x break, caught by our own typecheck (#104).** `pi-tui`'s `Container`
  gained a `private mouseLayout?` in the 0.85.0 mouse work (0.84.4's `Container` had no private
  member at all) while `Box` declares a separate private field of the same name, so TypeScript's
  private-member identity rule broke the `Box → Container` structural assignment that had held
  through 0.84.4 (`TS2322` at `entwurf-control.ts`). Upstream's Breaking section names only
  `createGatewayBindingFetch`. The repair narrows the annotation to what the vendor contract
  actually asks for — `MessageRenderer` returns `Component | undefined` — which is what the helper
  always needed.
- **The pack-install pin-leak matcher was blind to a new closure member (#104).** pi 0.85.0 added
  `@earendil-works/chord` as a runtime dependency of pi-coding-agent, pi-agent-core, pi-client and
  pi-protocol — inside the runtime closure, with a name carrying no `pi-` prefix. Measured on a real
  0.85.1 install tree, `@earendil-works+chord@0.85.1` sits beside the seven pi entries and the
  `^@earendil-works+pi-` filter did not see it, so an unpinned caret would have floated while
  `check-pack-install` printed a verified pin — the same class as the 2026-07-21 `pi-agent-core`
  incident, and it made the "covers every other pi package" comment false. The matcher now filters on
  the org prefix, chord is pinned explicitly, and the self-test splits into two cells so each
  property fails under its own name. New claim `[QK:PACK-INSTALL-PIN-MATCHER-COVERS-CLOSURE]` with
  its exact-once replant; inventory **368 → 369 mutants across 40 lanes**.
- **`check-pack-install`'s "every harness absent" row was not actually absent of OMP.** The row
  pins harness probes away with explicit `*_BIN` seams, and `OMP_BIN` was never added when 0.16.0
  admitted OMP — the two sibling fixtures (`smoke-setup-verdict.sh`,
  `check-setup-qualification.sh`) both got it. On a host that HAS `omp` on PATH the row's premise
  was therefore false: setup detected omp, and the omp config/receiver installers refused —
  correctly — because the row also exports `PI_CODING_AGENT_DIR`, which omp reads too, leaving the
  target directory ambiguous. The product was right and the fixture was wrong. It stayed invisible
  because CI runners carry no omp **and** `release_gate()` does not run this gate (it is
  `prepublishOnly` plus the CI install-surface job), so no green floor ever covered it. Measured
  here with a control: a clean clone of the pre-bump HEAD fails at the same row for the same
  reason. The seam is added to both setup rows, and the zero-state probe now requires **five**
  SKIPs so a sixth harness cannot be admitted while this seam is left behind again.
- **`VERIFY.md` still advertised a pi range two bumps stale, and now nothing can leave it there.**
  It sat outside `check-dep-versions`' `BASELINE_DOCS`, so nothing read it; it has joined that
  list (six docs). Its declaration is a plain range, so the existing range scan binds it — no new
  prose pattern was added for it.
- **`AGENTS.md` claimed `check-dep-versions` checks the ACP pins.** It does not — it is the **pi**
  pin's oracle and reads no ACP pin (`run.sh:1820-1919`). The ACP pins are owned by
  `check-acp-sdk-surface`, which is the vitest contract `test/acp-sdk-surface.contract.test.ts`;
  the `run.sh` name is a transition shim into it.

### Added

- **`scripts/raw-acp-compaction-measure/`** — a raw measurement probe (not a gate, in no check
  tier) that drives one live `/compact` turn on the pinned adapter and replays the captured
  notifications through the production event mapper, so the vendor wire and our rendered notice sit
  in one receipt.
- Four new qualification claims from #102, each with its exact-once replant:
  `MANIFEST-SET-INTEGRITY-REFUSED` and `LANE-INVENTORY-DECLARED` (new `gate-qualification` lane,
  replanting the 08-20 / 08-21 / 08-28 catches), `MUTANT-GATES-INSIDE-FULL-FLOOR` and
  `CI-TAG-PUSH-NOT-REBUILT` (`release-gate` lane).

### Notes

- **`allowBuilds: esbuild: false`.** chord's only dependency is esbuild, and its arrival made
  `pnpm install` stop on `ERR_PNPM_IGNORED_BUILDS` until the key carried a decision. Denied like the
  other two entries: nothing here executes esbuild.
- **`bridge-command-boot`'s three agy gates moved to the `run.sh` argv the other manifests use**,
  merging a duplicate group (#102). Group count is unchanged at 52 — the merge removes one and the
  new head gate adds one — so the saving is a 66s control pair traded for a 16s one, not fewer
  groups.

## 0.18.0 - 2026-09-04

### Fixed

- **A Claude window that changes which session it serves no longer leaves an armed receiver behind
  (#101).** One process serves one garden at a time but can change which: open a bare `claude` and
  then `/resume` or `/clear` inside it, and a second `SessionStart` arrives under the same pid,
  seconds later, naming a different session. The garden it stopped serving kept a receiver marker
  naming a LIVE owner, so dispatch read an armed doorbell nobody held — a sibling's message was
  reported as sent and then sat unread in that mailbox for over 50 minutes (oracle, 2026-09-04; that
  unread letter is what opened the issue).
  - **Deliverability now asks about *now*, not *ever*.** `watchArmed` was a copy of the identity
    match; it is a measurement — the receiver owner's own sender marker
    (`meta-senders/<backend>/<pid>.json`) must still name the same garden. Both consumers, the v2
    production seam and `entwurf_self`, go through one shared composition, so a citizen's
    self-report and dispatch cannot disagree.
  - **The hook retires what it stopped serving** — the marker only, never the record (a record is a
    citizen's identity, not sweepable state), only a marker its own pid owns, and only on an
    arm-capable event. `UserPromptSubmit` cannot emit `watchPaths`, so retiring on a keystroke would
    disarm the session the operator is sitting in with no way to re-arm. The vendor's `source` is
    logged on every line and branched on nowhere: the switch is settled by what is on disk.
  - **The join is scoped by the marker's `ownerKind`, not by backend** — today that is
    `claude-code-cli`. A Copilot watch lives in a forked extension child with its own pid while its
    sender marker carries the CLI's `process.ppid`, so applying the same check there would make
    every Copilot citizen permanently `mailbox-undeliverable`. That is a scope decision with a
    measured reason, not an omission.

### Added

- **A rejected delivery now names which receiver axis failed (#101).** A bare `mailbox-undeliverable`
  sent one sibling hunting for a live session it had read as dead. The rejection now says whether
  the doorbell is not armed, the owner is not alive, or there is no record.
- **`entwurf_peers` separates a live citizen from a phantom (#101).** Every claude-code row reads
  `liveness=unsupported`, so two rows were byte-identical whether or not anyone was home. Each row
  now carries two observed facts — `receiver=` (doorbell state) and `transcript=` (whether a
  conversation was ever written):

  ```text
  - 20260904T072015-e09b66  liveness=unsupported  receiver=active    transcript=exists
  - 20260904T093135-ac7a1a  liveness=unsupported  receiver=inactive  transcript=absent
  ```

- **`check-meta-hook-session-switch` (28 assertions) and the first mutant lane the Claude hook has
  ever had (#101).** The gate drives the shipped launcher twice under one fake owner pid and
  requires that exactly one of the two gardens is deliverable — and that it is the one the operator
  is sitting in. `scripts/mutants/meta-hook-session-switch.json` carries **17 claims**, 1:1 with the
  gate's `[QK:…]` labels, each re-planting the defect this lane closed and requiring the gate to go
  red at its claimed signature. Three of those six new mutants exist because cross-review found two
  QK labels with no mutant behind them and three real weakenings walking straight through: the
  join's `ownerKind` scope, the sender marker's start-key guard, and its backend equality.

### Changed

- **One inherited sentence about the resume picker is retired, and it was retired by measurement
  (#101).** The diagnosis said the picker fires `SessionStart` twice — a placeholder id, then the
  picked one. Six LIVE cells on this host (Claude Code 2.1.260, hook log verbatim in
  `scripts/raw-claude-session-switch/README.md`) show it fires **once**, carrying the real id,
  whether the id comes from the picker or from argv. The two-`SessionStart` shape is a bare `claude`
  followed by an in-session `/resume` or `/clear` — which is exactly what the field case did, four
  seconds before its second envelope. The repair is unaffected (either way one pid stops serving one
  garden), so only the prose moved, in four places. Compaction, manual and automatic, re-fires
  `SessionStart` for the **same** native id and retires nothing; the same-garden rule already
  covered it.
- **A `UserPromptSubmit` envelope is trusted for the receiver join, on a measured footing.** The
  cross-review threat model ("a stale or out-of-order UPS") was withdrawn rather than defended: it
  claimed the sender pointer is untrustworthy for the join while the same pointer stays authoritative
  for sender identity — two incompatible readings of one file. Across the raw lab's four pids, every
  `UserPromptSubmit` named the native id its own pid's preceding `SessionStart` had established,
  **8 of 8**. The arm-capable restriction stays on its own footing.
- **Three LIVE smokes stopped depending on a fixture the new join reads as retired.** Five smokes
  seeded a receiver marker with no sender marker beside it — three of them release MUSTs — so each
  would have failed on its own fixture rather than on the rail it exists to prove. They now seed
  both and sandbox the senders root, the shape `smoke-mux-lifecycle-live` and `smoke-omp-fresh-live`
  already had. `smoke-entwurf-chain-live` additionally gives its terminus an owner **outside hop 1's
  ancestry**: seeding it under the smoke's own pid put two garden citizens on one host process and
  the bridge refused the hop outright with `ambiguous sender identity`.

### Upgrade note

**Run `entwurf setup` once after upgrading — every rail, not just Claude.** This release changes
`pi-extensions/lib/meta-session.ts` and the Claude hook, and **four install paths deploy that
file** — `install-meta-bridge` (Claude), `install-omp-bridge` and `install-omp-receive` (OMP),
`install-copilot-bridge` (Copilot). Every one of them present on the host now carries a STALE
writer until it is re-installed, and its own doctor says so by name. Re-installing only the Claude
rail leaves the others stale, and that does not surface until a LIVE gate turns red — measured in
the 0.17.2 cut, where it blocked `smoke-omp-receive-live` and made the first `--cut` run BLOCKED.

`entwurf setup` is presence-driven and re-synthesizes exactly the units this host has, which is why
it is the upgrade command rather than any single `install-*`. An already-open Claude Code session
keeps the old manifest until it restarts — and, for this release specifically, an already-open
session also keeps the old hook, which is the code that retires a switched-away receiver.

### Verification

All of the following ran on oracle (Linux, Claude Code 2.1.260, node 24.18.1, pi 0.84.4, omp 18.0.0).

- **`pnpm run check:full` — exit 0**, 440s on the prepared tree and 446s inside the release gate.
- **`LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.18.0c.xZlKjZ --cut` — `cut: OK`,
  exit 0.** **MUST PASS=23 FAIL=0 SKIP=0**, **BEHAVIOR PASS=1 FAIL=0 SKIP=0**. Run 18:57→19:48 KST
  on `faee8f6`, with `env -u CLAUDE_CONFIG_DIR -u PI_SESSION_ID -u PI_AGENT_ID`. Log:
  `/tmp/entwurf-release-gate-0.18.0c.xZlKjZ/release-gate.log`. It carried `check:full` and
  `check-gate-qualification` (**364/364 KILLED**, up from 347 — the 17 new claims are this lane's
  `MHSS-*`) as MUST steps.
- **This lane's own gate: `check-meta-hook-session-switch` — 28 assertions passed**, and all 17
  `MHSS-*` mutants killed at their claimed signatures inside that qualification run.
- **The three LIVE smokes whose fixtures this lane changed are green**, including
  `smoke-entwurf-chain-live` — **24 assertions**, four citizens across three harnesses, and its new
  pre-flight cell `fixture: the terminus is a deliverable citizen at the moment the chain starts`
  passed before the chain ran.
- **One unattributed `smoke-entwurf-chain-live` failure is on the record and is NOT closed.** During
  the lane (2026-09-04 16:58 KST) one run rejected at hop 3 with `mailbox-undeliverable (observed
  liveness: unsupported)`; the runs before and after it passed and it has not reproduced. A
  start-key race and an early idle-owner exit were excluded by measurement; a memory-pressure
  hypothesis is neither confirmed nor refuted (no OOM or kill entries in the host journal for that
  window). The instrument that will split the next occurrence shipped in this release — the fixture
  pre-flight assertion above, plus a `terminus fixture at timeout:` line naming owner liveness and
  both receiver facts.
- **The first `--cut` attempt of this cut was BLOCKED, and the cause was operator error, not the
  product.** `check-gate-qualification` aborted with `origin HEAD changed during qualification`
  because a commit was created while the gate was running. Every other MUST step in that run passed
  (`MUST PASS=22 FAIL=1 SKIP=0`). The run above is the re-measurement on a frozen HEAD. One LIVE
  gate run before that was killed by the host harness's low-memory watchdog rather than by any
  assertion, and was re-run under tmux.
- **Exact-SHA CI on the pre-version HEAD `e56eee0`** — `check`, `install-surface`,
  `artifact-consumer` all `success`.
  Run: https://github.com/junghan0611/entwurf/actions/runs/33853363923

## 0.17.2 - 2026-09-03

### Added

- **An arriving letter is now visible to the operator, not just to the model (#98).** A sibling's
  mail landed, was read, and left one line on the receiving screen — `Stop hook feedback` — with no
  sender, no count, no garden id. Three surfaces changed, each measured in the
  `scripts/raw-async-delivery/` lab before any product edit:
  - **The doorbell says what it is.** The shipped `FileChanged` hook declares
    `rewakeSummary: "entwurf inbox: sibling mail arrived"` and
    `rewakeMessage: "entwurf mailbox notice:"`. The model no longer wakes to
    `Stop hook blocking error from command "FileChanged"` — mail arriving was being named an error.
    Both fields are `@internal` in the vendor and unsanitized, so `check-hook-launch-topology` lints
    them (declared, no newline, not whitespace-only, length bound, no `[` in the prefix that would
    double the doorbell's own `[entwurf inbox]`) and `smoke-meta-async-drift` carries both as
    markers — a silent `@internal` removal is a future this repo cannot measure live.
  - **The status line carries an unread badge.** `✉N` counts exactly what `entwurf_inbox_read`
    would hand back (`*.msg` + `*.msg.delivered`, `.read` excluded — the same union as
    `readMetaInbox`). No badge at zero. **`✉?` when the count could not be TAKEN** (no python3,
    unusable garden id, unreadable directory): a measurement failure must not look like an empty
    inbox.
  - **A send names the file it enqueued.** `entwurf_v2 meta-mailbox → enqueued (2026-…-113443.msg)`.
    `enqueueMetaMessage` already returned `messagePath`; the mailbox hand was flattening it to
    `{success:true}`. Deliberately not a read stamp: at enqueue time `lastReadAt` belongs to the
    PREVIOUS message, and surfacing it would read as "my message was read".

### Fixed

- **A dead-socket send that falls back to the mailbox now names its file too (#98).** A
  control-socket delivery whose socket was gone re-resolves to the mailbox and writes a `.msg`
  exactly like the primary rail, but the sender's line said only `fallback-sent` — the one mailbox
  delivery with no per-message identifier. The receipt is carried through `SendDrive` →
  `ControlSocketSendResult` → `ExecutedOutcome` → surface. A socket-to-socket retry writes no file
  and carries none; a `rejected` enqueue carries none; a dep that omits it degrades to the bare
  outcome rather than printing `undefined`.
- **entwurf no longer owns the compaction switch (#94).** `autoCompactEnabled` and
  `env.DISABLE_AUTOCOMPACT` moved from `MANAGED_SETTINGS_SCALARS` to `RETIRED_SETTINGS_SCALARS`,
  the path `skipDangerousModePermissionPrompt` already walked. Retirement moves **ownership, not
  state**: `relinquish_retired_scalar()` restores the install-state snapshot only when the current
  value still equals the last managed one, so retirement alone turns compaction on for nobody —
  turning it on is a separate operator act, and entwurf writing that value again would undo the
  return. The doctor now stays green for an operator who turned compaction back on.
  - **A correction that belongs in the record:** `env.DISABLE_AUTOCOMPACT` was a **no-op** at Claude
    Code 2.1.259 — the only key that actually suppressed compaction was `autoCompactEnabled`. The
    conclusion is unchanged; the reason narrows to one key.
  - The lineage is also corrected. 0.5.0 *did* ship a pi-side compaction guard in real code;
    `378c682` (v2 subtraction) deleted it and `623a4ea` later cleared the docs that outlived it by
    seven days. The "zero code backing" in that commit message was a grep result at that moment, not
    a claim that the guard never existed.

### Changed

- **Three shipped comments stopped repeating two claims this release retired.** `doorbell.sh`,
  `raw-async-delivery/README.md` and `smoke-meta-async-drift.sh` said that `asyncRewake` ignores
  `rewakeMessage` and that stdout is dropped. Measured against three vendor binaries (2.1.236 /
  2.1.258 / 2.1.259), both are false: `rewakeMessage` *replaces* the prefix, and the body is
  `stderr || stdout`. The marker strings were correct while their stated reasons were dead — a
  sentinel nobody could act on. The lab README now carries the receipts under
  `## Inherited facts corrected`, and the watcher documents what it observes rather than which
  backends it expects.
- `lastDeliveredAt` is documented as a **reserved slot nobody stamps**, in five comments and four
  test cells that had been pinning it green as `=== null` while 933 files carried a `.delivered`
  suffix. The per-message facts are the suffixes (`.msg` → `.delivered` → `.read`); `state.json`
  holds only the garden's last enqueue/read. Removing the field is a separate migration (its reader
  is doubly strict and 182 v1 files are on disk), tracked apart from this release.

### Upgrade note

**Run `entwurf setup` once after upgrading — every rail, not just Claude.** Two separate debts:

- The Claude plugin's hook template gained `rewakeSummary` and `rewakeMessage`, so until
  `install-meta-bridge` runs, `doctor-meta-bridge` reports
  `installed manifest DIFFERS … Re-run install-meta-bridge`.
- **This release changed `lib/meta-session.ts`, and four install paths deploy that file** —
  `install-meta-bridge` (Claude), `install-omp-bridge` and `install-omp-receive` (OMP),
  `install-copilot-bridge` (Copilot). Every one of them that is installed on the host now carries a
  STALE writer until it is re-installed, and its own doctor says so by name. Re-installing only the
  Claude rail leaves the others stale — measured on oracle during this cut, where it blocked
  `smoke-omp-receive-live` and turned the first `--cut` run red.

`entwurf setup` is presence-driven and re-synthesizes exactly the units this host has, which is why
it is the upgrade command rather than any single `install-*`. An already-open Claude Code session
keeps the old manifest until it restarts.

0.17.1 was tagged and released on GitHub but **not published to npm**; it is superseded by this
version.

### Verification

All of the following ran on oracle (Linux, Claude Code 2.1.259, node 24.18.1, pi 0.84.4, omp 18.0.0).

- **`pnpm run check:full` — exit 0** (432s on the prepared tree; 437s on the pre-version HEAD).
- **`LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.17.2b.WW12BK --cut` — `cut: OK`,
  exit 0.** **MUST PASS=23 FAIL=0 SKIP=0**, **BEHAVIOR PASS=1 FAIL=0 SKIP=0**. Run 20:39→21:26 KST
  with `env -u CLAUDE_CONFIG_DIR -u PI_SESSION_ID -u PI_AGENT_ID`. Log:
  `/tmp/entwurf-release-gate-0.17.2b.WW12BK/release-gate.log`. It carried `check:full` (429s) and
  `check-gate-qualification` (**347/347 KILLED**) as MUST steps.
- **The first `--cut` attempt was RED, and that is the receipt for the upgrade note above.**
  `smoke-omp-receive-live` failed with `STALE writer: source=634d5b96ed50 installed=229fef123589`
  on `~/.omp/agent/extensions/entwurf-receive-omp/lib/meta-session.ts` — MUST PASS=22 FAIL=1,
  `cut: BLOCKED`. Both OMP extensions on the host still carried the pre-release writer because only
  the Claude rail had been re-installed. `install-omp-bridge` + `install-omp-receive` moved both to
  `634d5b96ed50`, `doctor-omp-bridge` and `doctor-omp-receive` went PASS, and the re-run was green.
  Nothing in the product changed between the two runs.
- **#94 measured on a live host.** After one `install-meta-bridge`, the install-state ledger no
  longer carries `autoCompactEnabled` or `env.DISABLE_AUTOCOMPACT`, and `~/.claude/settings.json`
  was **byte-identical** to its pre-install backup — the return does not rewrite the value it
  returns. `doctor-meta-bridge` went FAIL→PASS, `smoke-meta-install-state` PASS,
  `check-meta-doctor-oracle` PASS including the two new cells (`an operator who turned compaction
  back ON is not drift`, `install-state still owns a retired scalar → FAIL naming its own cause`).
- **#98 B measured across the whole suffix lifecycle** in an isolated mailbox root: no badge at 0,
  `✉1` on `.msg`, `✉2` after `.msg.delivered`, unchanged by a `.read` file, back to no badge when
  all are read, and `✉?` on an unreadable directory.
- **`smoke-meta-async-drift` ends `pass=12 fail=0 drift=1`, exit 1** — the drift is
  `codex 0.147.0` outside the `0.144.x` pin and **pre-dates this release**. Both markers this
  release added (`rewakeMessage`, `rewakeSummary`) are present. The pin bump is deliberately not in
  this lane.
- **Exact-SHA CI on the pre-version HEAD `4124e42`** — `check`, `install-surface`,
  `artifact-consumer` all `success`.
  Run: https://github.com/junghan0611/entwurf/actions/runs/33742448634

## 0.17.1 - 2026-09-03

### Fixed

- **The C1b red that blocked two of the three 0.17.0 `--cut` runs: a LIVE smoke was waiting exactly
  as long as pi's lock-stale window, and losing by 148ms.** The cause is measured end to end, and
  none of it is a product regression:
  1. pi guards `auth.json` AND `models-store.json` with `proper-lockfile` and reads through that
     lock on every boot (`dist/core/auth-storage.js`), retrying a held lock for `staleMs = 30_000`
     before taking it over.
  2. `terminateChild`'s SIGTERM ends a resident before `proper-lockfile`'s release ever runs, so a
     kill that lands inside the lock window orphans the lock directory. Sweeping 24 kill offsets
     across a boot reproduced it once, at +375ms.
  3. With `~/.pi/agent/models-store.json.lock` orphaned, the next boot → V3 record measured
     **30_148ms** — and **1_114ms** immediately afterwards, once the stale takeover had cleared it.
  4. `smoke-entwurf-v2-matrix-live`'s `BOOT_TIMEOUT_MS` was `30_000`: it stopped looking 148ms
     before C1b's record landed. Hence the exact signature the blocked cuts left — empty stderr, no
     record in any store, and (confirmed in both runs from the host's own process-audit trail) a
     child that was alive for the entire 30s and was killed by the smoke at +30s.
  The control was in the same three runs: `smoke-entwurf-chain-live` does the same two-resident
  dance with `BOOT_TIMEOUT_MS = 45_000` and passed 3/3 while matrix-live failed 2/3.
  - **The bound is now shared and carries its receipt.** `PI_BOOT_TIMEOUT_MS = 45_000` lives in
    `scripts/lib/pi-record-discovery.ts` next to the measurements above, and the five smokes that
    sat on the 30s cliff (`smoke-entwurf-v2-matrix-live`, `smoke-acp-socket-citizen-live`,
    `smoke-acp-bundled-mcp-live`, `smoke-acp-v2-send-live`, `smoke-acp-cortex-live`) now derive
    from it. 30s was the single worst value available: it expires *inside* the takeover.
    `smoke-resident-garden-guard` already used 90s and needed no change.
  - **A boot overrun now names the lock.** `describePiLockResidue()` reports which pi locks are held
    at failure time — read-only, because a live holder and an orphan look identical from outside and
    only pi's own stale protocol may arbitrate them.
- **Both blocked smokes now say WHICH failure they hit**, which is what made the cause findable.
  `smoke-entwurf-v2-matrix-live` watches each resident (pid, exit code/signal and how many ms in, a
  signal-0 liveness probe taken in the catch before the reaper runs, and a **per-child** stderr tail
  — the old single shared buffer could not say whether C1 or C1b spoke; an empty tail now prints as
  `(empty)` rather than being skipped). `smoke-mux-lifecycle-live` attaches window forensics when a
  nonce callback never comes — pane-pid liveness, `list-panes`, and the last 40 lines of
  `capture-pane`, for both cells. Its launch receipt already tells a human "the window is visible
  and can be read directly"; on a headless gate nobody is there and the window is torn down seconds
  later. Every diagnostic step is best-effort so it can never become the failure.

  The mux pi-native nonce timeout (the second blocked cut) is NOT this bug and stays open: 300s is
  ten times the stale window, and the codex rail was healthy in that same run (`chain-live` and
  `smoke-omp-fresh-live` both passed on it). The forensics above are what the next occurrence will
  answer with.

### Verification

- `pnpm run check:toolchain` (biome + `tsc` ×3) — green.
- **The repair measured against the exact failing condition.** With `models-store.json.lock`
  planted as an orphan, `LIVE=1 ./run.sh smoke-entwurf-v2-matrix-live` is **17/17 PASS in 34s** —
  the stale wait absorbed. The same condition measured 30_148ms to birth, i.e. red under the old
  30_000 bound.
- **Boot cost, undisturbed**: 1008–1212ms across 80 consecutive boots in the smokes' spawn shape
  (5.1–5.4s under 4× CPU oversubscription). The bound is not sized for boot cost; it is sized to
  clear pi's stale window.
- **The new matrix-live diagnostic exercised on a real failure path**, at 0 model tokens, by
  pointing the smoke at a bogus provider: `resident C1: pid=… EXITED code=1 signal=null at +1057ms
  — it was gone before the wait ended`, with that child's own stderr beneath it.
- `LIVE=1 ./run.sh smoke-entwurf-v2-matrix-live` — **17/17 PASS** on the real
  `openai-codex/gpt-5.6-luna` target (undisturbed run).
- `LIVE=1 ./run.sh smoke-mux-lifecycle-live` — **81 checks passed, exit 0** (real model turns on
  both pi cells and the claude-code cell).
- 15 iterations of the gate's own C1b neighbourhood (`smoke-resident-garden-guard` → `check-bridge`
  → `doctor-pi-provider` → `smoke-entwurf-v2-matrix-live`) reproduced nothing — recorded because it
  is what ruled out host load and prior-smoke residue and sent the search to pi's lock.
- **`LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.17.1.hb5Q5j --cut`** — **MUST
  PASS=23 FAIL=0 SKIP=0**, **BEHAVIOR PASS=1 FAIL=0 SKIP=0**, exit 0, `cut: OK`. Run on `665191d`,
  2026-09-03 09:46:37 → 10:35:42 KST, with `env -u CLAUDE_CONFIG_DIR -u PI_SESSION_ID -u
  PI_AGENT_ID`. Log: `/tmp/entwurf-release-gate-0.17.1.hb5Q5j/release-gate.log`. This carried
  `pnpm run check:full` (451s) and `./run.sh check-gate-qualification` (**347/347 KILLED**) as MUST
  steps. **This is the green `--cut` 0.17.0 never got**: both cells that blocked it — C1b in
  `smoke-entwurf-v2-matrix-live` and the pi-native nonce in `smoke-mux-lifecycle-live` — passed
  here, on the same host, in one run.
- **Exact-SHA CI on `665191d`** — `check` (34m20s, carrying `check:full` and
  `check-gate-qualification`), `install-surface`, `artifact-consumer`, all `success`.
  Run: https://github.com/junghan0611/entwurf/actions/runs/33697821117

## 0.17.0 - 2026-09-02

### Verification

Each receipt carries its own scope; none of them is transferable to another commit or host.

- **`LIVE=1 ./run.sh release-gate <scratch> --cut`** — **MUST PASS=23 FAIL=0 SKIP=0**,
  BEHAVIOR PASS=1 FAIL=0 SKIP=0, exit 0, `cut: OK`. Run on commit `0379764`, tracked tree
  `cb1a3dc69b521909f0fe6f956e5c0fa36e885d5955f91271dd8e63d30cd918fb`, 2026-09-02
  20:14:51 → 21:04:41 KST. Frozen log: `/tmp/entwurf-0.17.0-evidence/ACCEPTED-cut-release-gate.log`.
  This run carried `pnpm run check:full` and `./run.sh check-gate-qualification`
  (**346/346 KILLED**) as MUST steps. **It is not the 0.17.0 acceptance SHA:** `9479750`
  changed source after it.
  `CHANGELOG.md` is in `package.json` `files` and `check:full → check:package → check-pack`
  enumerates it (`npm pack --dry-run`, required/forbidden names — not a cardinality lock).
  `NEXT.md` is not in `files`. Working-tree cleanliness at cut start was an operator
  observation, not a line in the gate log.
- **Four reds along the way, all real, none smoothed.** A formatter rejection of the new mutant
  manifest; a doc-floor gate catching the ROADMAP ledger entry quoting the ADAPTER's
  `engines.node ">=22"` as though it were entwurf's own; a qualification run that aborted RED on its
  own self-fence because the worktree was edited mid-run — kept in the record because a
  qualification predating the final bytes is not a receipt, and the fence is what says so; and
  `check-bridge-delivery` failing "artifact is not stale" after the review amendment edited three
  `.ts` files without rebuilding the MCP bridge. That last one is why the tree hash above is quoted
  twice: `mcp/entwurf-bridge/dist/` is gitignored, so the rebuild moved no candidate byte, and the
  two receipts really do cover the same tree. None of the four would have been caught by typecheck
  plus the focused gate.
- **The first `--cut` attempt was RED — MUST PASS=18 FAIL=5 SKIP=0 — and every one of the five was
  the operator's own environment, not this release.** Recorded because the failure wore a
  convincing disguise: it read as a broken host. `static` was the stale bridge artifact above,
  re-created when a `git checkout`/`merge` bumped every tracked `.ts` mtime past the built `dist`.
  The other four came from running the gate **inside a live entwurf ACP Claude session**, which
  exports two carriers into every child it spawns. `CLAUDE_CONFIG_DIR` points at the ACP overlay,
  whose `settings.json` is `hooks: {}` by design — so the Claude Code children the live smokes
  launch are born with no entwurf SessionStart hook and mint no meta-record, failing
  `smoke-claude-native-resume-live`, `smoke-entwurf-chain-live` and `smoke-mux-lifecycle-live` on
  citizen birth. The same variable made `doctor-meta-bridge` report `installed: absent` and
  `claude mcp list` deny `entwurf-bridge`; with it unset the doctor reads
  `installed: v3 (229fef123589)` matching source and assembled exactly. `PI_SESSION_ID` did the
  analogous damage on the omp axis: `smoke-omp-fresh-live` reported a 240s nonce-callback timeout,
  but the sibling was alive — it was born at 19:58:21 KST and called back at 19:58:28 to the
  AMBIENT caller id rather than the caller the smoke had minted, so the smoke watched the right
  mailbox and saw nothing. That smoke's own source anticipates this exact disguise
  (`scripts/smoke-omp-fresh-live.ts:186`, "the failure would masquerade as a silent sibling").
  Re-run with `env -u CLAUDE_CONFIG_DIR -u PI_SESSION_ID -u PI_AGENT_ID`, all five turned green and
  nothing else changed. That gap — VERIFY.md named `PWD` in scratch but not the carriers — is what
  cost the first cut its 52 minutes; VERIFY.md and AGENTS.md now name the strip.
- **Qualification lane size.** On the `0379764` cut the total was **335 → 346**, eleven new claims
  in `scripts/mutants/acp-usage-accounting.json` (absent on the 0.16.1 base). `9479750` adds a
  twelfth, `ACP-REBILL-MAIN-LOOP-SCOPE`. Standalone `./run.sh check-gate-qualification` on
  `fee89d3` is **347/347 KILLED** (36m19s, log `/home/junghan/.pi/background/1788355846036-bg03.log`).
  That is a qualification receipt, not a `--cut` receipt.
- **Three recuts on the D1 tree, all `cut: BLOCKED`.** Each ran
  `env -u CLAUDE_CONFIG_DIR -u PI_SESSION_ID -u PI_AGENT_ID LIVE=1 ./run.sh release-gate <scratch> --cut`.
  All three: MUST PASS=22 FAIL=1 SKIP=0, BEHAVIOR PASS=1. None of the FAILs is D1.
  1. `/tmp/entwurf-cut-0.17.0.WdTkH7` — `smoke-entwurf-v2-matrix-live` C1b: second
     `pi --entwurf-control` wrote no hidden-store record in 30s, stderr empty. Isolated re-run:
     17/17 PASS.
  2. `/tmp/entwurf-cut2-0.17.0.XQcOuR` — `smoke-mux-lifecycle-live` pi-native nonce
     `mux-fresh-call-4bd6391e9783fb24fb1ee74a` never arrived in 300s (claude-code cell passed;
     v2-matrix passed this run). Same shape as the 0.16.1 mux-lifecycle retry.
  3. `/tmp/entwurf-cut3-0.17.0.sfZ8WC` — C1b 30s again. Isolated re-run: 17/17 PASS.
     mux-lifecycle PASS this run.
  GLG 2026-09-03: no fourth cut. Make proceeds with this gap named here, not rounded up to
  `cut: OK`.
- **`smoke-acp-raw-turn-live`** — PASS on the moved pin, quoted from the accepted `--cut` run's own
  output rather than from a session message: launch source
  `package:@agentclientprotocol/claude-agent-acp` (not PATH fallback), `protocolVersion=1`, model
  `claude-sonnet-5`, `stopReason=end_turn`, reply `"OK"`, 62,998 bytes NDJSON. This is the dep-bump
  track's own named lock, not a substitute for it. An earlier standalone run of the same smoke
  reported 58,189 bytes and another 58,178; the byte count is per-run and is not a fixed
  fingerprint, which is precisely why the number cited here is the one the gate printed.
- **Recurrence corpus measurement** — cited from the in-source comment at
  `pi-extensions/lib/acp/backend.ts` (`priorTurnInputOutputSum`): 2,398 of 2,410 adjacent pairs
  (99.50%), 2026-05 → 2026-09. The raw pair inventory is not in the frozen receipts; treat it as
  an operator observation recorded in source, not as a cut receipt.

### Changed

- **ACTION REQUIRED — ACP accounting consumers must read `usage.acp`.** Claude ACP
  `PromptResponse.usage` is the sum across a turn's API round trips, not one request's
  prompt shape. The turn's accounting totals now travel at
  `usage.acp.{input,output,cacheRead,cacheWrite}`; pi's four request-shaped fields remain
  zero, while `usage.totalTokens` remains the vendor's context-occupancy reading. Consumers
  that display ACP token/cache accounting must read the new key — `agent-config`'s
  `pi-extensions/glg-footer.ts` does so at `47b9b95`. The numerator is taken from the
  vendor's ACCOUNTING-GRADE `_meta.quota.model_usage` rows (summed) in preference to the
  main-loop-only `PromptResponse.usage`, because the cost denominator is an adjacent diff of
  the backend's running total and already has that wider scope. Deterministic receipts:
  `scripts/check-acp-usage-accounting.ts` CELLs 1/1b drive pi's real overflow and context
  readers with the incident-scale 4,185,084 cache-read aggregate on a 223,516-token context,
  and CELL 1e drives both token carriers at once so a silent fallback to the narrow one
  cannot pass for a preference.
- **ACTION REQUIRED — the certified Claude ACP dependency coordinates move together, and
  this release REQUIRES them.** The bundled Claude adapter is
  `@agentclientprotocol/claude-agent-acp` **0.70.0 → 0.73.0**, its wire SDK is
  `@agentclientprotocol/sdk` **1.3.0 → 1.4.0**, and the resolved transitive
  `@anthropic-ai/claude-agent-sdk` is **0.3.232 → 0.3.257**. This is not a refresh riding
  along with the fix: `_meta.quota.model_usage` does not exist before adapter 0.71.0 (added
  by upstream `fad4d10`, "report per-model token usage on prompt responses"), so the
  accounting above has no accounting-grade numerator without this bump. Three adapter minors
  are folded into one certification; the per-bump measurement — declared-dependency deltas
  per tag, the zod floor narrowing at 0.71.0, lock peer-resolution, the reachable/unreachable
  split of the new surface, and the re-measured MCP readiness boundary — is recorded in the
  ROADMAP "Dep bump(별도 트랙)" ledger. Re-run the ACP support gates on any locally
  overridden adapter command before treating that command as covered by these coordinates.

### Fixed

- **Claude ACP no longer presents a turn aggregate as one request to pi.** That projection
  caused pi's raw overflow reader to compact a live 223,516-token session under a
  1,000,000-token window, invented two phantom cache misses, and silenced the one real miss
  after a 401-minute idle gap. The aggregate is retained as accounting evidence, context
  occupancy remains separate and is carried forward across a turn that reports none, and a
  material re-billed prefix is reported as a PROVEN LOWER BOUND rather than silently hidden.
  Turn cost remains the adjacent difference of the SDK's cumulative estimate, never a local
  reprice. A backend with no measured semantics (cortex) is still sealed not at all.
- **The re-billed-prefix bound no longer mixes main-context occupancy with wide accounting IO.**
  `readTurnAccounting` prefers `_meta.quota.model_usage`, whose rows also count Task subagents,
  sidechains, and internal compaction. Feeding that `cacheWrite` into a bound whose occupancy is
  main-context inflates the lower bound through both remaining terms, so a warm main prefix can
  announce a miss and attach this turn's dollar figure to it. The bound and its stored prior now
  read `PromptResponse.usage` (main loop) only; `usage.acp` stays the wide totals. Deterministic
  oracle: `scripts/check-acp-usage-accounting.ts` CELL 1f.
- **A backwards session total no longer asserts a cause it has not measured.** The operator
  diagnostic for a decreasing cumulative cost previously named a conversation reset as "the
  known cause". The adapter's `conversation_reset` handler only switches to a fresh
  conversation and touches no cost (0.73.0 `dist/acp-agent.js:3675-3682`); the documented
  mechanism lives in claude-agent-sdk instead, which states that a mid-session `/clear`
  resets the running total (`sdk.d.ts:4884`). The notice now reports the observation, names
  `/clear` in the vendor's own word rather than paraphrasing it into a different noun, states
  explicitly that the adapter's `conversation_reset` event is NOT that mechanism, and says plainly
  that the cause is not measured here. Naming the disproven event as the documented cause was the
  release's own thesis being violated inside its own diagnostic; it was caught in review.

## 0.16.1 - 2026-09-01

### Verification

Each receipt carries its own scope; none of them is transferable to another commit or host.

- **`pnpm run check:full`** — PASS, exit 0, **454s** inside the gate, on the 0.16.1
  versioned tree (HEAD `2e7ceb4` + the uncommitted changelog/version edits).
- **`./run.sh check-gate-qualification`** — **335/335 KILLED, NOT KILLED 0**, as the
  release-gate MUST step. The first run of this cut reported **334/335**: the single
  miss was `PACK-INSTALL-PIN-MATCHER-BOUNDED` reading `MUTANT-STALE` because `5c1bda5`
  moved `run.sh`'s pin matcher to the 0.84.4 floor and left that mutant's anchor on
  0.84.3, so it matched 0× and the gate had silently stopped asking its question.
  Repaired in `2e7ceb4` and re-run green. A rotted anchor is recorded here rather than
  quietly fixed, because "N killed" only means something when N is the whole set.
- **`LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.16.1.m0LUjr --cut`** —
  **MUST: PASS=23 FAIL=0 SKIP=0**, **BEHAVIOR: PASS=1 FAIL=0 SKIP=0**. Log at
  `/tmp/entwurf-release-gate-0.16.1.m0LUjr/release-gate.log`. `smoke-mux-lifecycle-live`
  failed the first run on a pi-native nonce callback that never arrived inside its 300s
  window (the codex rail was measured healthy at the time: 5h 23%, weekly 77%), and
  passed on re-run — recorded because a LIVE step that needed a retry is not the same
  evidence as one that passed first time.
- **#72 launch/observation receipts** — the launcher's two field claims are not
  unit-provable, so they were measured on the host that produced the failure:
  `/proc/<pid>/cmdline` carries no vendor name, the janitor's own Phase 1 selector run
  against the real `ps` row with its age threshold forced to 0 selects nothing, and a
  real SIGTERM still ends at exit 0 with the frame on stderr. Commands and output in
  `scripts/raw-acp-child-exit-measure/README.md`.

### Added

- **`setup` composes OMP — the fifth backend is now in the one command.** v0.16.0 admitted OMP
  as a D6 citizen with installers, doctors and inverses for every unit, but `setup_all` had no
  `omp` branch: on an operator host the released package printed a **green** setup summary while
  OMP had nothing installed — no extension, no `mcp.json` entry, no garden id on the status line.
  Presence-driven now, same shape as Copilot: `omp` on PATH composes four independent named
  components (birth → MCP hand → the `tools.xdev` operator setting → receiver), absent is one
  zero-state SKIP, and a detected-but-incomplete unit is a named FAIL owning a nonzero exit.
  Gate: `smoke-setup-verdict` S-8 drives the real composition against a stub vendor and asserts
  every install-state, both extension units in the sandbox agent dir, the effective `xdev-off`
  reading, and idempotence on a second run; S-1 pins `OMP_BIN` absent and requires the SKIP row.
- **`install-omp-config` / `uninstall-omp-config` — the operator setting is a unit, not a
  documentation step.** `tools: xdev: false` was a hand-edit in `docs/setup-clean-host.md`, so a
  host that skipped it registered every entwurf tool behind the vendor's `xd://` wrapper and the
  doorbell announced a tool the model could not call. The writer owns exactly the lines it adds
  (recorded in its install-state), refuses a symlinked config, refuses a config it cannot parse,
  and refuses an EXPLICIT operator `tools: xdev: true` **by name** rather than overwriting a
  decision — setup surfaces that as a component FAIL for the operator to resolve. The inverse
  takes back only the recorded lines and refuses when the file changed since install.
- **`docs/adding-a-harness.md` step 10 — an onboarding is not finished until `setup` composes
  it.** The rule the OMP gap forced, with the five conditions a new harness owes (presence-only
  trigger, one independent component row per unit, compose only what an inverse can undo,
  operator settings are units with a refusing writer, pin the probe seam and add an aggregate
  cell) and the shape to watch for: two closed parity loops with no gate owning the edge between
  them.

### Changed

- **pi floor moved to 0.84.4.** devDependency exact pin, the three peer ranges (`>=0.84.4 <0.85`),
  the `check-pack-install` runtime pins, the pin-leak matcher's version boundary with its synthetic
  fixture, and the pnpm lockfile all move together — the floor is one fact with several spellings,
  and a partial bump is how they drift apart.

### Fixed

- **#72 — the ACP Claude child is no longer selected by the host janitor that was killing it, and
  a caught signal survives the vendor erasing it.** The child was not crashing: it was being **SIGTERMed from outside**. A
  janitor installed on the operator's host for a *different* harness (openclaw's acpx, upstream
  PR #245) selects the vendor process name `claude-agent-acp` by **argv substring** and kills
  anything older than 900s. entwurf **retains** its child across turns, so that child's age is the
  age of the SESSION, not of a turn — every session past 15 minutes was shot at every 5 minutes.
  The vendor's own handler then turned the signal into `dispose(); process.exit(0)`, so the death
  reached entwurf as exit code 0 with no signal, indistinguishable from a clean shutdown. That is
  why three diagnosis passes retired four candidate causes and still missed it. Measured: **12 of
  12** anomalous terminations across two boots correlate with a reap, pid- and timestamp-locked —
  including the sample that opened the issue (2026-07-30) and the original field report
  (2026-08-16); receipts in `scripts/raw-acp-child-exit-measure/`. Two changes, both inside the
  issue's repair fence (no timeout, no replay, no watcher/supervisor/hidden retry): (a) the default
  launch is now an **entwurf-owned launcher** (`pi-extensions/lib/acp/claude-acp-launch.js`) that
  imports the vendor **in-process** — same process, so there is no child to restart and it cannot
  become a supervisor — carrying a name no vendor-name scanner matches, consuming no argv (the
  vendor's own `argv.slice(1)` self-reinvocation still works), standing down if it would otherwise
  be the only signal listener (an observer that suppressed default termination would make the
  process signal-immune), and dying nonzero without retry if the import fails; (b) a caught
  SIGTERM/SIGINT is recorded as a **typed lifecycle fact** on its own line
  (`launch observed SIGTERM before child exit (sender not attributed)`) via an exact full-line
  control frame that is consumed out of the vendor stderr tail — the tail stays vendor evidence,
  the observation is entwurf's, and sender attribution is explicitly NOT claimed (that needs the
  host journal). `CLAUDE_AGENT_ACP_COMMAND` stays verbatim: an operator who names their own command
  owns the result. **Known trade:** after the name split a host janitor can no longer collect
  entwurf's children even when they genuinely leak, so entwurf now owns that cleanup story.
  **Read the order right: the cause was the host's janitor, and its owner has retired it**
  (`nixos-config e283d92`, 2026-09-01 — `acp-zombie-reaper.timer` disabled). Measured there:
  PR #245 is CLOSED, not merged; that deployment runs `acp.enabled=false` with no ACP agent;
  acpx is not even installed in the running image (`/app/node_modules/acpx` absent, its `.bin`
  entries dangling symlinks); and every reap since the 2026-06-10 ACP removal was a single-process
  misfire matching our pid table. So the change here is **not what stops the symptom** — the
  retirement is. It is defense-in-depth against the class, and that class is wider than this
  issue: the selector reads the WHOLE `ps` line, so on a harness that puts the prompt in argv, a
  session merely *discussing* `claude-agent-acp` matched. Measured 2026-09-01 with zero ACP
  processes alive, the script's own counter read `alive_acp=3` — three ordinary agent sessions,
  one of them the session investigating it. A launcher whose name we own survives the next such
  janitor too. Gates:
  new `check-acp-launch-namespace` (2 mutants) plus `check-acp-prompt-lifecycle` CELLs 12–13,
  where 13 is the negative sibling holding that vendor prose mentioning `SIGTERM` can never forge
  the observation (3 mutants). The primary repair still belongs to the janitor's owner — a cleaner
  should scope by a positive marker it owns, not by a name anyone may share.

- **A vendor-written `config.yml` no longer reads as `unreadable`.** omp's own settings writer
  emits `modelRoles:` followed by an indented `{}`, and `scripts/omp-tool-surface.py`'s
  block-only reader returned None for the WHOLE file on that shape — so an untouched operator
  config classified as unreadable and `doctor-omp-mcp` went RED for a reason unrelated to
  `tools.xdev` (measured on a real host, omp 18.0.0). The reader now parses flow collections in
  value position and as a whole child block. `check-omp-fresh-preflight` gains the vendor shapes
  plus `[QK:OMP-XDEV-VENDOR-SHAPE-READABLE]` direct assertions — agreement between the two
  readers could never catch this, since both collapse `unreadable` and `true` into "not false".
- **The Copilot plugin-row grammar admits the vendor's state token.** Copilot CLI 1.0.81 prints
  `<qualified> (v0.1.0) (enabled)` plus an indented `from <path>` continuation line;
  `copilot_exact_row_version` read the version as `0.1.0) (enabled`, called the row malformed,
  and refused the birth install on a host whose plugin was installed and enabled — `entwurf
  setup` reported `copilot-birth: FAIL`. The grammar now admits exactly one optional
  `(enabled)`/`(disabled)` token; any other trailing token is still malformed. The fake vendors
  in `scripts/fake-copilot-vendor.sh` and `check-copilot-birth-hook.ts` emit the 1.0.81 shape,
  with `[QK:COPILOT-ROW-STATE-TOKEN-ADMITTED]` holding both directions.

## 0.16.0 - 2026-08-31

This release admits **OMP (`omp`) as the fifth garden backend** and closes the admission
contract that let a citizen ship without the legs that make it reachable. Bundles A, B and C
are one arc — birth and identity, addressed receive, visible fresh — and the durable half is
the general rule they forced: from OMP onward, the FIRST release of a harness admitted under
the #82 contract owes its clause 7 visible-fresh receipt as a release-gate MUST step, its
citizen↔fresh parity edge inside `pnpm run check:full`, and two cross-harness dispatch
receipts. Every OMP LIVE claim below is one Linux host, one model, one accepted run; that
limit is stated once in Notes and is not softened anywhere above it. (#87)

### Added

- **OMP is an addressable garden citizen.** `omp` enters the backend registry (`wakeMode`
  `self-fetch`, `deliveryLevel` `D6`, `nativeIdLabel` `sessionId`) and
  `pi-extensions/meta-bridge-omp.ts` mints it: an omp hook IS an in-process extension, so
  birth, the scope fence, the status line and the sender marker are one module. Both birth
  edges are bound — `session_switch` is where `/new`, fork and in-TUI resume re-fire — and
  every mode but `mode === "tui"` is refused before any write. The fence is the vendor's own
  mode and nothing else: `hasUI` is true under rpc/rpc-ui/ACP, so a fence built on it would
  admit exactly the sessions this refuses. A task subagent mints nothing. The step-6 join is
  one process, so the marker is keyed to `process.pid`, never `process.ppid`. Gates:
  `check-omp-birth-hook`, `smoke-omp-bridge-state`, `scripts/mutants/omp-birth.json`. (#87)
- **An omp-native MCP hand that shadows the borrowed Claude import.** The writer targets omp's
  own `<omp agent dir>/mcp.json` in the vendor's own writer shape, and the server key is a
  PINNED LITERAL `entwurf-bridge` — that pin is the entire mechanism. On a host that ever used
  Claude Code, omp already imports an `entwurf-bridge` server labeled
  `external-mcp/claude-code`; native provider priority beats the import and dedupe is
  first-wins on the key with `equivalent()` never consulted, so a byte-identical key suppresses
  the import while a different key would load BOTH and one of them would keep introducing an
  omp session as Claude Code. `disabledServers` is never the hide-import tool — suppression is
  by name and a suppressed item still claims the key — so the writer refuses to install under a
  denylist of its own key and the doctor is red while one exists. `doctor-omp-mcp` adds an
  EFFECTIVE-source read (native-wins / import-wins / both-suppressed / no-entry) and labels it
  what it is: a configuration read of vendor precedence, never a runtime receipt. Gate:
  `smoke-omp-mcp-state`. (#87)
- **OMP receives addressed messages — the garden is no longer one-way for it.**
  `pi-extensions/meta-bridge-receive-omp.ts` joins the citizen in the SAME process, holds an
  `fs.watch` on its mailbox signal, and rings an announce-only doorbell through the vendor's
  `pi.sendUserMessage` — measured to live on the factory object rather than the event ctx, and
  measured to start a turn on an idle host with zero typing. The model drains with
  `entwurf_inbox_read`, and that read is the receipt. The `/new` unarm is rail-specific: the
  watch lives inside the operator's TUI, where pid plus start-key cannot see a citizen change
  underneath a living process, so the old garden id is explicitly unarmed and the replacement
  armed. Bounded arm defer, watch-error, vanished-signal and overlapping-edge paths are all
  fail-closed. Install, uninstall and doctor surfaces ship with it, plus
  `check-omp-receive-arm` with `scripts/mutants/omp-receive.json`, `smoke-omp-receive-state`
  and `smoke-omp-receive-live`. (#87)
- **`entwurf_fresh_call` opens omp on all three public surfaces.** A five-axis pre-mutation
  preflight decides the launch before the tmux window exists, so a missing prerequisite is a
  named refusal instead of a dead window; the fifth axis is omp-specific (`tools.xdev !==
  true`). There is NO positional prompt. The fixed registered flag `--entwurf-bootstrap`
  carries a closed `{v,target,nonce,task}` grammar — an unknown key is a refusal — and the
  installed birth extension runs a two-stage bootstrap: bounded readiness polling over both
  public tool snapshots, a callback-ONLY prompt, then the task released only by the exact
  successful `tool_result` (stored `toolCallId`, tool name, target, nonce and
  `isError === false` all matching) and delivered at that same session's next `turn_end`. That
  shape is a measurement, not a preference: the positional candidate opened its window, minted
  its citizen, received the framing byte-identical, and answered the literal text `ACK` with
  zero tool calls — the vendor's interactive UI defers MCP discovery while the positional
  `initialMessage` prompts straight after `mode.init()`, so the turn began roughly 830ms before
  the tool it was told to call existed. (#87)
- **`check-harness-admission-parity` — the missing edge between two closed loops.** Every
  backend in `META_CITIZEN_BACKENDS` must appear in `FRESH_CALL_BACKENDS` or be a declared
  pre-#82 legacy admission whose exception a reader can find in `DELIVERY.md`. Registry↔citizens
  and surfaces↔fresh-set each already had a guard, but no file imported both constants, which is
  how omp could pass the entire floor as a D6 citizen that `entwurf_fresh_call` cannot open. The
  gate went red on `Unaccounted: omp` the moment it was added and green when Bundle C closed it.
  It runs inside `check:contracts`, and therefore inside `pnpm run check:full`. (#87)
- **Two OMP LIVE steps in the release-gate MUST tier.** `smoke-omp-fresh-live` is clause 7's
  worked instance. `smoke-omp-receive-live` reads the capability registry and decides its own
  outcome — no drainable mailbox is a protocol SKIP, which `--cut` reads as red; a registry
  claiming a receive rail with no acceptance body here is a FAIL. Neither is a hardcoded pass,
  and the receive step was wired while omp was still outbound-only, so the one-way boundary
  stopped being prose a cut could pass over in silence. (#87)
- **`docs/adding-a-harness.md` gains the shipped map and the release stop.** A comparative table
  of the five admitted backends — lineage, receive rail, callback dialect, fresh launch form —
  sits at the top so the variety is expected rather than re-derived at each admission. It pins
  two lessons: lineage does not choose the rail (omp is pi underneath and rides Claude's mailbox
  shape, because the rail follows the measured wake surface; what ancestry does instead is
  concentrate the danger, since a shared env vocabulary is exactly where a fork splits a store),
  and the doorbell doctrine — a hard bridge of measured dialects, explicit doorbells and honest
  rejects is what makes the thing on the other side a peer rather than a disposable worker. The
  release stop then states both executable halves of the admission rule plus the cross-harness
  leg. (#87)

### Changed

- **`setup` is the install story on all three entry shapes.** npm global, npm project-local and
  source clone now lead with `entwurf setup <project>`; `entwurf install <project>` is stated as
  the narrower pi-wiring repair leaf that composes no harness. The 14-line native-harness paste
  that read as the install recipe is now "repair and doctors" — one paragraph plus the command
  names, with every per-unit installer, doctor and inverse retained, because a single broken unit
  must still be redoable alone. The user-scope ownership matrix and the manual MCP registration
  paths moved to the documents that already own them. Stale live claim corrected: after an
  upgrade the operator was told to rerun every owned installer; `setup` re-composes them.
  `package.json` gains the `copilot` keyword, shipped since 0.15.0 but unlisted. (#86)
- **OMP meta roots resolve as one indivisible bundle, never through `piAgentDir()`.** omp is a pi
  fork and inherits pi's env vocabulary, so `PI_CODING_AGENT_DIR` means "pi's persistence root"
  to entwurf and "my agent dir" to the vendor — a plain `omp --profile work` sets it. One pure
  resolver leaf now serves both consumers, the in-process birth extension and the omp-labeled
  bridge child, so agreement is by construction rather than two places computing the same thing.
  A relative override fails closed instead of letting cwd become an authority: measured, the same
  relative value resolved to two different stores because the extension's cwd is wherever the
  operator launched omp while the doctor's is the repository. Installers refuse rather than guess
  under an inherited `PI_CODING_AGENT_DIR` / `PI_CONFIG_DIR` / `PI_PROFILE`. (#87)
- **`PI_SESSION_ID` and `PI_AGENT_ID` are scrubbed at the launch seam for every backend.**
  Measured on the operator host: a tmux server env carrying `PI_SESSION_ID` was inherited
  verbatim by a new pane, so a sibling's bridge child could phone home under another citizen's
  identity. The scrub is at the seam, not per backend. (#87)
- **The deterministic floor composes the omp gates.** `check:hermetic` gains
  `smoke-omp-bridge-state`, `smoke-omp-mcp-state`, `smoke-omp-receive-state`,
  `check-omp-receive-arm` and `check-omp-fresh-preflight`; `check:contracts` gains
  `check-harness-admission-parity`. Both tiers still exclude the separately scheduled
  `check-gate-qualification`, and `setup` still does not compose omp. (#87)
- **`docs/adding-a-harness.md` step 5 now says to measure the invocation FORM, not only the tool
  name.** omp mounts MCP tools as `xd://` virtual devices by default (`tools.xdev`), so a correct
  tool NAME is still not a callable function: the model must read the device for a schema that
  `tools.xdevDocs` keeps off-prompt, then write JSON to the same path to execute. Measured on omp
  18.0.0, a plain send under that default listed peers and then reported delivery with nothing
  enqueued, and the mount also hid omp's own lsp, debug, browser and ast_edit — 11 devices in
  all. `tools.xdev: false` restores every enabled tool top-level and leaves plan mode's
  `xd://propose` finalization intact. (#87)

### Fixed

- **The bridge boot entry was in no typecheck program.** `mcp/tsconfig.json` extended the root
  config without re-declaring `exclude`, so the inherited `"mcp"` resolved to `<repo>/mcp` and
  filtered out everything its own `include` added; `mcp/entwurf-bridge/src/index.ts` — the
  785-line bridge boot entry — was the only tracked `.ts` in the repo in no `tsc --noEmit`
  program at all, and nothing imports it, so nothing rescued it through the import graph. Orphan
  census 1 line before, 0 after; the mcp program's repo-file count moved 27 → 54, all product
  sources. The emit path is untouched, so there is no product runtime change.
- **`entwurf_self` stopped rendering a mailbox nothing drains.** `metaDeliveryDomain` was derived
  as native-push or self-fetch, so an omp citizen was handed a `mailboxPath` with no drainer. It
  now has three values: `nativePushSupported` → native-push, else the decider's mailbox seam →
  self-fetch, else none. Dispatch and `wakeMode` are untouched. (#87)
- **`doctor-omp-mcp` reads `tools.xdev` on the runtime axis.** An absent file or key applies the
  vendor default (xdev on, empty inline allowlist) and is RED while the native hand is the
  effective source; `xdev: false` is ok and a covering `xdevInlineDevices` glob is
  ok-with-note. Ownership stays a separate question, and the smoke never touches the host
  `config.yml`. (#87)
- **The bootstrap epoch now ends before the birth edge can bail.** Epoch termination depended on
  reaching `startOmpBootstrap`, so a later birth edge that bailed early — a refused envelope or a
  throwing upsert — skipped the invalidation, and on a same-id resume both handler fences still
  passed, leaving the earlier defect shape alive in a narrow window. One rule, one owner:
  `endBootstrapEpochOnLaterEdge` runs right after the mode fence, before the envelope is read,
  and the consumed branch delegates to the same helper. Zero new state, zero new exports. (#87)
- **The omp-fresh qualification manifests were settled by measurement.** The first standalone
  qualification run on the Bundle C bytes caught what static exactness could not: four mutants
  whose claim and signature named different cells, one QK token minted twice in its gate source,
  twelve find hunks left stale by the bundle's own refactor and the amendment's rewiring, and one
  kill-site guess that died at an anonymous cell. Every repair was adjudicated by
  apply/gate/revert measurement rather than by guess, and kill sites the floor disputed were
  moved to where the kill actually lands. Separately, two mutants had been added to the
  self-address lane without extending `EXPECTED_LANE_MUTANTS` — exactly the drift that assertion
  exists to catch; the declared contract now says 5. (#87)
- **Two packaging omissions in the omp units.** `pi/meta-bridge-omp/entwurf-meta-omp/package.json`
  and `pi/omp-receive/entwurf-receive-omp/package.json` were absent from `files[]`, so
  `install-omp-receive` died in the installed package while passing from a checkout. (#87)
- **`check-pack-install` pins the transitive `@earendil-works/pi-telemetry` to 0.84.3.** Upstream
  published the 0.84.4 family on 2026-08-28; `pi-agent-core@0.84.3` and `pi-ai@0.84.3` both carry
  a `^0.84.3` caret on it, so the lockfile-less fresh-temp install floated to 0.84.4 and the leak
  assertion failed closed in the `install-surface` CI job. The pin keeps the verified 0.84.3
  constellation ours to hold; the leak assertion still guards every other pi package and any
  future closure growth. The 0.84.4 bump itself remains a separate hard-cut lane.
- **The omp doctor treated Bundle C's empty tmux scrub as inherited identity.** `tmux -e NAME=`
  writes `PI_SESSION_ID=` / `PI_AGENT_ID=` present-but-empty; authoritative readers trim and
  require truthy values, so empty and absent are the same answer. The doctor was presence-testing
  those names, which turned `check:full` red whenever a visible fresh omp citizen was alive.
  It now flags only a nonblank value, and the hermetic smoke hands it fixture pids rather than
  the host `pgrep`. (#87)

### Verification

Each receipt carries its own scope; none of them is transferable to another commit or host.

- **`./run.sh check-gate-qualification`** — **324/324 KILLED, NOT KILLED 0**, standalone on the
  Bundle C candidate (`fd5e462`), independently re-verified by a second model on the gate
  predicate plus a full-lane rescan and a 3/3 sample re-kill.
- **`pnpm run check:full`** — exit 0 in 430s on that same candidate, after the `build-bridge`
  refresh the stale-dist tripwire demanded.
- **Clause 7 LIVE** — `smoke-omp-fresh-live` green 2026-08-30, 21 assertions, oracle / omp 18.0.0
  / `openai-codex/gpt-5.6-sol`. The sibling's garden `20260830T192913-df52b9` came from the
  CALLBACK's sender envelope and never from the launch receipt; exactly one new citizen;
  `lastEnqueuedAt 10:29:19.179Z` / `lastReadAt 10:29:24.673Z`, with the drain visible in that
  session's own transcript for its own garden id. It took two runs: the first went red on
  stage-two delivery alone, which is the argument for making it a MUST.
- **Receive acceptance (D6)** — 2026-08-30, oracle, omp 18.0.0: garden `20260830T140819-116f6a`,
  `lastEnqueuedAt 05:08:20.555Z` / `lastReadAt 05:08:23.958Z`. D3 isolation is PROVEN, not
  pending: with two live armed omp citizens, one addressed enqueue rang exactly one doorbell
  while the sibling persisted no transcript and kept an empty mailbox.
- **Cross-harness leg** — 2026-08-31, the first bidirectional live-turn roundtrip on the committed
  bytes: a claude-code citizen opened a fresh omp sibling through the public surface (callback
  sender garden `20260831T124226-eac41a`), dispatched an addressed `entwurf_v2` into it, and the
  omp citizen's own live turn drained the doorbell and replied into the claude mailbox.
- **`LIVE=1 ./run.sh release-gate <scratch> --cut`** — **MUST PASS=23 FAIL=0 SKIP=0,
  BEHAVIOR PASS=1 FAIL=0 SKIP=0, `cut: OK`.** `check-gate-qualification` inside the gate
  killed **325/325** mutants across 36 lanes. Log:
  `/tmp/entwurf-release-gate-0.16.0.run2.DfMtRj/release-gate.log` (SHA-256
  `2df4f6d4bddd563431ca41d2a43074f2cb6ccf9926ec6e8c7323de1a6ddf8192`).
  A first attempt on the same versioned tree (scratch `.../entwurf-release-gate-0.16.0.AyHcIJ`)
  hit one MUST FAIL in `smoke-entwurf-v2-matrix-live` C1b: the hidden-store resident did not
  birth a record inside the 30s boot window. The same smoke rerun standalone passed 17 checks
  in 4.9s; the rerun cut above is the acceptance. `pnpm run check:full` on the versioned tree
  was exit 0 in 432s before P5.

### Notes

- **Evidence limit.** Every OMP LIVE claim above is one Linux host (oracle, ARM), one model, one
  accepted run. Multi-host, multi-model and repeated fresh calls inside one process are not
  claimed and are not evidenced here.
- **Operator prerequisite.** `tools: xdev: false` in `~/.omp/agent/config.yml`. Under the vendor
  default the doorbell would name a tool the model cannot call, so both the fresh preflight and
  the LIVE smokes check it as a precondition. `setup` does not compose omp.
- Measured against **omp 18.0.0** while the vendor announces 18.0.11. The `mode === "tui"`
  discriminator, the `xd://` behaviour and the five measurement cells recorded in
  `scripts/raw-omp-measure/README.md` §M7 are re-measurement targets on upgrade.
- Copilot's operator-metered clause 7 exception is preserved, not reopened. The release stop
  applies from OMP onward, forward-only.
- The cross-harness leg's deterministic half — every post-contract citizen backend having a wired
  cross-harness LIVE step or a declared metered exception — is an owed follow-up. Until that gate
  lands the rule is prose, and `docs/adding-a-harness.md` says so in place.
- Pi `0.84.4` remains a separate hard-cut lane.
- #90 is measured but unfixed: installed Claude Code sends `model` as a STRING on the interactive
  `SessionStart` envelope and omits it entirely in print mode, while the reader accepts only the
  object shape, so claude-code records carry no model. Widening the reader and pinning both shapes
  in a fixture is a separate lane.

## 0.15.1 — 2026-08-27

This patch is the Linux install-honesty floor for #86: Entwurf installs itself only,
`setup` composes harnesses the operator already chose, and a detected integration that
cannot be completed makes the command non-green. It is not a new garden capability.
macOS and native-Windows implementation move to #78; this cut makes no cross-platform
support claim.

### Changed

- **`setup` is presence-driven composition, not recruitment.** Mode is a named
  source-versus-installed branch before any prerequisite check or write. Each detected
  harness (pi, Claude Code, Copilot, agy) is completed independently; absence is
  zero-state SKIP; below-floor or incomplete is named FAIL and a nonzero exit. The old
  unconditional `DONE ... green` is gone — the summary is computed from component
  outcomes. Pi is optional-by-presence with the package-derived floor `>=0.84.3 <0.85`.
  A detected Copilot composes all four native units (birth → MCP → receiver → visible
  footer). Installed-package setup never runs npm/pnpm inside `node_modules`. (#86)
- **The shared Pi user-scope registration has a recorded owner.** Silent
  last-writer-wins normalization is retired. A second root's install/setup/remove refuses
  with zero settings writes and names `takeover-user-scope`; only that explicit operator
  verb moves the entry (old→new reported). The inverse removes only the recorded owner's
  exact entry. (#86 C2)
- **Setup no longer mutates credential stores.** The unconditional `sync_auth` path that
  copied the Anthropic OAuth object to an `entwurf` alias is removed. Hosts that already
  ran the legacy path keep the alias and `auth.json.bak` as a documented manual cleanup,
  not an automated one. (#86 A5)

### Added

- **Copilot birth has a package-owned inverse.** `uninstall-copilot-bridge` uses the
  qualified `plugin@marketplace` identity, runs a read-only ownership/safety preflight
  before any vendor write, and refuses to remove an unproven foreign unit. Installer,
  inverse, and doctor share one structural oracle. (#86 C3a)
- **Packed-consumer and all-absent setup rows are first-class fixtures.**
  `smoke-setup-verdict` and the installed `entwurf setup` path inside `check-pack-install`
  prove absence, independence, false-success refusal, and the named installed-versus-source
  branch without a model turn. That npm-consumer harness is the Linux install evidence
  #78 waits on. (#86)

### Fixed

- **Source setup now exposes the `entwurf` operator command Copilot fresh requires.**
  `./run.sh setup` manages `~/.local/bin/entwurf` as an ownership-checked symlink to the
  current checkout's `run.sh`, with per-bin state and an honest inverse. npm consumers
  already received this command through package bin linking; the missing source half caused
  `entwurf_fresh_call {backend:"copilot"}` to reject `runtime-unresolved` unless an unrelated
  global package happened to mask the defect. Source setup now fails loud when that
  operator path is foreign, outside PATH, or shadowed; helper units are attempted
  independently and a foreign helper is a named FAIL, never a warning followed by cosmetic
  success. The managed `entwurf copilot` boundary and every fresh/preflight/delivery
  contract are unchanged. Discovered while rechecking #82. (#86)

### Verification

- **`pnpm run check:full`** — PASS, exit 0, 252s standalone / 247s inside the gate
  on the 0.15.1 versioned tree (HEAD `4a23af1` + uncommitted changelog/version).
- **`LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.15.1.hAAn7U --cut`** —
  **MUST PASS=21 FAIL=0 SKIP=0, BEHAVIOR PASS=1 FAIL=0 SKIP=0, `cut: OK`.**
  `check-gate-qualification` inside the gate killed **277/277** mutants across 33
  lanes. Log: `/tmp/entwurf-release-gate-0.15.1.hAAn7U/release-gate.log`
  (SHA-256 `aa1364922301e685c650670dd6556a3c27feacdf1481d850d8e2ef56ef5cb23e`).

### Notes

- #78 owns macOS and native-Windows implementation. WSL remains Linux evidence.
- Native-harness doctors stay the per-leaf live-certification surface. Setup writes
  artifacts; a new session is still required before `doctor-meta-bridge` / Copilot receive
  can go green on a host that already had processes open.

## 0.15.0 — 2026-08-25

This release admits Copilot CLI as a full self-fetch garden citizen — birth, an owned
MCP hand, record-backed sender identity, an installed first-party receive extension, and
a visible-fresh launch path — closing #82, and fixes the fresh-launch YOLO regression the
admission work exposed.

### Added

- **Copilot CLI is a self-fetch garden citizen.** `birthCopilotCitizen` upserts
  `(backend:"copilot", nativeSessionId)` into the shared V3 record store, gives the
  session a garden id, an owned `entwurf` MCP hand, a footer statusline slot showing that
  id, and record-backed sender identity on every dispatched message. The receive rail is
  an installed first-party extension (`run.sh install-copilot-receive`) that binds to the
  V3 record, arms a watcher, and rings a doorbell the model drains with
  `entwurf_inbox_read`; `wakeMode` is `self-fetch`, so dispatch reaches the mailbox rail —
  armed sessions get `delivered`, unarmed or stale sessions get the honest
  `mailbox-undeliverable` refusal. Launch is exclusively through the owned invocation
  `entwurf copilot`, which sets `COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS` for that one
  process; a session started any other way is silently inert by design, and
  `doctor-copilot-receive` reads the live CLI environment to catch that class. (#82)
- **Fresh Copilot siblings are admitted through the same preflight contract as birth.**
  `copilot-fresh-preflight.ts` decides birth, MCP hand, receiver, and visible footer
  BEFORE the tmux mutation, so a missing capability is a named refusal instead of a dead
  window. `entwurf_fresh_call` takes one explicit model in Copilot's measured CLI dialect
  (`--model <name>` beside `--interactive <prompt>`) and opens through `entwurf`'s own
  managed invocation, never the bare vendor binary. (#82)
- **Visible-fresh and D6 receive are LIVE-accepted on one host.** 2026-08-23 D6 receive
  acceptance (garden `20260823T181316-d9f6ba`, CLI 1.0.80): `joined → armed → doorbell →
  rang`, mailbox enqueue/read timestamps, and a model reply on the same
  record/native/garden-id chain. 2026-08-25 visible-fresh acceptance: launch window `@89`,
  nonce `mux-fresh-call-690529ae99f99faa2252aefb`, exact-callback garden
  `20260825T085721-f68be0`, one `entwurf_v2` mailbox enqueue plus a same-garden reply, and
  an operator-observed footer garden id on a healthy multi-turn window. Both rows are
  evidence level L4 (one host) and stay unmerged; visible fresh is operator-metered and is
  not a release-gate MUST.

### Fixed

- **Fresh Copilot siblings now default to `--yolo`, matching the profile a human gets
  from `entwurf copilot`.** `mux-fresh-call.ts` previously passed a callback-only
  `--allow-tool=entwurf-bridge(entwurf_v2)` grant, which caused `copilot-launch.sh`'s
  explicit-policy scan to suppress its own `--yolo` injection — every task-tool call then
  stopped on a confirmation prompt the new sibling could not answer, making it practically
  unusable. GLG operator LIVE on 2026-08-25 confirmed the missing `YOLO` footer and the
  per-task-tool stalls; the fix restores the default without adding a permission
  parameter to the fresh-call API or changing the manual `entwurf copilot` override
  behavior. (#82 follow-up)
- **Pi runtime pin moves to `0.84.3`.** Certified development pin and closed peer range
  are now `0.84.3` / `>=0.84.3 <0.85`. `compat.ts` stayed byte-identical at the previous
  bump but `loader.ts` did not, so the diff was read and judged reachable before moving
  the ceiling; the argument is not reused across bumps and each future ceiling move is
  judged on its own diff.

### Verification

- **`pnpm run check:full`** — PASS, exit 0, 406s standalone on the prepared HEAD.
- **`LIVE=1 ./run.sh release-gate <scratch> --cut`** — **MUST PASS=21 FAIL=0 SKIP=0,
  BEHAVIOR PASS=1 FAIL=0 SKIP=0, `cut: OK`.** `check-gate-qualification` inside the gate
  killed **252/252** mutants across 30 lanes. Log:
  `/tmp/entwurf-release-gate-0.15.0.run2.fB2LLP/release-gate.log` (SHA-256
  `9a00a22e8b4ca715ad0b955b51c99a2bacc385bf0c225180026948a4618e5ff6`).
- A first attempt on the same prepared HEAD (scratch `.../entwurf-release-gate-0.15.0.7yUIFH`)
  hit one MUST FAIL in `smoke-mux-lifecycle-live`'s cleanup launcher-integrity self-fence:
  all 78 lifecycle assertions passed, but the Claude Code launcher symlink changed target
  and content mid-run (`2.1.243`→`2.1.245`) because auto-update was still on the default
  channel. GLG pinned `autoUpdatesChannel: stable` before the rerun above; this was an
  environment race during the LIVE run, not a defect in the 0.15.0 candidate.

### Notes

- Copilot's D7 grade is PARTIAL: reply and read receipts are observed; completion
  taxonomy and long-haul operation are not. D3 (second-session isolation of an owned
  invocation) is PENDING — observed once, but the decisive log was lost to scratch
  cleanup before it could be preserved; re-measurement is tracked outside this release.
- #76 (subscription-first refusal of `openrouter/*` sibling launches), #78
  (macOS/native-Windows portability evidence), #80 (public vocabulary), #83, #84, #85, and
  the remaining #72 field-cause investigation stay outside this release.

## 0.14.2 — 2026-08-20

This patch makes bridge availability a property of the exact invocation each harness will run, preserves child-exit facts across ACP transport closure, and records Copilot delivery as probe evidence without admitting a new citizen rail.

### Changed

- **ACTION REQUIRED — the certified runtime floor is now Pi `0.84.2`, with Claude ACP adapter `0.70.0`.** Pi's exact development pin and closed peer range move to `0.84.2` / `>=0.84.2 <0.85`; Claude ACP `0.70.0`, ACP SDK `1.3.0`, and Claude Code `>=2.1.217` are the measured support coordinates. Re-run setup after upgrading so the installed package and stable bridge launcher agree with this release. (#79)
- **Every live-spend harness default is now `openai-codex/gpt-5.6-luna`.** The cross-harness chain, the v2 matrix, mux fresh/lifecycle, the resident garden guard, and the `entwurf-dev` skill's Pi default all name the cheaper model; the `ENTWURF_LIVE_TARGET` / `ENTWURF_CHAIN_GPT_TARGET` / `SMOKE_RGG_MODEL` overrides are unchanged. Fixture model strings are deliberately untouched — they assert exact argv or routing and spend nothing. This is a cost decision, not a gate change: no step moved tier and the LIVE gate was re-earned on the new default rather than inherited. Antigravity has no harness-side model at all (the operator opens that conversation), so its free-account fence — `gemini-3.6-flash`, never a Pro tier — is recorded in `VERIFY.md` and the `run.sh` help.
- **Pi and Antigravity doctors boot the exact configured stdio invocation.** Runtime truth is separate from repair ownership: every effective Pi entry, including an unowned override, is probed without being overwritten; Antigravity preserves its configured `command`, `args`, and `env`. A valid MCP `initialize` response must arrive before `notifications/initialized` and `tools/list`, and the returned surface must equal the seven public Entwurf verbs. Closes #81.

### Added

- **A direct-native Copilot raw probe records one bounded Linux observation without claiming support.** The current probe binds a unique marker body to `user.message.interactionId`, then to one `assistant.turn_start.turnId`, and accepts only assistant events from that turn; missing or ambiguous identity fails closed, the control session rejects any `user.message` or `assistant.*` event, and cleanup is bounded. The earlier 2026-08-19 L4 observation used a chronological slice on one workstation and its stdout was not archived, so it is not evidence that the corrected named-turn contract has run LIVE. Copilot remains outside `MetaIdentity`, backend registries, `entwurf_v2`, native-push, fresh, and resume; admission work is tracked in #82.

### Fixed

- **ACP prompt failures no longer lose child exit facts when transport EOF arrives first.** A one-shot child-end latch gives an already-failed turn a bounded post-mortem settle before Entwurf teardown, preserving the original backend error plus lifecycle phase, exit code, signal, stderr tail, or an honest bounded absence. It adds no running-prompt timeout, replay, watcher, supervisor, or recovery API; #72 remains open for the natural retained-child death cause.
- **A configured bridge cannot pass because its name resolves, its defaults boot, or it answers `tools/list` before initialization.** Pi and Antigravity reject dead overrides, argument/environment-specific failures, invalid invocation shapes, malformed initialize replies, missing/extra verbs, and foreign or relocated launchers while retaining the rule that Entwurf never clobbers a launcher it does not own.
- **The release gate boots the operator's CONFIGURED Pi bridge invocation before it reaches the LIVE tier.** `check-bridge` only proves the launcher this checkout ships, so a relocated or shimmed `entwurf-bridge` that `command -v` resolves while `exec` returns 127 used to stay invisible until sixteen LIVE steps and real model spend later. `doctor-pi-provider` is now a release-gate MUST `run_step` — not LIVE-gated, with no skip arm — so that class fails in about a second instead of after a model turn. (#81 follow-up)
- **The bridge probe preserves the launcher's own stderr across fast exit and asynchronous stdin `EPIPE`.** It installs the pipe error guard before the first write, consumes newline JSON-RPC frames once, and waits for process exit plus stderr end before issuing the exit verdict, so a Node stack trace cannot replace the diagnostic the operator needs.

### Verification

- **Landing SHA `d0fb8e6a37d401fc5ef660c90c1051db4b0811e8`** passed exact-SHA GitHub Actions run [32230953648](https://github.com/junghan0611/entwurf/actions/runs/32230953648): `check`, `install-surface`, and `artifact-consumer` all concluded success. At that SHA the combined landing candidate passed focused bridge 11/11, Pi provider 52/52, Antigravity 177/177, qualification **184/184 killed**, and `pnpm run check:full` in 315s before push. Those two numbers belong to `d0fb8e6` and are kept as its record — they are not this release's shipped figures.
- **The accepted 0.14.2 candidate** passed qualification **185/185 killed** — the `release-gate` lane grew 11 → 12 with `PI-DOCTOR-IS-RELEASE-MUST`, added by `877b4da` — and `pnpm run check:full` in 207s standalone / 209s inside the gate (remeasured 2026-08-20; `run.sh` is a mutant subject, so the pre-edit 311s does not describe this tree). **185 is the shipped inventory.**
- **`LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.14.2.c5VqTP --cut` — MUST PASS=21 FAIL=0 SKIP=0, BEHAVIOR PASS=1 FAIL=0 SKIP=0, `cut: OK`.** Log: `/tmp/entwurf-release-gate-0.14.2.c5VqTP/release-gate.log` (SHA-256 `27346d86be4a1a96a8ea8cab97687fcce807e4fa4bd6e3d179b91f85dbbcbe53`). Both model-in-loop lifecycle steps ran on the new default: `smoke-entwurf-chain-live` and `smoke-mux-lifecycle-live` passed with `openai-codex/gpt-5.6-luna`, so the cheaper default is proven LIVE rather than assumed. Cortex stayed the documented on-demand axis and is not part of this aggregate.
- The new hermetic `check-probe-bridge-command` lane requires sequential initialization, exact tool equality, stderr preservation, bounded cleanup, and the stdin `EPIPE` guard; its `bridge-command-boot` qualification lane carries nine claims within the shipped 185-mutant inventory.

### Notes

- Snowflake Cortex has neither a subscription nor a free tier reachable from the source-owning host (measured 2026-08-20), so `smoke-acp-cortex-live` can only report protocol SKIP here. That is an absent axis, not a pass, and no other backend substitutes for it.
- Copilot is probe-only in this release. #82 owns authentication, permission, liveness, stale/crash, operator-session cleanup, durable LIVE evidence, and the final admit/reject decision.
- #76 (subscription-first refusal of `openrouter/*` sibling launches), #78 (macOS/native-Windows portability evidence), #80 (public vocabulary), and the remaining #72 field-cause investigation stay outside this patch.

## 0.14.1 — 2026-08-13

This patch fills the cross-repository creation gap in the visible mux lifecycle shipped in 0.14.0, so one operator tmux session can form siblings in multiple project roots without borrowing a dormant session as a cwd carrier.

### Added

- **`entwurf_fresh_call` accepts one optional literal absolute `cwd` for cross-repository siblings.** Omitting it (or passing `""`) keeps the caller's current directory; Pi and Claude Code receive the selected directory through their existing visible launch path, and the launch receipt reports the requested value without claiming runtime acceptance.

### Changed

- **The lifecycle selection matrix now separates address, continuity, and project root.** Use `entwurf_v2` for an existing live citizen, `entwurf_resume_call` only for continuity with a dormant Pi citizen under its recorded cwd and garden id, and `entwurf_fresh_call` for a new sibling — omitting `cwd` for the caller's project or passing an absolute `cwd` for another repository. Resume is not a substitute for cross-repository fresh creation.

### Fixed

- **The Claude meta-bridge installer relinquishes its retired ownership of `skipDangerousModePermissionPrompt`.** Proven prior install state is restored once when the value is still exactly entwurf's former managed value; operator-changed or unproven values remain untouched, malformed ownership evidence fails loud, and later uninstall cannot overwrite the returned choice.
- **The cross-harness chain LIVE smoke no longer inherits the runner's `PI_SESSION_ID` / `PI_AGENT_ID`.** When release-gate (or any pi `--entwurf-control` parent) spawned hop A, the MCP bridge preferred those carriers over A's SessionStart meta-sender marker and stamped the runner's garden id on hop 1 — payload still traversed, identity assertion failed. Child env now strips the pi identity carriers so the Claude hop's own marker is authoritative.

### Verification

- Release-gate candidate: the in-gate `pnpm run check:full` exited 0 in 208s, and `./run.sh check-gate-qualification` killed **173/173** committed mutants.
- `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.14.1.j2eAVu --cut` — **MUST PASS=20 FAIL=0 SKIP=0**, **BEHAVIOR PASS=1 FAIL=0 SKIP=0**, `cut: OK`. Full log: `/tmp/entwurf-release-gate-0.14.1.j2eAVu/release-gate.log` (SHA-256 `bdd4d0b332d08c24210e9f56382b5898c0544fb6dffbf70287dade2f00e67c36`).
- Pre-tag installed-consumer diagnostics also passed: `./run.sh check-pack-install` installed the 0.14.1 tarball and proved the seven-tool boot plus physical delivery; `ENTWURF_REQUIRE_DOCKER=1 ./run.sh check-install-container` reached `container-consumer: PASS` in a checkout-invisible non-root Node 24 consumer (throwaway candidate SHA-256 `48778d33d1088af8078fe6b59ad932fb34ac8564e80bef84c34b25bab2bd5ef6`). These are diagnostic pack-once artifacts, not the preserved release candidate.
- On the source-owned operator host, `./run.sh install-meta-bridge` completed the retired-warning relinquishment and `./run.sh doctor-meta-bridge` passed with live MCP owner join, physical delivery, and writer parity. Exact prepared-HEAD CI and acceptance of one preserved immutable candidate remain `make` responsibilities.

### Notes

- #76 (subscription-first refusal of `openrouter/*` sibling models), #60, #72, and #75 remain outside this patch.
- The chain-smoke repair only scrubs ambient pi identity carriers from its children. The MCP bridge's existing pi-carrier precedence is unchanged; any general nested-runner product guard is a separate contract, not part of 0.14.1 or #76.

## 0.14.0 — 2026-08-08

Two arcs meet in this release. The product arc makes sibling sessions **visible**: opening and resuming a garden citizen is now an explicit, observable act, and the hidden alternatives were removed rather than kept as compatibility surface. The verification arc keeps the product from being swallowed by its own test cost: the everyday gate now runs in under a minute while the release floor stays strict. Claude Code native + pi + the meta-record store remain the main rail; the ACP backends (Claude ACP, Cortex) are optional service adapters on top of it.

### Changed

- **ACTION REQUIRED — the Pi runtime floor is now 0.84.1.** Installing this release upgrades a 0.82.x/0.83.x host rather than leaving it in place: the peer range is `>=0.84.1 <0.85`, the development pin is exactly 0.84.1, and installed-package acceptance pins the expanded Pi package constellation. Claude ACP moves to 0.66.0: the 0.65.0 permission metadata reaches the wire but is label-independent, the steered-turn change stays structurally unreachable because entwurf does not send `session/steer`, and 0.66.0's new goal extension changes no entwurf behavior — entwurf never sends `_session/goal`, does not consume the initialize advert, a `/goal` prompt still reaches the model unchanged (the adapter only adds a goal notification), and that inbound `session_info_update` can reach the wire but falls inert to the event mapper's ignore path.
- **Delivery is visible-first and single-verb.** `entwurf_v2 fire-and-forget` never starts a process; a dormant control-socket citizen rejects as `dormant-fire-forget-unsupported`, and the reject hint now points at the visible resume verb instead of a manual workaround. The hidden `spawn-bg`/`owned-outcome` resume path and its gates were removed rather than retained as dead compatibility surface.
- **ACP `streamSimple` honors Pi's request hook contract without fabricating HTTP evidence.** `onPayload` receives and may replace the exact ACP `{sessionId,prompt}` request on new and reused turns under fail-closed validation and abort ordering; `onResponse` is an explicit zero-call exemption because ACP has no truthful HTTP status/header boundary.
- **Visible team formation and role authority are separate operating phases.** Fresh tasks form exact callback-correlated citizens and stop; the operator's later direct visible grant supplies coordinator/implementer/reviewer authority. No role database, watcher, retry loop, or orchestrator was added.
- **Verification is tiered by meaning, not by elapsed time.** `pnpm check` is the everyday core — it completes in under 60 seconds on the reference host (36s measured on this candidate) and prints its own wall time; `pnpm run check:full` is the deterministic candidate floor that push CI, the release gate, and `prepublishOnly` all agree on by name. `check-gate-qualification` runs once per frozen candidate, in every push CI check job, and as a release-gate MUST step — never inside the inner loop. The subtraction behind this was loud, not silent: the `probe-ordering` mutant lane's 84 infrastructure replants were succeeded 1:1 by direct assertions with an 84-entry ledger (#70), bringing qualification to 165 mutants across 22 lanes with the infrastructure-subject share down from 111 of 247 to 27 of 165. What did *not* happen is also part of the record: the hand-built surface shrank by only ~1.6% in lines — the cost shape changed, not the mass. Gates move tier only by semantic-class decision.

### Added

- **Visible mux lifecycle verbs now cover both creation and same-id Pi resume.** `entwurf_fresh_call` opens one visible Pi or Claude Code sibling with an explicit runtime model and learns its garden id only from the sibling's exact nonce callback envelope. `entwurf_resume_call` reopens a dormant Pi citizen in the operator's tmux session under its existing garden id, keeps LAUNCH and OBSERVATION receipts separate, and runs no turn; Claude Code honestly refuses same-id resume as `target-not-pi`.
- **Owner-normalized local identity facts are available through `entwurf meta-facts`.** The deterministic JSON projection exposes the strict V3 garden/native/transcript join and in-band defects by reusing the record owner's parser and store authority, so same-user consumers no longer need to maintain a weaker copy of the certification contract.
- **Vitest 4.1.9 enters as the standard test runner — a beachhead, not an occupation.** The fresh-call surface/provider lane boots the real bridge, captures native registration and the Anthropic provider conversion path, and validates host-regex patterns against a Rust-family engine; a second lane moves the ACP SDK dependency/resolver contract behind the same stable `run.sh` shim. Two hand-built gates migrated; new contracts now default to being born in the framework, and further migration stays deliberate and lane-by-lane.
- **An `entwurf-dev` operator skill rides in the repository (not in the npm package).** It is a development/verification tour tool: it lets the operator drive the current surface — list citizens, open a fresh visible sibling, correlate its nonce callback, send, resume — in natural language without memorizing tool calls.

### Fixed

- **Garden-id creation is exclusive across the certified active store.** CREATE writes the record bytes to a same-directory temp file first and publishes with an exclusive `link(2)`; an occupied final path fails loud with a named `MetaRecordError` — the refusal is occupancy-based, there is no retry, no check-then-write TOCTOU window exists, and the occupying record's bytes stay untouched. ATTACH keeps atomic in-place replacement of its own record; a collision surfaces as an error, never as an overwrite.
- **Mux LIVE smokes cannot delete a retargeted real Claude launcher.** A shared fail-closed fence pins the PATH-selected launcher, link, resolved target, and content before launch; both smokes restore the operator's exact XDG presence/value and verify launcher integrity before conditional fixture cleanup on success and failure paths.
- **Fresh-call verification now observes the host boundaries that source-text checks missed.** The escaped schema defect is replanted against Rust-family regex compilation and actual provider request bytes, and the session-identity generator oracle no longer relies on a probabilistic collision-free sample.
- **The install surfaces hold the public MCP tool set as an exact seven — and the shipped protocol suite's tool assertion runs at all.** Three independent installed-consumer gates required only the five pre-0.14 verbs: `entwurf check-bridge` (which under `node_modules` is the prebuilt-dist branch of `start.sh`), the packed-install boot inside `check-pack-install`, and the checkout-invisible `check-install-container` that release acceptance hands the preserved candidate. An artifact that booted and answered `tools/list` without `entwurf_fresh_call` / `entwurf_resume_call` therefore passed the very gates that exist to catch "green clone, dead consumer" — the two verbs this release ships were covered by no installed-surface assertion at all. All three now compare the whole set and refuse a missing, extra, or duplicated verb. Underneath them sat something worse: the tarball-shipped `mcp/entwurf-bridge/test.sh` wrote its tool check as `python3 - <<'PY' <<<"$TOOLS_JSON"`, two redirections onto one stdin, so Python executed the JSON payload as its program while the here-doc assertions never ran once and the `ok:` line printed unconditionally. That block is live for the first time, with duplicate detection and the v1-verb negative kept as its own named diagnosis. `check-entwurf-bridge-boot` gains the same equality as `G1f` under `[QK:BRIDGEBOOT-PUBLIC-SURFACE-EXACT-SET]` with its own exact-once mutant, because every assertion before it was existential and `entwurf_fresh_call` was named by none of them. Stale enumerations that drifted when 0.14 added the two verbs were repaired with the gates: the bridge module header, the agy auto-grant exclusion list (two named exclusions, now four — the mux verbs launch into the caller's own tmux session, which an agy conversation is not), the external-MCP-host and mux-rail docs, and the `check-bridge` progress line that named only the dev strip-types branch to an operator reading it from an npm install.

### Removed

- **The unimplemented `tmux-live` receipt transport has been removed from the v2 contract.** A mux window is an operator view — it may later expose a runtime, but it is never address authority or delivery evidence.
- **Injected session ids and hidden background resume are no longer launch substrates.** Fresh identity comes from the callback sender envelope; dormant lifecycle is the explicit visible resume verb.

### Verification

- Pre-version landing HEAD `9e14df518fb33bad59be14af31c64d71107b558d` passed exact-SHA GitHub Actions run [31258659484](https://github.com/junghan0611/entwurf/actions/runs/31258659484): `check`, `install-surface`, and `artifact-consumer` all success.
- The 0.14.0 prepared tree passed `pnpm run check:full` (full deterministic floor, 303s, exit 0); `check-pack` counted **342 files**.
- The initial prepared tree's `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.14.0.r8r31u --cut` completed **MUST PASS=20 FAIL=0 SKIP=0** (including the `check-gate-qualification` MUST step at **165/165 killed across 22 lanes**), **BEHAVIOR PASS=1 FAIL=0 SKIP=0**, `cut: OK`. Full log: `/tmp/entwurf-release-gate-0.14.0.r8r31u/release-gate.log`; per-step scratch/artifact paths are preserved in that log. The active LIVE set is native Claude Code, native pi, and pi+ACP; Cortex stays the documented on-demand host-auth axis, and no model-in-loop AGY step is in the aggregate.
- Closing verification-surface inventory (the #70 after-picture, measured by `scripts/inventory-verification-surface.ts`): **203 files / 58,893 lines** combined, against the #62/#70 baseline of 201 files / 59,775 lines — lines below baseline (**−882**) with the file count reported transparently (**+2**). The prepared tree measured 58,845 before the install-surface repair below added 48 lines of gate text; the shipping number is the one stated here, so an independent recount lands on it.
- **Install-surface repair and amended-tree re-acceptance.** The whole deterministic and installed-consumer set was re-taken on one frozen amended tree: `pnpm run check:full` **299s exit 0** with `check-pack` at **342 files**, `./run.sh check-gate-qualification` **166/166 killed across 22 lanes** (the +1 is the new `BRIDGEBOOT-PUBLIC-SURFACE-EXACT-SET`), `./run.sh check-pack-install` exit 0 with the installed boot listing all seven verbs, and `ENTWURF_REQUIRE_DOCKER=1 ./run.sh check-install-container` reaching `container-consumer: PASS` with the same seven from a frozen non-root global install. A project-local npm install under a sandboxed HOME was additionally driven through the operator-facing first command, `entwurf check-bridge`: exit 0, seven verbs, from the dist branch. The aggregate was then re-run against that amended tree on 2026-08-09 (oracle): `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.14.0-is.52cPh0 --cut` — **MUST PASS=20 FAIL=0 SKIP=0** (qualification MUST at **166/166 across 22 lanes**), **BEHAVIOR PASS=1 FAIL=0 SKIP=0**, `cut: OK`, exit 0. HEAD, porcelain, and the repo-root work-surface hash were identical before and after; the complete 3,943-line log is `/tmp/claude-1000/-home-junghan-repos-gh-entwurf/4a6914ab-d9da-4f67-9db2-5bf20f0ed168/scratchpad/p5-live.log` (SHA-256 `0e0f7f6168fa7484aed9db1b42a7b8945e9bcfcdb5745a23c9615992275efb7c`).
- Exact prepared-HEAD CI and the preserved-candidate container acceptance remain `make` responsibilities.

### Notes

- **Known open issues shipped with eyes open:** #60 (native-push drops `wants_reply`/caller envelope), #68 (naming the valid no-transcript resume refusal), #71 (`skipDangerousModePermissionPrompt` pinned while `defaultMode` stays operator-owned), and an observed long-turn error pattern on the optional Claude ACP rail that a post-release audit will reproduce and classify. None of these gates this release; all are tracked.
- **Ecosystem:** the `agent-config` repository's `entwurf-peek` skill was reworked against this release as its baseline — an advanced-operator density tool, not a requirement.

## 0.13.1 — 2026-07-31

### Changed

- **ACP prompt lifecycle no longer applies a 600-second wall-clock cutoff to a running turn.** Bootstrap remains bounded; user abort sends ACP cancellation before bounded teardown, and child exit/stdio failure now preserves lifecycle phase, exit/signal, and stderr evidence without automatic cold replay.
- **The release gate now makes actual invocation auditable.** Every MUST step reports PASS, protocol SKIP, or FAIL; `--cut` refuses a MUST SKIP without misreporting it as a failed call. The aggregate includes the native resume, spawn substrate, and authenticated cross-harness delivery chain; Cortex remains an explicitly documented on-demand host-auth axis.

### Fixed

- **Claude's tiny non-empty engraving carrier owns its leading boundary.** The SDK fixed identity sentence and `# Engraving Here` now occupy separate blocks while preserving auto-memory containment, deterministic signature bytes, and the empty override opt-out.
- **The ACP provenance and v2 dispatch surfaces state their real boundaries.** First-user augment versus system carrier is rail-specific, and the `entwurf_v2` description fits the host tool-description cap.

### Verification

- The versioned release tree passed `pnpm check`, including **144/144** kill-qualified mutants across 10 lanes and `check-pack` at **309 files**.
- `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.13.1.LeOQDB --cut` passed: **MUST PASS=20 FAIL=0 SKIP=0**, **BEHAVIOR PASS=1 FAIL=0 SKIP=0**, `cut: OK`. Full log: `/tmp/entwurf-release-gate-0.13.1.LeOQDB/release-gate.log`.
- On-demand lifecycle acceptance `LIVE=1 ./run.sh smoke-acp-long-turn-live` passed on the final source set: a **733,635ms** turn exceeded the retired 600s cutoff with exactly one cold ACP bootstrap and no replay. Cortex is deliberately aggregate-excluded for this cut because the oracle has no Snowflake connection; its 0.13.0 thinkpad LIVE evidence is carry-forward, not a fresh 0.13.1 host certification.
- `check-pack-install` packed and installed `0.13.1` into a fresh consumer, proving the installed bridge boot/delivery and previous-generation lifecycle without touching the real data tree. The preserved exact candidate's checkout-invisible Docker consumer acceptance remains a `make` responsibility.

## 0.13.0 — 2026-07-30

### Added

- **Snowflake Cortex Code joins the ACP rail as the first non-claude backend** — the `cortexAdapter` contributed by hvkiefer (PR #40), landed together with the revisions the CP0 live audit of 2026-07-29 measured against Cortex Code v1.1.52 (`docs/acp-backend-rail.md` §11-8 records the ten defects D1–D10 and the agreed contract; the deltas are drift repair, not contributor error). As landed: the curated surface is the GLG-decided 4-row set (`cortex-auto`, `cortex-claude-opus-5`, `cortex-claude-sonnet-5`, `cortex-openai-gpt-5.4`) riding real pi-ai registry bases behind the reserved `cortex-` routing prefix; launch is `cortex acp serve` from PATH (+ `-c <connection>` via `entwurfProvider.cortexConnection` / `ENTWURF_ACP_CORTEX_CONNECTION`) with **no `-m` pin** — the model is enforced per turn through `session/set_config_option("model", <native id>)`, the same wire call as claude, so a curated id the running cortex no longer serves fails loud before the prompt. Containment is a **session-scoped dual-HOME overlay**: cortex's config/skill/hook surface is `homedir()`-anchored and `CORTEX_HOME` outranks `SNOWFLAKE_HOME`, so the adapter refuses an ambient `CORTEX_HOME` outright (empty string included), runs the child under an isolated HOME (global-scope leak measured to zero; explicit cwd project scope retained), passes through only the measured-minimum auth (`connections.toml`, optional `config.toml`, `cortex/cache/credential_cache` — symlink-through, never copied), authors `autoUpdate: false`, and — because cortex's ACP `newSession` ignores the wire `mcpServers` param — **projects** the envelope-enriched explicit `entwurfProvider.mcpServers` into the overlay-private `cortex/mcp.json`, restoring the real operator HOME on the `entwurf-bridge` entry alone so a cortex sibling sees the real garden (an isolated-HOME bridge measured an empty citizen roster); non-stdio entries fail loud before spawn. Cortex is system-prompt-carrier-less: the operator engraving rides the first-user augment. Coverage: the deterministic `check-acp-cortex` gate (in `pnpm check`) plus the `acp-cortex` mutant lane's twelve kill-qualified claims — ten on that gate, and two cross-gate: the production overlay call site passing `resolveSessionKey`'s authoritative value (`check-acp-session-reuse`) and the real compiled provider entry registering both adapters' curated rows (`check-acp-provider-surface`, so an entry that silently dropped every `cortex-` row can no longer go green) — and the on-demand CP2 live smoke `LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> ./run.sh smoke-acp-cortex-live` — a real cortex model turn delivering outbound `entwurf_v2` to a seeded peer as itself, plus overlay disk facts and process-group reclaim (an MCP-configured cortex child ignores stdin EOF) — deliberately outside the claude-only **aggregate** LIVE floor, so a host that runs no cortex cannot redden a claude release; that is a wiring decision, and a cut shipping cortex still owes a deliberate run of it.
- **A host that does not run Cortex is unaffected by this release.** The external `cortex` CLI is not an npm dependency, and neither package install nor provider registration looks for the executable: the four curated rows are enumerated deterministically from the compiled provider entry, and `cortex acp serve` is spawned only when a turn actually selects a `cortex-` model — so selecting one on a host without Cortex fails loud at that turn rather than degrading install or the rest of the provider. The deterministic `check-acp-cortex` gate runs on fake/injected seams and needs neither the CLI nor Snowflake auth; the aggregate release floor contains no Cortex LIVE step; and the dedicated smoke honest-skips without `LIVE=1`, without `cortex` on `PATH`, or without a connection on the adapter seam. Rows are deliberately **not** hidden by PATH detection — that would make the provider surface differ per host and dissolve the exact-six-row fence — so an explicit operator enable/disable control remains a separate future contract, not a silent behaviour of this cut.
- **The ACP ordering probe lands as a gated instrument, and the readiness question it exists to answer stays open.** The rail's open question — whether MCP tool availability precedes what `newSession` returns — had no observable signal, so the probe injects a controlled fixture startup delay and reads control + D1 + D2 paired runs off one shared NDJSON axis instead of reconstructing order from separate logs with drifting clocks. A raw client may stand in for the backend only while a gate holds it to the same calls, arguments, and order, so `check-probe-ordering` pins the sequence against `backend.ts` source, attributes every failure to its wire phase, drives the probe-mode fixture as a real child process, types the event log at its door, and replays the paired-verdict truth table through the pure classifier. The log's door is a gate too: the envelope belongs to the writer, `ts` derives from a single clock read, and per `(runId, pid)` writer the raw append order must have strictly increasing `seq` and a non-regressing clock — a JSON-valid line with an unknown marker, a broken sort axis, or a payload the classifier cannot judge takes the INVALIDATED path instead of moving a verdict. The runner now holds the child open past the turn until the marker lands, the child exits, or a deadline anchored on the fixture's own delay markers passes, and only a deadline close lets a missing marker read as evidence; every intervention reports ordering and callability as two axes so a settled comparison is not buried by an unsettled verdict, and each ordering value is named for the comparison it is (`prompt-request-ahead-of-wire` says we issued the request first, never that the server failed to wait). The delta-B name oracle cannot be the model, so that seam is a CLI shim at `CLAUDE_CODE_EXECUTABLE`: the consumer half (target preconditions by key presence, absolute/regular/executable/no-script-suffix assertions, path+sha256 roster pinning with a post-pair re-hash, snapshot channel doors, receive-axis single-prompt binding, structural-vs-reading severity split) and then the producer shim itself both land kill-qualified. **No readiness finding is claimed.** The first paired run under the door contract produced 57 events with zero malformed lines, so the parser is calibrated rather than merely strict, and rail §11-7-b carries the numbers — but the verdict is inconclusive, and an inconclusive verdict is not "nothing wrong". Artifacts predating the window protocol re-parse as INVALIDATED and remain forensic records only.

### Verification

- Pre-version landing HEAD `9f1c7dc9e1fa77103e29a6f1884af7759e1595eb` passed exact-SHA GitHub Actions run [30505001694](https://github.com/junghan0611/entwurf/actions/runs/30505001694): `check`, `install-surface`, and `artifact-consumer` all success. That run is also the third-party half of the optionality claim above, at the strength its sources actually carry: `.github/workflows/ci.yml` provisions only checkout, pnpm, and Node 24 — it installs no Cortex CLI and supplies no Snowflake auth — and the required Linux `artifact-consumer` job ran the candidate inside a clean `node:24-bookworm` container and passed. That is a workflow-configuration fact plus a passing consumer run; it is not a probe of the runner image's contents.
- The prepared tree passed an independent `pnpm check`, including `check-gate-qualification` at **111/111 committed mutants killed** (the `acp-cortex` lane contributing twelve). Then `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.13.0.drnRyR` completed all green: **MUST PASS=17 FAIL=0 SKIP=0** and **BEHAVIOR PASS=1 FAIL=0**, EXIT=0. Full log: `/tmp/entwurf-release-gate-0.13.0.drnRyR/release-gate.log`; per-step artifacts are preserved inside it.
- Cortex acceptance on the landing tree (2026-07-30, Linux/thinkpad, Cortex Code v1.1.52, connection on the adapter seam): the on-demand `smoke-acp-cortex-live` passed **23/23** — a deliberate rerun *after* the `resolveSessionKey` overlay-scope repair, so the shipped claim no longer rests on the earlier CP2 run's code. `check-pack-install` enumerated the **exact six curated rows (claude 2 + cortex 4)** out of the installed package's own model list, and `ENTWURF_REQUIRE_DOCKER=1 ./run.sh check-install-container` consumed candidate `sha256=63342aa8a144011dee86ebea8f0b778c7860e54dc0f1c710438983c679e8af87` on `node:24-bookworm` (`id=sha256:fcd0f74fb415c752…`, `repoDigest=node@sha256:5711a0d445a1af54…`).
- Cross-rail live round trips are **operator-session evidence, not a gate** (2026-07-29, same implementation set): a Cortex resident used the host pi citizen's garden id rather than inventing one — `agentId=entwurf/cortex-claude-sonnet-5`, `backend=pi`, reply envelope `origin=pi-session`, `replyable=true` — and exchanged real turns with native Claude Code (mailbox drain), pi native (control socket), and pi ACP Claude Sonnet (control socket). The record `20260729T204101-7aaa6f` remains on disk as corroboration.
- **Deferred to `make` as a release-blocking tag gate:** the preserved exact 0.13.0 candidate must be installed into a fresh temporary root and drive one cold `entwurf/cortex-claude-sonnet-5` turn from *those installed bytes* — unique nonce, exit 0, candidate SHA-256 unchanged before and after, resolved installed package root recorded. Until it runs, installed-artifact evidence and real-Cortex evidence have never met in one execution; a RED there stops the cut before the tag. Prepared-HEAD exact-SHA CI and preserved-candidate container acceptance remain deferred to `make` as usual.

## 0.12.10 — 2026-07-27

### Changed

- **The Claude ACP dependency rail moves to `@agentclientprotocol/claude-agent-acp` 0.62.0.** The paired SDK surface fence now covers Claude Agent SDK 0.3.219; this is a dependency refresh, not a claim that MCP readiness timing changed.
- **The ACP rail document now names its unresolved readiness question precisely.** The ordered probe records wire availability, `newSession`, model enforcement, and prompt boundaries before any adapter remedy or Cortex work is considered.
- **Gate qualification is part of the deterministic floor.** Committed defect mutants run in an isolated snapshot and must fail their named `[QK:<claim>]` oracle; the agy permission contract is likewise covered by an independent literal matrix.

### Fixed

- **All citizen rails now share the same record authority without inventing pi privilege.** Control-socket, self-fetch, and native-push capability differences remain explicit while stale pi-special address and transport prose is removed.
- **The shipped pi and MCP tool descriptions tell the complete v2 dispatch truth.** Native-push direct injection, its three-valued probe rejects, mailbox deliverability, control-socket lock scope, and spawn-bg's separate relaunch transport are described and regression-fenced on both surfaces.
- **Native-push self-awareness and agy permissions follow their actual rail.** Native-push never advertises an inbox; normal-path agy approval covers `entwurf_v2`, `entwurf_peers`, and `entwurf_self` with per-rule ownership, strict state migration, and separate runtime/ownership doctor verdicts.

### Verification

- Pre-version landing HEAD `9a501b30f0e7d82307d885f1a1eb9d91c79c5f16` passed exact-SHA GitHub Actions run [30252596435](https://github.com/junghan0611/entwurf/actions/runs/30252596435): `check`, `install-surface`, and `artifact-consumer` all success.
- The prepared tree passed `pnpm check`; `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.12.10.d4gC9v` completed all green: **MUST PASS=17 FAIL=0 SKIP=0** and **BEHAVIOR PASS=1 FAIL=0**, EXIT=0. Full log: `/tmp/entwurf-release-gate-0.12.10.d4gC9v/release-gate.log`; per-step artifacts are preserved in that log. Prepared-HEAD exact-SHA CI and preserved-candidate acceptance remain deliberately deferred to `make`.

## 0.12.9 — 2026-07-26

### Changed

- **The curated ACP surface adopts Claude Opus 5 on pi 0.82.1.** The deliberately narrow two-model surface keeps Sonnet 5 and replaces the Opus 4.8 anchor with Opus 5 (1M context, 128K max output, reasoning enabled). The pi runtime pin, closed peer range, lockfile, install gates, and current-version docs move together; source review of pi 0.82.1 confirmed the extension-loader aliases and `/compat` catalog seam are unchanged.
- **`meta-bridge-fresh-cut` now reports the transition that actually occurred.** Exit 0 means the cut completed, 1 means nothing moved, 2 is usage, 3 means the cut transition is incomplete, and 4 means the generation was archived and the fresh v3 store opened but residue cleanup is incomplete. The command help, `run.sh` usage, operator docs, and deterministic decision/source-fence cells carry the same contract; exit 4 may proceed to `setup`, while rerunning after a new citizen is born would archive the new generation too.

### Fixed

- **A marker that cannot plausibly own a session no longer blocks the only repair verb or grants identity indefinitely.** The Claude hook, agy imprint, marker write boundary, all sender/receiver readers, fresh-cut inspection, and sender-candidate filtering share one `isPlausibleOwnerPid` policy. On the currently certified Linux desktop/workstation axis, pid 1 is refuted by construction and reported separately from a proven-dead owner; the cut clears that residue instead of waiting forever on init. A container running the harness as pid 1 remains unsupported and fails closed rather than quietly widening the evidence boundary.
- **`setup` preserves the repository's tracked pi settings across the full install path.** Both writers of `.pi/settings.json` now share one serializer, recognize the portable relative package entry as the same checkout, and leave already-satisfied bytes untouched. The end-to-end gate plants the candidate-index settings in a stand-in checkout, drives the real `run.sh install`, and requires byte and mtime identity, covering both writers and user-scope side effects rather than only a helper.
- **Duplicate `nativeSessionId` claims are quarantined on discovery and refused wherever a record becomes an address.** `entwurf_peers` lists neither rival while preserving unrelated citizens and naming diagnostics; canonical `entwurf_v2` dispatch checks the store before choosing any transport, and dormant pi resume uses the same addressable read. A regular unreadable rival fails loud because it might be the duplicate, while symlinked, drifted, or unparseable neighbours remain certification/listing defects without being promoted into addressable rivals. The deliberately narrower raw mailbox and marker paths retain the per-entry half of the contract; that boundary and its promotion rule remain tracked in #55.
- **Record bytes now come from the same opened file description that proves their kind.** `readStoreRecordFile` opens with `O_NOFOLLOW` so a final-component regular-to-symlink swap fails before a byte is read, uses `fstat` on that fd, reads through the fd, and closes in a `finally`. `O_NONBLOCK` prevents the fd-classification repair from introducing a FIFO hang. The preceding `lstat` classification remains a separate policy layer so settled sockets, devices, and mode-000 directories receive the certification contract's non-regular verdict instead of leaking `ENXIO`/`EACCES` as a second vocabulary.

### Verification

- Pre-version landing HEAD `aaab00fbd293300d25c294580bb19bd3a88ad757` passed exact-SHA GitHub Actions run [30186472796](https://github.com/junghan0611/entwurf/actions/runs/30186472796): `check`, `install-surface`, and `artifact-consumer` all success.
- The prepared tree passed an independent `pnpm check`, then `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.12.9.8NSzz7` completed all green: **MUST PASS=17 FAIL=0 SKIP=0** and **BEHAVIOR PASS=1 FAIL=0**, EXIT=0. Full log: `/tmp/entwurf-release-gate-0.12.9.8NSzz7/release-gate.log`; per-step artifact paths are preserved inside it. Prepared-HEAD exact-SHA CI and preserved-candidate acceptance remain deliberately deferred to `make`.

## 0.12.8 — 2026-07-25

### Changed

- **ACTION REQUIRED — hosts carrying a pre-v3 meta-record store refuse install and every identity write until an explicit generation cut.** The active citizen store is v3-only and carries no cross-generation address or resume continuity: sessions flow; memory lives in native transcripts and the embedding axes, never in the bridge. `install` / `setup` / citizen birth / `entwurf_register_native` refuse before writing when the store cannot certify and name the one repair verb: quiesce sessions, run `entwurf meta-bridge-fresh-cut` (dev clone: `./run.sh meta-bridge-fresh-cut`), then retry. The cut archives `meta-sessions/` + `meta-mailbox/` as forensic siblings and opens an empty v3 generation; no runtime reads the archive and no restore verb exists.
- **#50 hard cut: the meta-record is the only address authority.** V3 drops `parentGardenId` + `isEntwurf`, removes the v1 `entwurf` / `entwurf_resume` / `entwurf_send` tools and `/entwurf*` commands, deletes `pi/entwurf-targets.json` + `setup:links`, and authorizes dormant resume through record existence plus transcript-header ↔ `record.nativeSessionId` integrity. A call is not parentage and there is no species boolean.
- **The migration lane is deleted, not deprecated.** `meta-migration.ts`, the M1 backup/migrate/restore command, three gates (`check-meta-migrate-v3`, `check-meta-migration-readers`, `check-upgrade-gate`), and the frozen byte fixtures — 2,404 lines of deleted files, for continuity the substrate does not promise — are replaced by one generation verb (`meta-bridge-fresh-cut`) and one writer/doctor contract (`certifyActiveStore`). The whole upgrade story is quiesce → fresh-cut → go.
- **The runtime pins move together.** Pi rises 0.80.7 → 0.82.0 under the closed peer range and doc gates; Claude ACP rises to `@agentclientprotocol/claude-agent-acp 0.61.0` + `@agentclientprotocol/sdk 1.3.0`, with `@anthropic-ai/sdk 0.100.1` retained. The ACP send gate proves a provider model can send as its host socket-citizen.

### Fixed

- **One active-store contract is shared by the doctor and every identity writer.** `certifyActiveStore` requires each `.meta.json` to be a regular file, readable by the live schema, named by its own body, and the unique holder of its `nativeSessionId`; it runs store-wide before every identity write. Targeted reads enforce the per-entry half and never follow a symlink. Duplicate uniqueness on read/discovery remains tracked separately in #52.
- **Unknown is never silently converted to absent or dead on the fresh-cut path.** ENOENT alone means absence across record, store, directory and socket-entry inspection; EACCES/ENOTDIR/ELOOP and symlink/non-directory surfaces refuse as UNCERTAIN. The quiesce gate also probes marker-less native-push citizens through the same adapter dispatch uses, and `pgrep` exit 1 alone means no host while scan failures stay indeterminate. Five directory inputs across four code paths and the socket-entry layer are covered by F12–F18.
- **The archive plan refuses common half-cut causes before moving and reports every partial move honestly.** Store and mailbox may have different parents, so each planned rename preflights parent writability and every destination is inspected with ENOENT-only absence before the first move. No permission probe can promise a rename (sticky bit, immutable attributes, read-only mounts and LSMs remain possible); if a rename fails, the loop prints each `archived so far:` path, calls the generation HALF-CUT, and gives the exact retry/manual-inspection prescription.
- **Only a doctor verdict earns a destructive prescription.** Both store-doctor callers map exit 1 to certification defects → fresh-cut and exit 3 to access repair; usage, crash and unknown exits are doctor/runtime failures and prescribe no cut. `run.sh` also guards the actual doctor entry selected by its mode (source `.ts` vs installed compiled `.js`), so a missing artifact cannot collide with the doctor's defect exit. I7–I9 drive both callers and the installed-artifact seam.
- **The installed-host acceptance closed two operator/test seams.** `./run.sh remove-dev-bin` now shifts its own command name before invoking the honest inverse. Stable-bin smokes remove every pre-existing provider/statusline bin directory from their sandbox PATH, so a maintainer carrying both dev links and registry shims cannot mask a dangling-command negative.

### Carried from the repair line

- Exec-form Claude hooks + the enforced Claude Code `>=2.1.217` floor (repair.0), and the capability registry beside the emitted MCP bridge with live-command physical delivery in `doctor-meta-bridge` (repair.1), are promoted to `latest`. After publication the required registry shape is `latest=0.12.8`, `repair=0.12.8-repair.1`.

### Verification

- Pre-version landing HEAD `1345688001ed6629bd0f58996a36134e7b7874bc` passed exact-SHA GitHub Actions run [30150824225](https://github.com/junghan0611/entwurf/actions/runs/30150824225): `check`, `install-surface`, and `artifact-consumer` all success.
- Published `0.12.8-repair.1` passed installed `doctor-meta-bridge` on maintainer + secondary Linux hosts after a new real Claude session opened with a live MCP child; both runs included physical `entwurf_v2` delivery and live owner join (BASELINE HISTORY).
- On the stable prepared tree, `LIVE=1 ./run.sh release-gate` is all green — **MUST PASS=17 FAIL=0 SKIP=0** (its first step is the full `pnpm check`; the run includes `smoke-acp-bundled-mcp-live` and `smoke-acp-v2-send-live`) and **BEHAVIOR PASS=1 FAIL=0**, EXIT=0 — at scratch `/tmp/entwurf-release-gate-0.12.8.u9y9IX`, complete log `/tmp/entwurf-release-gate-0.12.8.u9y9IX/release-gate.log`, per-step artifact paths printed inside it. The static gate judges the **candidate index**, so the release-prep bytes were staged before the run, not merely present in the working tree.
- Prepared HEAD `e31c28f` passed exact-SHA GitHub Actions run [30152323861](https://github.com/junghan0611/entwurf/actions/runs/30152323861) with `check`, `install-surface`, and `artifact-consumer` all successful. The preserved candidate `junghanacs-entwurf-0.12.8.tgz` (sha256 `7c7e8985823391ec6dfae918e08c4aed1fafd06b7415806b2d591b0cb95891f3`) passed the checkout-invisible container consumer, was tagged as `v0.12.8`, released on GitHub, and published as `latest=0.12.8` while `repair=0.12.8-repair.1` remained unchanged.

## 0.12.8-repair.1 — 2026-07-22

### Fixed

- **ACTION REQUIRED — `0.12.8-repair.0` is published but cannot deliver to mailbox-backed garden citizens.** Its npm tarball contains the source capability registry but omits the copy beside the emitted MCP bridge, so the installed `entwurf-bridge` boots and answers `tools/list` while a real `entwurf_v2` delivery dies `ENOENT …/entwurf-capabilities.json`. The same omission exists in `latest=0.12.7`; this cut deliberately moves only the `repair` dist-tag, leaving stable promotion for a separately authorized `0.12.8` after post-publish host proof. Install this exact repair, rerun `entwurf install-meta-bridge`, restart every already-open Claude Code session, open a new session with its live MCP child, and require the installed `entwurf doctor-meta-bridge` to exit 0. The doctor now proves delivery, not merely configuration shape.
- **The shipped MCP dist now carries the capability registry at the location its emitted `meta-session.js` actually resolves.** `build-bridge.sh` copies `pi/entwurf-capabilities.json` to `mcp/entwurf-bridge/dist/pi-extensions/entwurf-capabilities.json`; this is the bundle-root contract already used by the Claude meta-bridge plugin. `check-capability-bundle-reach` discovers every shipped `meta-session` copy, asks each copy from its real location, requires byte agreement with the source registry, and drives `metaCapabilityFor()` for all four registered backends. `check-bridge-delivery` then seeds isolated sender/receiver citizens, starts the built dist entry as a separate MCP stdio process, calls `entwurf_v2`, and requires one `.msg`, the doorbell, the seeded sender envelope, and no capability ENOENT. The same scene is replayed against `check-pack-install`'s project-local npm-installed bin and the clean Linux consumer's non-root global PATH shim, so source, dist, installed tree, and checkout-invisible consumer no longer split “boots” from “delivers.” This restores the fire-and-forget mailbox lane; it does not claim the separate neutral-install dormant-pi `owned-outcome` follow-up is solved.
- **`doctor-meta-bridge` now drives the live MCP command Claude is configured to execute and requires a physical delivery in a throwaway world.** Ownership and behavior remain separate verdicts: the live `~/.claude.json` entry must equal `desired_mcp()`, and that exact live command—not a recomputed healthy command—must land one message and poke its doorbell. The probe redirects `PI_CODING_AGENT_DIR`, every meta store, and the socket root; no model, network, API cost, or operator mailbox is involved. Oracle mutations cover an absent live entry and a registry-less bundle that still answers `tools/list`, while the container mutation removes the registry only from the global install and proves every other doctor claim stays green as delivery alone turns red.
- **Delivery verification no longer changes identity depending on which harness runs it.** A pi-launched doctor inherited `PI_SESSION_ID` plus `PI_AGENT_ID`; the bridge chooses that pair before meta-sender discovery, so the message still landed while the claimed seeded Claude sender-marker join was silently bypassed. The doctor and deterministic delivery gate now scrub both pi carriers plus `ENTWURF_META_SENDER_MARKER`, require `ENTWURF_BRIDGE_REQUIRE_META_SENDER=1`, and inspect the landed body for the seeded `meta-session/claude-code` garden id. A planted ambient pi pair and explicit marker carrier are part of the control; deleting the scrub leaves physical delivery green but turns the sender assertion red.
- **The repair publication check is bound to the requested version instead of the already-published repair.0 literal.** The shared release skill now compares the registry's `repair` tag with `$VERSION`, while preserving the current contract that `latest` stays `0.12.7`; without this correction a successful repair.1 `npm publish` would have been followed by a false post-publish failure. The S7 install-surface gate binds the skill to SemVer prerelease syntax rather than to one obsolete example version.

### Verification

- Pre-version landing HEAD `4ae5aa874886fc889c0525369b5290066b6f96af` passed exact-SHA GitHub Actions run [29919713499](https://github.com/junghan0611/entwurf/actions/runs/29919713499): `check`, `install-surface`, and `artifact-consumer` all concluded success.
- On the repair.1 prepared working tree, `pnpm check` passed and `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.12.8-repair.1.81GJe3` completed with `MUST: PASS=17 FAIL=0 SKIP=0` and advisory `BEHAVIOR: PASS=1 FAIL=0`; full log: `/tmp/entwurf-release-gate-0.12.8-repair.1.81GJe3/release-gate.log`. The final preserved tarball, prepared-HEAD exact-SHA CI, container acceptance, tag, and GitHub release remain deliberately deferred to `make`; no candidate was created in prepare.

## 0.12.8-repair.0 — 2026-07-22

### Fixed

- **ACTION REQUIRED — reinstall the Claude meta-bridge and restart every already-open Claude Code session after upgrading to this release.** The old hook keyed sender and receiver liveness to `process.ppid`; on an observed installed host Claude retained a `/bin/bash -c` wrapper, so all markers were written under short-lived shell pids while the MCP child looked under the still-live Claude pid. The same Claude Code version also produced a direct join elsewhere and ordinary tail-exec tests never reproduced the trigger — so rather than keep fighting for a portable topology inside the shell form, **this release leaves the shell form entirely**. Every meta-bridge hook is now declared in Claude's **exec form**: `command` is a shipped `hook-launch.sh` and `args` is the real argv, so no shell is on the launch path at all. The launcher `exec`s its argv, which preserves the pid, and the hook's parent is therefore the Claude process itself on every host — structurally, not conditionally. Measured at Claude Code 2.1.217 (#51 B2): `args` elements arrive verbatim, a literal `${HOME}` is never expanded, and a `FileChanged` `asyncRewake` hook exiting 2 really does wake an idle session. The shell `$PPID` carrier, its ancestry walk and its missing-carrier contract are **removed**; the hook reads `process.ppid` directly. **entwurf now requires Claude Code `>=2.1.217` and enforces that floor itself, because upstream gives no fail-loud:** an older Claude passes `claude plugin validate` on the exec manifest and then, at runtime, DROPS the `args` array, runs `command` alone, and reports the hook as `exit_code: 0, outcome: success` — measured at 2.1.138. There is no shell-form fallback lane. `install-meta-bridge` and `doctor-meta-bridge` refuse an older version outright, and `hook-launch.sh` refuses an empty argv so that silence becomes a visible error on the host where it happens. **Upgrade mismatch stays deliberately fail-closed.** An already-open session still holding the OLD cached command reaches the new hook without the launcher, so the launcher stamps an explicit exec-launch provenance token and the hook mints NO sender/receiver marker without it: the meta-record still lands, but a session with no trusted send identity or deliverability evidence never claims one, and any older marker still on disk is not proof that the upgraded session joined correctly. Run `entwurf install-meta-bridge`, restart all existing Claude sessions so they load the new manifest, then run `entwurf doctor-meta-bridge`. The doctor refuses a shell-form or launcher-less manifest **by name**, requires the installed manifest to equal the shipped template modulo the two baked values, execs the installed argv directly (no shell) for a synthetic owner join, and on Linux requires live MCP↔sender↔receiver agreement — **missing live evidence is `NOT CERTIFIED` and a nonzero exit, not a WARN**. Linux is the only certified axis for this repair cut: `install-meta-bridge` refuses macOS because its live bridge cannot yet be discovered without `/proc`, doctor reports `NOT CERTIFIED`/nonzero there, and `uninstall-meta-bridge` alone keeps Darwin support so an older install can still be removed honestly. This is not a permanent impossibility claim; future native validation may reopen the macOS lane. New gates: `check-hook-launch-topology` drives the shipped argv for real, including a plugin path containing a space, `$`, a backtick and `;&`, and asserts the upgrade-mismatch fail-closed; `check-claude-floor-coherence` keeps the floor a single number derived from `package.json` `entwurf.claudeCodeFloor`.
- **The install gate pinned three of the four packages that make up the pi runtime, so it verified a runtime nobody verified.** `check-pack-install` builds a fresh temp project with no lockfile and pinned `pi-ai` / `pi-coding-agent` / `pi-tui` at the declared `0.80.7` — but `pi-coding-agent` depends on `@earendil-works/pi-agent-core` by CARET, so that fourth package floated to whatever pi published last and then dragged a NESTED `pi-ai` of its own. Measured 2026-07-21: the tree held `pi-agent-core@0.80.10` + `pi-ai@0.80.10` while the gate still printed `pinned pi 0.80.7`. Only the operator's stale pnpm metadata cache had been hiding it — refreshing the cache does not unblock the gate so much as let the unverified runtime in, which is why the earlier "npm registry partial publish" reading was wrong on both counts (`@aws-sdk/token-providers@3.1088.0` and `@earendil-works/pi-*@0.80.10` are both published; the local cache simply had not seen them). The gate now pins every `@earendil-works` package that constitutes the runtime **and reads the resolved tree back**, failing loud if any of them is not `0.80.7` — a pin is a wish until something asserts it.
- **A gate that cannot name which pi it proved has proved nothing.** `check-pack-install`'s loader and foreign-cwd smokes resolved `pi` through the **host PATH**, so the release commit's `install-surface` job went RED on a CI runner that carries no global pi — and the mirror image was worse: the gate had been green locally only because the dev box happened to carry a *newer* global pi (0.80.6) than the repo pinned (0.80.3). It was never driving the runtime it declares. Both smokes now drive `$tmp/node_modules/.bin/pi` — the pinned peer this gate already installs next to the tarball — and **assert `--version` against the `package.json` devDep** before proving anything with it. Review caught the fix reintroducing the very coupling it removes: the `--version` probe itself ran unsandboxed, and **pi reads settings before it prints its version** (`bootstrapSettingsManager` precedes the `--version` branch in pi's `main`), so the probe opened the operator's real `~/.pi/agent/settings.json` — 1 access before, 0 after (strace-verified). Every pi invocation in the gate now runs under one throwaway `HOME`/XDG/agent-dir env array. The rule this leaves behind: **a gate may not READ the operator's global install any more than it may WRITE it.** `AGENTS.md` rule 11 forbade only the write half, and the read half is the more insidious one — locally it is always green, so without CI it never surfaces.
- **The runtime-floor gate carried a pin that no gate enforced, and verified only half the range it declared.** `check-pi-runtime-version` held `const FLOOR = '0.80.3'` as a hand-kept literal that `check-dep-versions` had never seen: its assertions bind the devDeps to the peer range and to the `check-pack-install` peer-install pins, but nothing bound this constant, so a bump that forgot it would leave the runtime gate still blessing the OLD floor while every other pin moved. The floor is now **derived from the `package.json` devDep** (an exact `x.y.z` pin is required, or the gate fails loud): one pin to move, and the diagnostic names the real floor instead of a frozen string. The check is also **closed at the top** now, matching the range we actually declare (`>=<devDep> <0.<minor+1>`) — a floor-only comparison blessed any *future* pi, and "the runtime moved past the range while every gate stayed green" is this cut's entire subject. Mutation-checked in both directions: devDep `0.80.9` against the installed 0.80.6 fails the floor; devDep `0.79.9` (ceiling `0.80.0`) fails the ceiling.
- **`check-dep-versions` outlived its own doc coverage and kept advertising it.** The gate was born reading a doc: 362becd added it after the 21de0f9 pin drift (package bumped to 0.12.0, README left at 0.11.1) and asserted README's codex-acp install pin against `package.json`. bf4a533 then dropped the openclaw/ACP lane and removed that assertion with it — while leaving the coverage claim standing in the usage line and the function comment. So the doc half of the promise has been prose ever since, and the pi baseline docs were never bound to the gate at all. The pi pin lives in five of them, this bump touched all five, and what kept `demo/README.md` from being left behind was a hand-grep, not a gate. The docs are now **in** the gate: every closed-range declaration (`>=<floor> <0.<ceiling>`), every exact install pin (`@earendil-works/pi-<pkg>@<version>`), and four prose declarations that carry the pin in sentences those patterns cannot see (`current floor …`, `pi … fence`, `floor = **…**`, ``devDep exact `…` ``) must equal the devDep pin. A missing prose anchor fails loud rather than passing vacuously — a reworded sentence may not quietly drop the pin out of the gate — and a floor on the match counts guards against the whole doc scan silently matching nothing. History (`CHANGELOG` / `NEXT`) keeps its old versions; only sentences that *declare* the current pin are in scope. Mutation-checked: reverting `demo/README.md` alone to the old floor exits 1.
- **An unidentifiable Claude version could kill the installer/doctor before either printed its intended diagnosis.** The shared detector used `claude --version | head | grep | head` under the callers' inherited `set -euo pipefail`, and both callers captured it in a bare assignment. A nonzero CLI or output with no dotted triple therefore exited at the assignment instead of reaching the explicit install refusal / `NOT CERTIFIED` branch; a verbose writer also retained the known early-reader SIGPIPE shape. The detector now consumes the complete output, returns success-with-empty on failed/unparseable probes, and lets each caller own the diagnosis. `check-claude-floor-coherence` drives normal multi-line, unparseable, nonzero, and 128-KiB long-writer fixtures under `set -euo pipefail`, then invokes the real installer and doctor to prove they reach their own install-refusal / `NOT CERTIFIED` branches (and the doctor's final FAIL summary).

### Added

- **A required Linux artifact-consumer CI lane now tests the package in a world that has never seen the checkout.** `check-install-container` makes one candidate tarball on the host, mounts only that file read-only into a Node-24 Linux container, installs globally as a non-root user through an isolated prefix, resolves all five bins through PATH, freezes the package root, boots MCP `tools/list`, and runs `install-meta-bridge` plus the strict doctor under a regular-file path+sha256 fence. The output records canonical artifact path + sha256 and container image id/repository digest. Default CI keeps its pack-once temp mode; release acceptance may set `ENTWURF_CANDIDATE_TGZ` to a caller-preserved `npm pack` output, in which case the gate verifies name/version and consumes that exact file without chmod/copy/re-pack so the accepted bytes can be passed directly to `npm publish <same.tgz> --tag repair`. Its fake Claude CLI, planted plugin cache, stand-in owner, and `/proc` bridge are labelled fixtures: this is L3 package/oracle evidence, not proof that a real Claude process installed the plugin or woke. Direct runtime evidence remains #51 B/B2 (actual 2.1.138/2.1.217 sessions on one NixOS host), and a production host is accepted only by the installed doctor against a new live session. The post-provenance rerun caught one fixture lie before final acceptance: the container runner itself was PID 1, so the product correctly refused it as an impossible owner. C now keeps an outer PID-1 shell and runs the stand-in Claude below it; both default and exact-artifact modes assert marker owner `>1`, reached doctor PASS, and consumed byte-identical candidates (recorded in BASELINE). The earlier pre-provenance green is not reused.

### Changed

- **Release-preparation evidence:** the pre-version landing HEAD `8f566e01dc9c4510f7485d08bcdf370eb364a614` passed the exact-SHA GitHub Actions run [29899948565](https://github.com/junghan0611/entwurf/actions/runs/29899948565) with `check`, `install-surface`, and `artifact-consumer` all green. After the `0.12.8-repair.0` version change, `pnpm check` passed and `LIVE=1 ./run.sh release-gate /tmp/entwurf-release-gate-0.12.8-repair.0.LMTFbr` completed with `MUST: PASS=17 FAIL=0 SKIP=0` and advisory `BEHAVIOR: PASS=1 FAIL=0`; full log: `/tmp/entwurf-release-gate-0.12.8-repair.0.LMTFbr/release-gate.log`. The final preserved tarball, second exact-SHA CI, and artifact acceptance remain deliberately deferred to `make`.
- **Release operation is now one repo-local Agent Skill shared by Claude Code and pi, instead of two pi-only prompt files.** `.claude/skills/entwurf-release/SKILL.md` owns four explicit authority modes: `land` pushes a reviewed pre-version HEAD and requires its exact-SHA CI; `prepare` edits, gates, and commits without pushing; `make` pushes the prepared HEAD, requires the second exact-SHA CI, accepts one preserved candidate, and only then tags and creates the GitHub release; `publish` alone may send those accepted bytes to an explicitly named npm dist-tag. The sibling `verify-exact-ci.sh` oracle binds both CI checkpoints to the requested `headSha` and all three required jobs (`check`, `install-surface`, `artifact-consumer`) instead of trusting a branch badge. `.pi/settings.json` points pi at the same project skill directory, and the former `.pi/prompts/prepare-release.md` / `make-release.md` copies are removed, so the two harnesses no longer see different release hands. The shared version contract accepts ordinary SemVer prereleases such as `0.12.8-repair.0` (still no leading `v`).
- **The pi runtime pin moves 0.80.6 → 0.80.7 — a fix+minor release that carries none of 0.80.6's anchor risk.** Where 0.80.6 shrank the Anthropic catalog 24→14 and put `curatedClaudeModels()`'s `claude-opus-4-8` anchor one dropped row from a crash, 0.80.7 leaves `anthropic.models.ts` **byte-identical** — the anchor and `claude-sonnet-5` both survive untouched (source-diffed against `pi-mono v0.80.6..v0.80.7`). The `getModels` slice this repo consumes via `/compat` is unchanged; `compat.ts` also adds an `AMBIENT_AUTH_MARKER` ambient-auth path in `withEnvApiKey()`, but that behavior change never reaches the catalog/getModels surface entwurf imports, so it is irrelevant to this path. The extension loader's jiti alias map (`root` / `/compat` / `/oauth`) is byte-identical, so the `/compat` exception holds. The one breaking change — `OpenAIResponsesCompat.sendSessionIdHeader` replaced by `sessionAffinityFormat` — is referenced zero times in this repo (grep-verified), as are `supportsToolReferences` and the deferred-tool `addedToolNames`. `package-manager`'s new `--legacy-peer-deps` is on the npm uninstall path only (`packageManagerName !== "pnpm"`), so entwurf's pnpm install/uninstall is byte-identical; the dynamic-tool `wrapper.ts` change is a no-op for a static tool set (zero `getActiveTools` deltas mid-execution); `agent-session.ts` is a private `_getCompactionRequestAuth` → `_getSummarizationRequestAuth` rename (an ambient-auth branch-summary fix). `system-prompt.ts` drops the `Current date:` line for a prompt-cache win — safe here because entwurf's code and contract consume no default prompt date. devDeps / peer range (`>=0.80.7 <0.81`) / the `check-pack-install` peer pins / the five baseline docs move together under `check-dep-versions`, and the lockfile resolved with no transitive change beyond the four pi packages. `pnpm-workspace.yaml` gains four `minimumReleaseAgeExclude` entries that pnpm 11.9 records automatically for the <24h-old 0.80.7 pins.
- **The pi runtime pin moves 0.80.3 → 0.80.6, so the runtime we declare is the runtime that exists.** The global pi had already moved to 0.80.6 while the repo still pinned 0.80.3; that gap is what made the `check-pack-install` fix above matter, and closing it is the other half of the same repair. devDeps (`pi-ai` / `pi-coding-agent` / `pi-tui`), the peer range (`>=0.80.6 <0.81`), the `check-pack-install` peer-install pins, and the baseline statements in `AGENTS.md` / `README.md` / `ROADMAP.md` / `docs/setup-clean-host.md` / `demo/README.md` all move together, and `check-dep-versions` now fails if any one of them lags. The peer floor rises with the devDep on purpose: keeping `>=0.80.3` would declare support for a version no gate verifies. The lockfile resolved with no transitive change beyond the four pi packages (`pi-agent-core` is coding-agent's own dependency, not a new pin of ours).
- **What only the gates could answer, they answered.** 0.80.4 reworked `package-manager` (an `autoload:false` package delta plus a dedupe rewrite), `settings-manager`, and `resource-loader` — the exact three files our install surface stands on, and typecheck can say nothing about any of it. Under a **deliberately failing fake `pi` planted first on PATH** (stronger than merely unsetting the global one: an unqualified `pi` call exits 97 instead of silently working), `check-pack-install` drove the pinned 0.80.6 out of the install-smoke tree and kept both regressions green — the npm-managed install writing settings through a hoisted dep, and the user-scope citizen loading from a foreign cwd.
- **The Anthropic catalog SHRANK in 0.80.6, and that is a risk no type could have shown.** The registry drops ten legacy rows (`claude-3-*`, `claude-opus-4-0`, `claude-sonnet-4-0`, …), 24 model ids down to 14. `curatedClaudeModels()` calls `requireRegistryModel` on `claude-opus-4-8` and **crashes rather than fabricating a row** if the anchor is gone, so a bump that dropped it would have taken the provider surface down at extension load. Both curated rows survive with byte-identical `cost` / `contextWindow` / `maxTokens`. The only metadata added is `thinkingLevelMap` — Opus 4.8 goes `{xhigh}` → `{xhigh, max}` and Sonnet 5 gains the map outright (it had none) — and the curated rows copy neither, so the registered surface is unchanged. `ThinkingLevel` likewise gains `"max"` (a union widening this repo never consumes: it holds no exhaustive map over the type), and `cost` becomes the `ModelCost` superset with optional `tiers[]`, which passes through untouched because the curated surface copies `cost` wholesale and the provider gate asserts field presence, not an exact key set. Wiring thinking/effort remains a separate lane (#49 D), not a consequence of the bump.

## 0.12.7 — 2026-07-14

### Fixed

- **Three operator commands were dead in every installed package, and the class is now fenced in one place.** `entwurf doctor-pi-provider`, `entwurf new-session-id`, and `entwurf meta-bridge-prune` dispatch through `run.sh`, whose `REPO_DIR` sits under `node_modules` once installed — so each one executed a raw `.ts` and died on `ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`. `new-session-id` is the alias `docs/setup-clean-host.md` tells operators to run, and `doctor-pi-provider` is the pi-ownership verdict, so both shipped broken while every dev clone stayed green. This is the same fence start.sh (0.12.1), the store-doctor (0.12.4), the plugin hook (0.12.5), and the agy imprint hook already crossed by hand — the fourth recurrence, and the reason it is no longer hand-written. All 75 `.ts` entrypoints in `run.sh` now route through a single `run_ts` helper that dispatches to the prepack-emitted JS when installed and keeps transparent source execution in a dev clone; a dev-only gate, which has no compiled twin by design, is REFUSED with a legible message rather than falling back to raw `.ts` or exiting 0 as a silent no-op.
- **The install surface is now verified, not assumed.** `check-pack-install` packed a real tarball but drove only bins — never a subcommand — which is precisely why the three commands passed every gate while being dead on arrival. It now executes them from the installed bin under `node_modules` and asserts MEANING, not the absence of a crash: the session id must match `SESSION_ID_RE`, the doctor must reach its own verdict body, and prune must walk the 0-record store it was handed. A new static `check-install-surface` closes the other half: `run_ts` is the only fence crossing (S1), every operator subcommand has a compiled twin whether it calls `run_ts` directly or through a helper — the house style (S2), no npm bin points at a raw `.ts` and every `.sh` bin that execs one branches on `node_modules` (S3), and dev-only gates stay out of the tarball (S4). Each S is mutation-checked against the bug it names; review found three bypasses in the first cut (a raw-`.ts` bin, an operator command hidden behind a helper, and a smoke that aliased the live path into a variable), and all three now fail the gate.
- **The agy bridge doctor no longer reports a working host as broken.** It demanded the literal string `mcp(entwurf-bridge/entwurf_v2)` in `permissions.allow`, so a host whose operator had granted a broad `mcp(*)` was told the bridge was "registered and unusable — agy prompts on EVERY entwurf_v2 call". That was false: agy matches `mcp(*)` and `mcp(<server>)` against our tool, which the doctor already knew — it read exactly that coverage in the `deny`/`ask` direction to detect shadowing, and then refused to read it in the `allow` direction. Coverage is now read both ways. The installer still writes only the narrowest rule it needs; the doctor distinguishes a grant we own (`allow → …`) from one the operator's broader rule is carrying (a NOTE that names the covering rule and warns that narrowing it takes the grant away) from a genuinely missing one (DRIFT). Deny/ask precedence is unchanged and still fails loud, including when the same broad rule sits in both lists. Ownership beats coverage in the other direction too (review follow-up): when the permission-state records that WE added the exact rule and it has since vanished, an operator wildcard keeping calls alive does not make the doctor green — it reports both axes (our grant gone, their rule covering) and stays red; a whole-file settings relink (agent-config `ensure_link`) produces exactly this shape, and only the statusline doctor caught it before.
- **agy doctors now bind install-state to the live file this host actually reads.** A hard-verification sweep moved `HOME` to `/tmp` but inherited the operator's real `XDG_DATA_HOME`, writing seven sandbox-target state records into `~/.local/share/entwurf`; all three doctors inspected those foreign files and reported green. Bridge, permission, statusline, and hook state now fail `FOREIGN TARGET` when their normalized managed path differs from the live target, and fail `CORRUPT` when the state body is unreadable or lacks its required path. Permission state is checked independently even if bridge state is absent. Runtime and ownership evidence remain separate: a resolvable live command is still reported as present while foreign/corrupt provenance keeps the final verdict red. A relative managed path is CORRUPT too (review follow-up): install only ever records absolute paths, and normalizing a relative one against the doctor's own cwd could bless whatever directory it happens to run from. Regressions cover foreign targets, corrupt/relative state, the independent permission-state rail, and wildcard-masked owned drift (agy install/statusline/hooks: 140/69/44).

### Fixed (post-review, 2026-07-14 PM)

- **The offline floor no longer removes the operator's live pi-provider wiring while reporting green.** `smoke-user-scope-citizen` redirected `PI_CODING_AGENT_DIR` to fake settings but left `XDG_DATA_HOME` real. Its `run.sh remove-user-scope` drive therefore consumed the operator's real ownership state, followed that state's recorded `managedSettingsPath`, removed `entwurfProvider.mcpServers.entwurf-bridge` from the real `~/.pi/agent/settings.json`, and deleted the real state. This made the final bundled-MCP LIVE gate fail with `Connected MCP servers: (none registered)` after `pnpm check` had passed. Both inverse calls now pair the fake agent dir with fake XDG state, and the gate sandboxes HOME and the whole XDG trio up front, so the next root run.sh reaches for is already fenced. A before/after byte comparison proves the smoke leaves the live settings, the real `$XDG_DATA_HOME/entwurf` tree, and the real imprint log unchanged. Review then found the first S5c too narrow to hold the class it was written for: it fired only on the **inline-env** form, so hoisting the same override into an `export` one line up walked the identical leak past a green gate (mutation-proven), and its command list blessed `install`/`setup` drives that sandbox `PI_CODING_AGENT_DIR` — which those commands ignore, since `ensure_agent_dir_symlinks` hard-codes `$HOME/.pi/agent` and would still relink the operator's real agent dir. S5c now matches the **drive** (in any env form, and never in prose or an assertion string) and then demands the isolation that command actually needs at each root it writes. Cross-review closed one more ordering hole in that rewrite: a sandbox `export XDG_DATA_HOME` counts as isolation only for drives that come **after** it, so a trailing export can no longer retroactively bless a mutation that already ran against the live state (mutation-checked).
- **`check-pack-install` no longer leaks into the operator's real XDG roots — and proves it on every return path.** The gate swapped `HOME` per drive but inherited the operator's exported XDG roots, so its `run.sh install` drive wrote a **foreign pi-provider install-state into the real `~/.local/share/entwurf`** and the agy-imprint drive appended fake birth lines to the real `~/.local/state/entwurf/agy-imprint.log` — the same class as the 2026-07-13 hard-verify pollution, one layer deeper: inside `run.sh` itself, where S5/S5b (which scan only `scripts/*.sh`) cannot see. Every sandbox drive now exports `XDG_DATA_HOME`/`XDG_STATE_HOME`/`XDG_CACHE_HOME` alongside `HOME`. Review found the first self-fence was itself too narrow: it ran only on the success tail and fenced DATA while the known leak also touched STATE. The final **outer self-fence** runs after every success or early-failure path, requires the operator's real install-state tree to stay byte-identical, and requires the gate-specific fake agy marker count in the real imprint log not to increase. Dropping a drive's XDG swap is mutation-checked. A separate live audit also disproved the initial “all wiring intact” claim: Claude's XDG marketplace artifact was absent, producing `cache-miss`, no SessionStart records after 08:46, and an honest `🪛 ? cc`; this was a real meta-bridge disconnect, not agy's documented pre-first-turn `?`. Reinstalling the live meta-bridge restored `source=assembled=installed` parity and a fresh Claude probe automatically birthed garden id `20260714T121134-5effc4` (record count 116→117).

### Changed

- **Backend drift pins moved, each with an explicit verdict.** agy `1.0 → 1.1` after live re-verification on the new minor (2026-07-14, agy 1.1.0: `entwurf_self` without a permission prompt, bidirectional native-push reply on the same gid, `LIVE=1 smoke-agy-native-push-live` 13/13 — evidence in `DELIVERY.md` §Antigravity). codex `0.136 → 0.144` as an **observed bump, not a re-verification**: codex is not a shipped native-citizen lane in 0.12.x, so the probe evidence stays dated at 0.136.0 and `DELIVERY.md` §Codex now carries the explicit non-reverification verdict; re-run the raw probes before building any codex adapter.
- **CI now runs the install surface, not just the source tree.** `pnpm check` is a dev-clone floor by construction: every fence bug this repo has shipped was green on it. `check-pack-install` was release-gate-only, so the installed axis had never been in CI at all. It is now its own job (~1 minute), which is what turns "we fixed it" into "it cannot come back".
- **Verification may not rewire the operator's own installation.** `check-install-surface` S5 flags an offline smoke that writes a live `~/.claude` / `~/.gemini` / `~/.pi` path before swapping the process HOME to a sandbox — or without swapping at all — including one hop of variable aliasing. The current tree is clean (the install smokes all `export HOME` to a sandbox first, and `smoke-resident-garden-guard`'s `rm -rf` targets a `mktemp -d`), so this pins the existing contract rather than fixing a live break. **It is a static tripwire, not a sandbox proof:** it reads shell source, so a path assembled across several variables or built inside an embedded heredoc would slip past it. The real guarantee — running the whole offline floor under a swapped HOME — is recorded in `NEXT.md` as open, not claimed here. S5b (review follow-up) pins the axis the 2026-07-14 pollution actually used: any offline smoke that swaps HOME into a sandbox must swap `XDG_DATA_HOME` with it, because HOME alone still writes real install-state below the inherited XDG root.

- **Install/package hygiene guards now seal three post-0.12.6 edges.** Package tarballs exclude Python bytecode residue even though `scripts/` ships as a whole, pack gates serialize the full `npm pack` dist-read window and use per-run tarball destinations, and the user-scope pi package inverse is exposed as explicit `remove-user-scope` with a read-only `--remove --dry-run` preview.

## 0.12.6 — 2026-07-03

### Fixed

- **Claude Code meta-bridge live marketplace sources now live outside the checkout for dev and npm installs alike.** Development clones and installed packages both assemble the plugin bundle under `$XDG_DATA_HOME/entwurf/meta-bridge/.assembled`; the checkout or `node_modules` tree is now only the source origin. This removes the class where `pnpm check`, `git clean -xfd`, or a repo-local uninstall smoke could delete a user-scope Claude marketplace source and leave new Claude Code sessions at statusline `?`. The installer still chooses `.ts` vs compiled `.js` hook artifacts by source origin, but the live registration path is the same XDG artifact lane.
- **Meta-bridge uninstall now uses the recorded live-artifact path and fails before side effects when the state is corrupt.** The install state's `assembledMarketplacePath` is the SSOT for uninstall, doctor, and state checks. Uninstall validates the full `…/entwurf/meta-bridge/.assembled` suffix before removing Claude plugin/MCP registrations or deleting state, so malformed paths such as `/` or `…/entwurf/meta-bridge/not-assembled` fail loud with zero Claude side effects and leave state/artifacts intact. `state.py check` also rejects missing, empty, or malformed recorded paths even when settings agree with the corruption.
- **User-scope pi package registration is now part of setup.** `./run.sh setup` registers `entwurf` in user-scope pi settings so `--entwurf-control` and the provider surface load from foreign cwd sessions, not only from a project-local `.pi/settings.json`. A hermetic `smoke-user-scope-citizen` covers idempotency, stale normalization, remove symmetry, unrelated-key preservation, and corrupt-shape fail-loud behavior.

### Changed

- **The install toolchain is now aligned to one pnpm 11 lane and one setup surface.** The repo dropped the obsolete `packageManager` pin and `.npmrc`, moved pnpm policy to `pnpm-workspace.yaml`, updated CI to pnpm 11.9, and treats `./run.sh setup` as the single local install path instead of a split `pi install` flow.
- **The next delivery lane is pinned before implementation.** `NEXT.md` now records the agy/Antigravity delivery adapter constraints: direct-inject/native-push is separate from pi's control-socket liveness domain, registration is explicit, receiver markers are not reused for native-push replyability, and install/doctor/uninstall must inherit the source-origin/live-artifact boundary proven by this release.
- **The future fresh-spawn lane stays mux-visible by default.** The mux driver plan now keeps minting and mux transport separate, treats tmux/zmx as drivers behind a leaf interface, and keeps fresh pi-native GPT launch visible instead of reviving hidden background one-shots as the default.

### Verification

- `pnpm check` passed on 2026-07-03 after the XDG live-artifact move, recorded-path uninstall hardening, user-scope citizen smoke, pnpm 11 setup cleanup, and NEXT lane updates.
- `./run.sh smoke-meta-install-state` passed with the new direct install→XDG proof, recorded-path mismatch case, corrupt basename/missing-field fail-loud cases, and checkout-internal `.assembled` boundary fingerprint.
- `./run.sh doctor-meta-bridge` passed on 2026-07-03 with source/assembled/installed writer parity all v2 and the assembled bundle under `$XDG_DATA_HOME/entwurf/meta-bridge/.assembled`.
- `./run.sh check-pack-install` passed on 2026-07-03, proving the npm consumer path keeps the stable XDG marketplace source and user-scope pi citizen registration.
- `LIVE=1 ./run.sh release-gate /tmp/psa-release-gate-0.12.6.ddCcmz` passed on 2026-07-03; log `/tmp/pi-tmux-entwurf-release-gate-0126.log`; summary `MUST: PASS=17 FAIL=0 SKIP=0`, advisory `BEHAVIOR: PASS=0 FAIL=1` (`smoke-resident-garden-guard` positive `/gnew T3` model-in-loop identity turn; non-blocking).

## 0.12.5 — 2026-07-01

### Fixed

- **The plugin hook now runs as compiled JS when installed — the strip-types class is closed for good.** The SessionStart/UserPromptSubmit hook ran as a raw `meta-bridge-hook.ts`. When the marketplace source sits below `node_modules` (a global npm/pnpm install), Claude executes that `.ts` directly and Node refuses strip-types there (`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`), so every session failed. The hook was the last `.ts`-at-runtime surface; `build-bridge` now emits `dist/pi-extensions/meta-bridge-hook.js` and the installer copies that compiled closure (dev clones still run the `.ts` for transparent editing), mirroring the same installed-vs-dev split `start.sh` (0.12.1) and the store-doctor (0.12.4) already use. `check-pack-install` now runs the installed compiled hook **from under `node_modules` with plain `node`** and proves a raw `.ts` at the same location is refused — the exact fence that broke real hosts is a green regression. The doctor's writer-version parity compares `meta-session.<js|ts>` by install mode so a compiled bundle no longer false-STALEs against the `.ts` source.
- **Installed meta-bridge paths are now stable across package upgrades.** The installed statusline uses a new `entwurf-statusline` bin shim (matching the existing `entwurf-bridge` MCP shim), and installed meta-bridge marketplace assemblies move out of versioned pnpm store paths into a version-stable operator data directory. Package upgrades still require `entwurf install-meta-bridge` to refresh the Claude plugin bundle/cache, but old-store dead links no longer strand `statusLine` or marketplace source paths. The doctor now also executes the cached SessionStart hook once in an isolated temp agent dir, catching stale plugin-cache / hook-syntax failures before the next real Claude Code session.

### Verification

- Oracle and local review both reproduced the installed hook fence: compiled `meta-bridge-hook.js` runs from under `node_modules` with plain `node`, while the raw `.ts` at the same location fails specifically with `ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`.
- `./run.sh check-pack` and `./run.sh check-pack-install` passed on 2026-07-01 with the hook-JS tarball requirements, baked `hooks.json` `.js` assertion, and raw-`.ts` fence reproduction.
- `pnpm check` passed on 2026-07-01 after the hook-JS + stable installed-path changes.
- `./run.sh install-meta-bridge && ./run.sh doctor-meta-bridge` passed from the development clone after re-materializing the gitignored `.assembled` bundle.

## 0.12.4 — 2026-07-01

### Fixed

- **Installed `doctor-meta-bridge` no longer false-fails on node_modules strip-types.** The doctor previously ran `scripts/meta-bridge-store-doctor.ts` and `scripts/check-entwurf-v2-surface.ts` through Node strip-types even from an npm/pnpm-installed package. Node refuses type stripping under `node_modules` (`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`), so real floor hosts reported false store-scan / v2-surface failures while development clones stayed green. The doctor now branches by package location: installed packages run the prebuilt `mcp/entwurf-bridge/dist/scripts/meta-bridge-store-doctor.js` with plain `node` and defer the repo-only v2 source-shape gate after confirming the shipped source and runtime wiring; development clones keep the raw `.ts` gates.
- **The store-doctor helper now ships as a node_modules-safe dist artifact.** The bridge build emits `dist/scripts/meta-bridge-store-doctor.js` alongside the MCP bridge closure, reusing the already-shipped `meta-session.js` dependency without adding a new runtime package lane. `check-pack` / `check-pack-install` require the artifact in the tarball and prove it scans a real fixture store under `node_modules` with plain `node`.
- **Clean-host install docs call out the 0.12.4 doctor floor check.** The walkthrough now tells operators exactly which doctor lines prove the installed-vs-dev split and flags any `ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING` as a pre-0.12.4 or broken-tarball signal.

### Verification

- `pnpm check` passed on 2026-07-01 after the doctor/install-floor fix.
- `./run.sh check-pack-install` passed with the new installed store-doctor scan and doctor-dispatch lock assertions.
- Release-gate prep evidence: `LIVE=1 ./run.sh release-gate /tmp/psa-release-gate-0.12.4.PliLsd` passed on 2026-07-01; log `/tmp/pi-tmux-entwurf-release-gate-0124.log`; summary `MUST: PASS=17 FAIL=0 SKIP=0`, advisory `BEHAVIOR: PASS=0 FAIL=1` (`smoke-resident-garden-guard` post-`/gnew` autonomous `entwurf_self` identity turn; non-blocking).
- `target Linux host` real floor host reproduced the pre-fix strip-types failure from an installed package and passed after installing the patched tarball: compiled store-doctor scanned `1 record(s)` with plain `node`, and installed `doctor-meta-bridge` reported store-scan ok plus v2-surface deferred.

## 0.12.3 — 2026-07-01

### Changed

- **Claude ACP dependency lane refreshed for Sonnet 5.** The ACP runtime pins now use `@agentclientprotocol/claude-agent-acp@0.54.1` with `@agentclientprotocol/sdk@1.1.0`, while keeping the direct `@anthropic-ai/sdk@0.100.1` peer-resolution pin. The pi adapter floor is now `@earendil-works/pi-* >=0.80.3 <0.81`, matching the runtime catalog that exposes `claude-sonnet-5`.
- **Curated Claude surface moves from Sonnet 4.6 to Sonnet 5.** `claude-sonnet-5` replaces `claude-sonnet-4-6` across the ACP provider, demo/default smoke targets, pi target registry, and release docs. The Sonnet-specific 200K cap was removed; Sonnet 5 now surfaces the verified 1M context window like the Opus anchor, with a 1M ceiling guard to prevent silent future inflation.
- **Release and backend docs are version-neutral where the repo shape is stable.** The README now describes the durable repository shape instead of a point-in-time `0.12.x` state, and the clean-host/demo/verification docs reflect the current pi floor and Sonnet 5 defaults.
- **Cortex and fresh-spawn planning docs realigned to the 0.12 substrate.** The ACP backend rail documentation and NEXT/ROADMAP planning notes now describe the as-built adapter seam and the mux-visible fresh-sibling lane without re-centering old v1/fat-bridge assumptions.

### Fixed

- **Live ACP smoke timeout cleanup no longer leaves stale timers after PASS.** Raw-turn, overlay, memory-containment, and session-reuse live smokes now clear their timeout handles when the awaited operation wins, so a successful live check exits promptly instead of lingering until the old timeout expires.
- **Session-reuse live smoke now preserves its success evidence.** The two-turn reuse smoke no longer calls `process.exit(0)` on success, allowing the turn-2/PASS log and cleanup to drain naturally while the retained ACP child is still handled by the backend exit cleanup.
- **Claude Code meta-bridge install state also disables workflow surfaces.** `enableWorkflows` and `workflowKeywordTriggerEnabled` are now managed false alongside the existing auto-memory, compaction, prompt-suggestion, progress, and auto-mode settings.
- **Unsupported ACP Codex targets are not advertised.** The target registry keeps Codex on the native `openai-codex` provider only; `entwurf/gpt-5.4` and `entwurf/gpt-5.5` are removed until an ACP Codex backend exists.

### Verification

- `pnpm check` passed on 2026-07-01 after the dependency/model/doc updates; prep log `/tmp/pi-tmux-entwurf-prep-check-0123.log` ended with `EXIT=0`.
- `LIVE=1 ./run.sh smoke-acp-raw-turn-live` passed with `claude-sonnet-5` and exited promptly after PASS.
- `LIVE=1 ./run.sh smoke-acp-provider-live` passed with `claude-sonnet-5` through the pi provider path.
- `LIVE=1 ./run.sh smoke-acp-session-reuse-live` passed with a two-turn reused ACP child; turn 2 recalled the turn-1 codeword from delta-only prompt scope.
- `LIVE=1 ./run.sh release-gate /tmp/psa-release-gate-0.12.3.ZcRc8w` passed on 2026-07-01 with `MUST: PASS=17 FAIL=0 SKIP=0` and `BEHAVIOR: PASS=1 FAIL=0`; log `/tmp/pi-tmux-entwurf-release-gate-0123.log`.

## 0.12.2 — 2026-06-29

### Fixed

- **Claude Code meta-bridge installs on the supported 2.1.x floor.** Claude's plugin validator is a closed schema whose accepted marketplace keys differ by patch level; 0.12.1's root-level `marketplace.json` `description` passed on Claude 2.1.195 but failed on the floor host's 2.1.97 with `Unrecognized key: "description"`. The marketplace manifest now keeps only the minimal root keyset confirmed on the floor (`name`, `owner`, `plugins`), leaving explanatory text in installer/docs comments rather than in closed-schema JSON.
- **Installed meta-bridge MCP wiring no longer bakes pnpm store paths.** On npm/pnpm-installed hosts, the user-scope Claude MCP entry now points at the stable `entwurf-bridge` bin instead of `$REPO/mcp/entwurf-bridge/start.sh`, whose `$REPO` can be a `.pnpm/@junghanacs+entwurf@.../node_modules/...` hash path that goes stale on version or peer changes. Development clones still pin to that clone's `start.sh`; both branches preserve the external Claude sender env (`ENTWURF_BRIDGE_EXTERNAL_AGENT_ID=external-mcp/claude-code`, `ENTWURF_BRIDGE_REQUIRE_META_SENDER=1`).

### Added

- **`check-meta-manifest-schema` — a CLI-version-independent meta-bridge manifest guard.** The new deterministic gate pins the Claude marketplace/plugin/hooks manifests to the minimal keysets used by the meta-bridge, including the load-bearing hook event names (`SessionStart`, `CwdChanged`, `UserPromptSubmit`, `FileChanged`) and hook command keys. It also asserts `meta-bridge-state.py::desired_mcp()` chooses the installed-vs-clone MCP wiring without invoking a real Claude CLI. The gate is wired into `pnpm check` so future decorative closed-schema keys fail before release.

### Verification

- `pnpm check` passes with the new `check-meta-manifest-schema` static guard included.
- `./run.sh smoke-meta-install-state` passes, proving the state manager/doctor consumers still follow `desired_mcp()` without drift.
- Installed-location regression probe passes: running `scripts/check-meta-manifest-schema.py` from a synthetic `node_modules/@junghanacs/entwurf` package no longer self-fails.
- Claude Code 2.1.97 floor validation passed on `target Linux host` after removing the root marketplace `description`; current Claude 2.1.195 validation also passes with warnings only.
- `LIVE=1 ./run.sh release-gate /tmp/psa-release-gate-0.12.2.NLGhet` passed on 2026-06-29 with `MUST: PASS=17 FAIL=0 SKIP=0` and `BEHAVIOR: PASS=1 FAIL=0`; log `/tmp/entwurf-release-gate-0.12.2-20260629T205339.log`.

## 0.12.1 — 2026-06-29

### Fixed

- **Installed MCP bridge boots from npm/node_modules.** The 0.12.0 launcher ran `src/index.ts` through Node strip-types, but Node refuses type stripping below `node_modules` (`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`). The npm tarball now carries a clean tsc-emitted bridge JS closure under `mcp/entwurf-bridge/dist/`, and `start.sh` runs that dist path when installed while keeping the strip-types source path for development clones.
- **Stale dist files cannot ship.** `build-bridge` removes `mcp/entwurf-bridge/dist` before emit, and `check-pack-install` plants a stale sentinel before `npm pack` to prove prepack cleaned the tree. This closes the orphan-emit tarball contamination found during the 0.12.1 C review.
- **npm bin symlink installs resolve the package root.** `run.sh`, `start.sh`, and the bridge protocol smoke now resolve symlinks before computing their root, so `node_modules/.bin/entwurf` and `node_modules/.bin/entwurf-bridge` work like direct package paths.
- **Two live ACP MUST smokes no longer flake on model-in-loop phrasing.** `smoke-acp-carrier-augment-live` proved augment delivery by asking the model to echo a `SECRET_PROJECT_CODE` planted in a `/tmp` `AGENTS.md` — current Claude correctly refuses that as a prompt-injection/exfil pattern, so the MUST gate failed even though the augment rode the wire and the empty carrier billed clean. It now uses a benign factual marker (an internal build codename) asked back as a normal "answer from project context" task. `smoke-acp-bundled-mcp-live` asked the model for "values only, one per line" yet asserted on field-name-labeled lines (`socketState: alive`), so a compliant bare-value reply was dropped by the envelope filter while the `[tool:done]` notice truncated `socketState`; it now requests labeled lines so the three identity fields are deterministically observable. Neither change weakens the gate (same MUST assertions, same non-circular gid proof) — both only realign the observation contract with current model behavior.

### Changed

- **Install docs are npm-first and pi-adapter-second.** The README and clean-host walkthrough now lead with neutral `npm install @junghanacs/entwurf`, document the `entwurf` / `entwurf-bridge` bins, and move pi to the optional ACP-provider/control-socket adapter lane (`@earendil-works/pi-coding-agent >=0.80.2 <0.81`). `pi install npm:...` is no longer the public primary install recipe.
- **Pi peers are optional for the neutral package.** The `@earendil-works/*` peer trio and `typebox` are marked optional so a plain npm install can boot the MCP bridge without pulling the pi adapter stack. The pi loader lane is still verified separately with explicit pi peers.
- **Garden id concept is documented up front.** The concept primer now defines garden/garden id as the shared address space for independent harness citizens, not a worker name or proof of pi ownership, and points callers to `entwurf_peers` + `entwurf_v2` instead of hand-picking transports.

### Verification

- `./run.sh check-pack-install` passes with the neutral npm install regression: package bins present, optional pi peers absent, installed dist bridge answers `tools/list`, and pi-loader registration still passes on the explicit pi-peer lane.
- Remote `target Linux host` real-install probe from the packed tarball passed: local npm install, package bins, optional pi peers absent, installed `entwurf-bridge` `tools/list`, `entwurf install` with isolated HOME, and `entwurf check-bridge`. The host's real HOME also exposed a pre-existing stale `~/.pi/agent/entwurf-targets.json` symlink to `pi-shell-acp`; fix with `entwurf setup:links --force` or an explicit `ENTWURF_TARGETS_PATH` if that old registry is intentional.
- `LIVE=1 ./run.sh release-gate /tmp/psa-release-gate-0.12.1.GUFDUb` tiers `MUST: PASS=17 FAIL=0 SKIP=0` with `BEHAVIOR: PASS=1 FAIL=0` on 2026-06-29; log `/tmp/entwurf-release-gate-0.12.1-20260629T191543.log` (the two live-smoke observation fixes above were what moved the gate from `MUST FAIL=1` to green; the install change is harness-neutral and touches no ACP code path).

## 0.12.0 — 2026-06-29

> This release hard-cuts the project from `pi-shell-acp` to **`entwurf`**. It is not a compatibility rename: the package/provider/model/MCP identity is now `entwurf`, v1 entwurf verbs are gone, and `entwurf_v2` is the canonical garden-id dispatch verb. The repo is **entwurf-core (v2 dispatch) + meta-bridge + pi adapter + ACP plugin**. Pi remains an important adapter and ACP host, but the project subject is the garden-citizen dispatch substrate. Verified release floor: `pnpm check`, `check-pack`, `check-pack-install`, and `LIVE=1 ./run.sh release-gate <scratch>` MUST tier `PASS=17 FAIL=0 SKIP=0` on 2026-06-29, with BEHAVIOR (advisory model-in-loop autonomous MCP tool-selection) `PASS=1 FAIL=0` and recorded separately from the cut decision.

### Added

- **`entwurf` package/provider identity.** Package metadata, provider id, model prefix, MCP server name, repo URL, env namespace, install surface, and package-source resolver now use `entwurf` / `@junghanacs/entwurf` / `entwurf-bridge`. Runtime aliases and legacy provider-id accept are intentionally absent.
- **0.12.0 install surface.** `./run.sh setup .` is the one-command local setup path: `pnpm install` → project install → Claude Code meta-bridge install when available → v2 smoke. `run.sh install` now preflights broken/missing `node_modules` and fails loud before writing settings. `check-install-preflight` locks the relocation/reinstall gap found after the repo move.
- **Published-package smoke.** `check-pack` and `check-pack-install` pack the release tarball, install it into a fresh temp project with pi 0.80.x peers, and prove the pi loader registers the `entwurf` provider and curated Claude model anchors.
- **ACP plugin on the v2 core.** Provider registration via `pi-extensions/acp-provider.ts` plus `pi-extensions/lib/acp/*`, curated Claude models (`claude-sonnet-4-6`, `claude-opus-4-8`), no-auth sentinel, explicit config overlay, tool-surface preflight, ACP→pi event mapping, session reuse, first-user augment, and display-only lifecycle notices.
- **Meta-bridge install/state cutover.** Claude Code meta-bridge install state, MCP entry, statusline, permissions, and sender/receiver markers now use the `entwurf` naming surface; stale `pi-tools-bridge` MCP entries are pruned as one-shot cutover state, not accepted as a runtime alias.

### Changed

- **Project framing is entwurf-first.** README / ROADMAP / DELIVERY / BASELINE / VERIFY were reframed around garden ids, shipped vs verified-probe harness lanes, thin bridge boundaries, tool narrowing, and the ACP plugin as one ingress rather than the boundary.
- **ACP is a plugin, not a second harness.** The host `--entwurf-control` pi session supplies socket citizenship; the ACP plugin owns backend process lifecycle, overlay, per-backend dialect, and turn evidence only. No auth proxy, no subscription bypass, no transcript hydration, no ambient MCP scan.
- **Dependencies bumped and fenced.** pi dev/runtime floor is now **0.80.2** (`>=0.80.2 <0.81`), with `getModels` reached through the loader-compatible `/compat` entrypoint. Claude ACP moved to `@agentclientprotocol/claude-agent-acp@0.50.0` and `@agentclientprotocol/sdk@0.29.0`; model forcing uses `session/set_config_option(configId="model")`. The deprecated `ClientSideConnection` path was replaced by the fluent `client().connect(stream)` adapter with explicit teardown close.
- **Release gate remains two-tier.** MUST owns the cut decision and now includes v2-native live gates plus ACP plugin live smokes (socket-citizen, raw-turn, overlay, provider, reuse, carrier augment, memory containment, RGG, operator MCP, skill, bundled bridge). BEHAVIOR is advisory model-in-loop autonomous tool-selection and never blocks the cut.
- **Install docs are npm-first.** README and the clean-host walk-through lead with `pi install npm:@junghanacs/entwurf` (resolving to `~/.pi/agent/npm/node_modules/@junghanacs/entwurf`, the path `check-package-source-routing` pins); the `git:` source path and a local clone are documented as alternatives for tracking `main` or hacking on the bridge.
- **Release hero refreshed for the entwurf identity.** The README hero and pi package gallery image now use a GLGMAN Universe `entwurf` release-day illustration (four sibling schools, shared forged driver) instead of the old demo GIF as the public first impression.
- **Verification docs simplified to the 0.12 surface.** `VERIFY.md` was reduced from 621 to 260 lines and `BASELINE.md` from 284 to 227 lines by deleting broken/dead v1 procedures, moving historical rows back to CHANGELOG/git, and keeping the load-bearing 0.12 evidence axes: install paths, identity interview, carrier separation, backend MCP identifiers, tuple formula, JSONL memory axis, and pass criteria.
- **v1 residue swept from runnable comments and stale ledgers.** Retired `entwurf_send` / `entwurf_resume` references in current-source comments and the absorbed `NEXT--acp-on-v2.md` branch ledger were removed or rewritten to the v2 surface; historical CHANGELOG rows remain historical evidence, not current recipes.

### Removed

- **v1 entwurf entrypoints.** MCP tools `entwurf` / `entwurf_resume` / `entwurf_send`, pi-native `entwurf_send`, `spawn_async_resume`, and `/entwurf*` commands are removed. Current surface: `entwurf_v2`, `entwurf_peers`, `entwurf_self`, `entwurf_inbox_read`, plus `/entwurf-sessions` and `/gnew` on the pi adapter.
- **Legacy `pi-shell-acp` runtime identity.** No permanent package/provider alias, no legacy provider accept, no dual-read of old runtime state. Old install/cache state is a one-shot operator cutover only.
- **OpenClaw install surface.** The old plugin/importer path remains historical only; it is not a live consumer.
- **Phantom compaction surface.** Documentation no longer claims bridge-owned compaction knobs or a compaction smoke surface; backend-native compaction remains backend-owned.

### Fixed

- **Mailbox reply instructions point at the canonical v2 surface.** Replyable meta-session bodies now tell agents to use `entwurf_v2`, not the retired `entwurf_send` tool.
- **Branch-lane handoff pointers no longer dangle.** `AGENTS.md` now points at the main-lane `NEXT.md` rather than a deleted branch ledger.
- **npm-managed installs resolve hoisted runtime dependencies before writing settings.** `run.sh install` walks Node's module-resolution paths, so `pi install npm:@junghanacs/entwurf` works from `~/.pi/agent/npm/node_modules` with no package-local `node_modules`; the `@earendil-works/pi-*` peer trio is treated as loader-provided. `check-pack-install` locks the layout with a real npm-managed `run.sh install` regression under an isolated HOME.

### Deferred

- **npm publish / old package deprecation** — maintainer-owned final step after the release cut. `package.json` is already `@junghanacs/entwurf` with `publishConfig.access: public`; registry publication is intentionally last.
- **Demo / GIF retake** — the recorded demo scripts and archived GIF still describe the retired v1 `entwurf` / `entwurf_resume` / `entwurf_send` flow, so they ship as pre-0.12 evidence; a v2-native demo retake is a post-0.12 minor follow-up.
- **Fresh sibling minting** — v2 dispatch targets already-identified citizens only. Creating a brand-new sibling from nothing is a later `spawn-fresh` lane.
- **Persisted resume/load** — current ACP reuse is in-memory plus record write; persisted read/use stays off.
- **Non-Claude ACP backends / Cortex lane** — next backend work should first define the backend-addition rail and verification contract.
- **Codex / Antigravity shipped adapter lanes** — delivery probes are verified, but 0.12.0 ships them as documented evidence, not managed install surfaces.
- **Bundled-MCP deterministic split** — `smoke-acp-bundled-mcp-live` still exercises a model-in-loop `entwurf_self` call inside the MUST floor; it passed on the current cut, but the deterministic surface proof vs autonomous echo split remains a follow-up before hardening the taxonomy.

## 0.11.0 — 2026-06-16

> **0.11.0.** The entwurf v2 dispatch substrate (#35): a single additive verb, `entwurf_v2` / `runEntwurfV2`, that unifies *dispatch to existing garden citizens* behind one decider which reads peer liveness as a fact and picks transport from a frozen table keyed on **target state AND intent** (not state alone): live pi + fire-and-forget → control-socket send, dormant pi + owned-outcome → spawn-bg resume, active self-fetch + fire-and-forget → meta-mailbox enqueue; every other state×intent pair (live+owned, dormant+fire-and-forget, self-fetch+owned) is an honest reject. It does **not** mint new siblings — fresh sibling creation stays the v1 `entwurf` verb (0.12 cutover lane); the `spawn-bg resume` row resumes an already-identified dormant citizen, it does not create one. Built bottom-up as pi-only TypeScript substrate (Stage 0): contract freeze → per-gid dispatch lock → pure decider → release-policy reducer → send/spawn hands → production deps assembly → pi-native + MCP `entwurf_v2` tool. On top of it the **spawn-bg resident lifecycle** — the headline guarantee of #35 — was proven LIVE for the first time (a real `pi --entwurf-control` child stands its socket up, resumes a dormant Entwurf session, and does a model turn), and that first LIVE run surfaced and closed a production contradiction in the resident-name guard. Finally a **v2-only mode** (`PI_SHELL_ACP_V2_ONLY=1`) hard-refuses every v1 entrypoint so v1 can be turned off ahead of its 0.12 removal. Scope is Stage 0 (pi-only substrate); Stage 1 (Claude↔Claude live) is explicitly out of scope. **Release-gate restructured before the cut (2026-06-16): the pi floor was bumped to `>=0.79.4` (runtime parity) and the live gate was split into a two-tier MUST (release-blocking, owns the exit code) + BEHAVIOR (advisory, model-in-loop autonomous MCP tool-selection) summary. The prior flat `LIVE=1 → PASS=18` run (log `…20260615T152058`) predates BOTH changes and no longer describes the current tree. Fresh `LIVE=1 release-gate` on the 0.79.4 + two-tier tree (2026-06-16, log `…20260616T141023`): **`MUST PASS=17 FAIL=0 SKIP=0` (necessary condition met) + `BEHAVIOR PASS=1 FAIL=1`** — the lone BEHAVIOR-FAIL is `sentinel` (cell4/5 `S7` Bash-bypass, advisory/non-blocking); resident-garden-guard positives flipped FAIL→PASS vs the earlier run with zero code change, confirming the advisory scoping. "green" applies to the MUST tier only.**

### Added (0.11.0 entwurf v2 — unified dispatch verb)

- **`entwurf_v2` / `runEntwurfV2` — one additive dispatch verb over three transports.** The decider reads a peer's liveness as a fact (the `entwurf_peers` fact surface) and chooses transport from a frozen table keyed on **state AND intent**: alive pi + fire-and-forget → control-socket send, dormant pi + owned-outcome → spawn-bg resume, **active/deliverable** self-fetch + fire-and-forget → meta-mailbox enqueue; the complementary pairs (live + owned, dormant + fire-and-forget, self-fetch + owned, inactive self-fetch + fire-and-forget) are honest rejects, not silent fallbacks. Built as pure substrate first — the contract freeze, a per-gid lockfile primitive (F2), the pure decider, the release-policy reducer, the control-send + dead-control-send hands, the enqueue-only mailbox send body, the pure execute-router and the top-level decide→execute join — then surfaced as both a pi-native tool and an in-process MCP verb, plus `doctor` surface sanity and the `PI_ENTWURF_PREFIX_ROOTS` operator-policy SSOT. Each slice landed behind its own deterministic gate.
- **v2 dispatch reachability + lock SSOT and a 3-cell LIVE matrix sentinel.** `check-entwurf-v2-matrix` is the reachability + lock-policy table; `smoke-entwurf-v2-matrix-live` is a 3-cell LIVE sentinel (control / mailbox / guard) wired into `release-gate` after the bridge check with an honest `LIVE!=1` skip.

### Added (0.11.0 entwurf v2 — spawn-bg resident lifecycle, #35 headline)

- **`smoke-entwurf-v2-spawn-resume-live` — the full spawn-bg resident loop, proven LIVE (22 checks).** A real saved Entwurf session is resumed by a detached `pi --entwurf-control` child that stands its control socket up, does a model turn (nonce echoed in both the user and assistant turns of the session JSONL), releases its dispatch lock exactly once, and cleans up with zero litter. This is the first time the production spawn path (a detached `spawn()` pi resident — not the v1 tmux smoke fixture) was exercised end to end, closing the acceptance debt step 5c-3c had deferred to "the matrix proves it."
- **`PI_SHELL_ACP_V2_RESUME_RESIDENT_SESSION_ID` — sessionId-bound authorized Entwurf-child resident.** The first LIVE run surfaced a production contradiction: a v2 spawn-bg resume launches its child with `--entwurf-control`, but `maybeSetResidentName` refused any `entwurf`-tagged resident (the tag is the `entwurf_resume` marker), so the resume self-terminated before doing any work. Resolved by narrowing the invariant, not dropping it: operator residents still reject the `entwurf` tag, but a v2 spawn-bg resume child is authorized by the sessionId-bound marker its launcher plants, keeps its tag, and stays re-resumable. The marker is a zero-import leaf so it is root-safe from both the `.js`-import (`entwurf-control`) and `.ts`-import (`entwurf-v2-spawn-production`) compilation worlds.

### Added (0.11.0 entwurf v2 — v2-only mode)

- **`PI_SHELL_ACP_V2_ONLY=1` — hard-refuse every v1 entwurf entrypoint ahead of v1 removal.** A zero-import leaf helper (`entwurf-v2-only.ts`: `isV2OnlyMode` true only for exact `"1"`, `checkV1EntwurfAllowed` pure return, `assertV1EntwurfAllowed` throw wrapper) is the single source of truth; when `PI_SHELL_ACP_V2_ONLY=1`, each of the 10 v1 entrypoints (9 surface groups — `/entwurf` tool + command count as two) refuses before any side effect through its own existing hard-refusal channel (tool throw, command notify, isError result, RPC `respond(false)`, startup error report, MCP `textErr`). The MCP `entwurf_resume` handler and the control RPC `spawn_async_resume` are **both** guarded so the socket path cannot bypass the MCP guard. v1 code is neither deleted nor unregistered — invocation refusal only; the 11-scenario v2 replacement and v1 removal are the 0.12 lane. `check-entwurf-v2-only` (28 checks) proves the helper contract, all 10 guard sites, the double guard, and that the `entwurf_v2` core stays flag-clean.

### Added (0.11.0 entwurf v2 — fact surface)

- **`listEntwurfFacts` / `entwurf_peers` — the entwurf fact surface (4-value liveness).** A pure `PeerFact` core (garden citizens from meta-records + record-less control sockets, each with alive / dead / indeterminate / unsupported liveness) assembled bottom-up with socket-axis hardening (symlink / dir-read / malformed diagnostics). It reports facts, never routing verbs — the dispatch decision is computed later by the v2 contract, not here.

### Added (0.11.0 meta — delivery authority on v2 identity + trust)

- **Meta delivery authority cut to v2 identity + state store (3D-2 … 3D-4).** A v2 identity-normalization gate, a dual-read identity seam with delivery-agnostic consumers, the live mailbox receipt dual-write to the state store, and backend capability sourced from the registry rather than a const. The `entwurf_v2` contract surface was frozen and gated before the verb was wired (step 4-pre).
- **`project_trust` handler + inherited-trust preflight (Trust 2층).** The pi trust preflight carries inherited-trust evidence and a deny formatter (F5a/N3b); a `project_trust` handler adds an inherited-distrust escape.

### Added (0.11.0 entwurf v2 — SE active-receiver deliverability)

- **The SE-1/SE-2 deliverability seam — honest pi-native + meta-self replyability.** A meta-receiver presence marker, MCP + pi-native `entwurf_send` mailbox-fallback gates, a `mailboxConversationalDeliverable` predicate, a guarded mailbox-enqueue wrapper, and the required v2 active-receiver deliverability seam, so a send to a **deliverable self-fetch meta citizen** (an active-receiver claude-code session) with no live socket can fall back to the mailbox transport, while **direct-inject (pi) and inactive-receiver** targets reject without leaving mailbox garbage instead of falsely succeeding.

### Fixed (0.11.0 entwurf v2 — deliverability honesty, consumer-visible)

- **`entwurf_send` / `entwurf_self` stop reporting false delivery to unreachable targets.** Previously a send to a citizen with no live control socket, or a `replyable: true` self-report, could be emitted even when the target could not actually receive — a socketless / record-less pi session, an inactive (human-terminated) meta receiver, or a direct-inject (pi) target — leaving a `✓ delivered` signal and stray `.msg` mailbox files behind. Now such targets are **rejected honestly** (no enqueue, no mailbox garbage), and `entwurf_self` reports `replyable: true` only when a real inbound path exists. This is an observable change for `entwurf_send` / `entwurf_self` consumers, but it is a **honesty bug-fix, not a behavior regression** — a previously "successful" send to a dead/inactive target was always a false positive. Gates: `check-entwurf-deliverability`, `check-entwurf-mailbox-guard`, `check-entwurf-self-address`.
- **`entwurf_v2` now reaches a record-less but live pi control socket (socket-only fire-and-forget target).** `entwurf_peers` lists a live `pi --entwurf-control` session as alive whether or not it has a meta-record, but the v2 production `resolveTarget` previously rejected any record-less gid as `bad-target` — so an `entwurf_v2` to an operator-greeted live pi peer failed while a legacy `entwurf_send` to the same gid succeeded (a fact-surface ↔ dispatch contract gap; the `bad-target` was masked whenever a caller fell back to v1). v2 now accepts a record-LESS gid whose canonical control socket is a confirmed non-symlink socket as a **socket-only pi endpoint**: a PROBE-FREE presence hint (one lstat, no connect — the shared `socket-discovery` classifier, so listing and dispatch cannot drift) promotes it to a `fire-and-forget` control-send target only. It is **never** an owned citizen — with no record there is no cwd/launch authority, so `owned-outcome` is refused *before* any lock and spawn-bg can never open into it; a record-less dormant resume stays out of scope (0.11.1). Gates: `check-entwurf-v2-decider` (socket-only fire-and-forget execute / owned-outcome pre-lock `bad-target` / dormant·indeterminate honest reject, never a spawn), `check-entwurf-v2-production` (record-absent + live socket → execute; symlink/absent → `bad-target`).
- **Mailbox payload guidance is now explicit at the tool schema boundary.** `entwurf_send` and `entwurf_v2` message fields carry a broad hard cap (`maxLength: 16000`) plus guidance to send one compact atomic message; larger reviews/logs should be written as a file/artifact and sent as a path plus digest. This avoids encouraging multi-part chat sends on a self-fetch mailbox whose doorbell is edge-triggered and may coalesce. The paired `smoke-meta-mailbox` regression now proves the honest residual guarantee: if multiple `.msg` bodies do queue up, one `entwurf_inbox_read` drains the whole backlog in order, stamps one read receipt, archives every body, and re-read is empty. This is **drain-scoped** evidence, not a claim that every rapid send gets its own doorbell wake.

### Changed (0.11.0 — entwurf surface affordance, consumer-visible)

- **`entwurf_v2` is now the canonical garden-id delivery surface; `entwurf_send` is demoted to a lower-level direct-send compat tool (tool descriptions reworded).** A live incident exposed a surface affordance bug, not a function bug: when an agent holds a garden id and both `entwurf_send` and `entwurf_v2` are visible, the name "send" pulls it to `entwurf_send` — but a bare garden id does not reveal whether the target is a live pi session or a Claude Code meta-session, so the agent picks the wrong transport and fails (it poked a live-socket path at a meta-session that needed the mailbox). The fix is at the affordance layer: the `entwurf_v2` tool description (MCP + pi-native) now leads with "**canonical delivery surface for garden ids — when unsure which transport, use `entwurf_v2`**", and the `entwurf_send` description (MCP + pi-native) now leads with "**lower-level direct control-socket compat tool; for garden-id delivery prefer `entwurf_v2`; use this only with a known live pi socket / for `get_message`·`clear` debug**". README's ACP-backed tool list now includes `entwurf_v2` + `entwurf_inbox_read` and states the rule plainly: **send/reply → `entwurf_v2`, create → v1 `entwurf`.** No runtime dispatch behavior changed — this is description/affordance + docs only (no deterministic gate snapshots the description text; re-validated by `pnpm check`). The deeper convergence (folding `entwurf_send` delivery into `entwurf_v2`, keeping only its debug actions, or unregistering v1 send under v2-only mode) is a 0.11.x / `entwurf`-repo lane.

### Changed (0.11.0 — dependencies)

- **pi floor bumped to 0.79.4 (runtime parity).** Requires **pi >= 0.79.4** (`@earendil-works/pi-ai` / `pi-coding-agent` / `pi-tui` peer floor `>= 0.79.4`; devDep pins, lockfile, the `check-pi-runtime-version` FLOOR constant, and the `check-pack-install` peer pins all moved to `0.79.4` so the repo-local deterministic gates and the operator pi runtime stop diverging). 0.79.4 was confirmed to carry **no deterministic regression** vs 0.79.3 (probe + forced spawn A/B); the floor bump is a transport/API-compatibility statement, **not** a claim that 0.79.4's model-in-loop behavior is fully deterministic — Claude Sonnet's MCP-vs-Bash autonomous tool-selection remains non-deterministic and is tracked in the release-gate BEHAVIOR lane (below). The substrate carries typecheck-fence and runtime guards that keep the `.ts` / `.js` dual-import worlds honest under `node --experimental-strip-types`.
- **`release-gate` split into a two-tier MUST + BEHAVIOR summary.** The single flat must-pass list was divided so that v1/v2 *function* (deterministic + programmatic gates: `pnpm check`, `smoke-async-resume`, `smoke-entwurf-resume`, `check-native-async`, `check-bridge`, the v2 matrix/spawn-resume LIVE gates, the resident-garden-guard *negative/id-safety + /gnew zero-token* half, …) stays **release-blocking (MUST, owns the exit code)**, while the v1 *behavior* probes that depend on the model **autonomously** driving the MCP entwurf surface — `sentinel` (6-cell diagonal spawn) and resident-garden-guard *positive* (post-`/gnew` `entwurf_self` identity turn + positive garden model turn) — move to an **advisory BEHAVIOR lane that is surfaced but never blocks the cut**. This is a v1 *behavior advisory*, **not** "v1 unsupported/broken": the v1 tools themselves remain proven by the MUST programmatic gates. The S7 Bash-bypass detector (`sentinel-runner.sh`) stays a **hard FAIL inside the BEHAVIOR lane** — a Bash/Terminal/pi-CLI bypass is never relabelled a pass, only made non-blocking. A residual bypass after prompt strengthening is a 0.11.x usability item, not a 0.11.0 blocker. Rationale: the BEHAVIOR lane is *new 0.11-era coverage* (sentinel entered the release-gate `6592c5f` 5/29; resident-garden-guard/T3 `440afba`/`7d45346` 6/4) — it did not regress, it newly *measured* a v1 model-in-loop weakness the older gate never looked at.

### Deprecated

- **`plugins/openclaw` is deprecated and unmaintained (2026-06-10).** The OpenClaw plugin layer no longer has a reason to exist: Claude and Gemini now support ACP natively (Claude on a credit basis from 2026-06-15), so routing them through an OpenClaw wrapper buys nothing. The pi-shell-acp bridge itself is unaffected and continues to support Claude / Codex / Gemini directly — only the OpenClaw adapter context changed. The npm package `@junghan0611/openclaw-pi-shell-acp@0.0.1` is marked deprecated on the registry (not unpublished); the source under `plugins/openclaw` is frozen for reference. No further ClawHub / npm publishing. (The `@junghanacs` ClawHub publisher handle was separately recovered via clawhub#2346 and is retained for other uses.)

## 0.10.0 — 2026-06-06

The first meta-bridge release (#30): garden-native async delivery into already-running, already-authenticated native coding-agent sessions — Claude Code only. Built bottom-up — a deterministic drift sentinel protecting the (then-undocumented) async-delivery path, the backend-agnostic meta-record authority (schema + pure functions), the idempotent fs upsert, the Claude `SessionStart` create/attach hook, and `entwurf_send` mailbox delivery + read-receipt — then the sender/addressee identity path (a native session becomes both wakeable AND a trusted, replyable sender) — and on top of it the operator surfaces: honesty gate (Phase 1), stateful install/uninstall/doctor (Phase 2), the garden-identity statusline (Phase 3), the listing-only meta-store prune janitor (Phase 4), and native sender identity + addressee delivery (Phase 5). A final cut-time fix closed the last identity asymmetry: `entwurf_self` now resolves trusted meta-session identity too, so a native Claude Code garden citizen can self-report the same replyable garden-id envelope it uses for `entwurf_send`. Hardening landed in the same cut: the doctor's drift surface is fail-loud again (a `set -e` early-death regression closed + gated), and #34's level-triggered body-drain robustness basis is now an asserted gate, not just a doc claim. The 0.9.0 evidence-closure entries below also strengthen two live gates so 0.9.0's guarantees are proven *directly* rather than indirectly and trim a stale follow-up. Scope stays Claude Code only; agy/Codex remain proven future adapters, not shipped surfaces.

### Added (0.10.0 meta-bridge — Phase 5 native sender identity + addressee delivery)

- **`entwurf_send` learns WHO a native session is — authoritatively, not by cwd guess.** Phases 1–4 made a native Claude session *addressable* (the receiver half: wakeable by garden-id, inbox-readable). Phase 5 closes the *sender* half. A native session sending through the user-scope `pi-tools-bridge` MCP has no `PI_SESSION_ID`, so the bridge resolves identity from a **sender marker** the `SessionStart` hook writes, keyed by the shared Claude **parent pid** (`process.ppid` of the MCP child IS the Claude process the hook ran under — never cwd inference; `PI_META_SENDER_MARKER` overrides for tests). A trusted marker promotes the send to a **replyable `meta-session` sender** addressed by its garden-id. The marker carries `ownerPid` + a boot-unique `ownerStartKey`, so a **pid-reuse** by an unrelated process fails the guard instead of granting a wrong-identity send, and a marker with no backing meta-record is refused. `PI_TOOLS_BRIDGE_REQUIRE_META_SENDER=1` (set by the Claude user-scope install) closes the **anonymous-send hole**: a send with neither pi-session identity nor a trusted marker is refused rather than going out as anonymous `external-mcp` — "if we don't know who sent it, we don't send it." The sender envelope `origin` gains `"meta-session"`; the receiver render shows a `[meta-session]` badge. Deterministic E2E in `smoke-meta-sender-identity` (A→B garden-id sender, B→A reply, PPID path, unbacked-record reject, pid-reuse mismatch reject, anonymous reject); the mailbox round-trip (send → enqueue + signal → `entwurf_inbox_read` → `.read` archive + `lastReadAt` receipt) is covered E2E by `smoke-meta-mailbox`. Both gates are in `pnpm check`.
- **`entwurf_resume` async-capability discriminant fixed: `origin === "pi-session"`, not `replyable` alone.** A meta-session is `entwurf_send`-replyable (it owns a garden-id mailbox) but has **no pi control socket**, so it cannot host an async-resume `followUp` any more than an external host can. The old auto-resolve keyed on `replyable` and so routed a meta-session resume into a control-socket lookup that always fails. The async discriminant is now `asyncCapable = replyable && origin === "pi-session"`: a meta-session (like an external host) auto-resolves to **sync**, and an explicit `mode="async"` from either is rejected with the canonical reason text. `check-async-resume-gate` adds the meta-session cases (now 19 assertions).
- **Preventive keyset-overlap guard (`check-keyset-overlap` + `smoke-meta-keyset-guard`).** The meta-bridge install owns a fixed set of `~/.claude/settings.json` (+ `~/.claude.json`) keys (SSOT: `meta-bridge-state.py managed-keys`); agent-config and any future consumer merge their own fragment into the same file. This is the **preventive** half (doctor's `state.py check` is the after-the-fact survival half): it fails loud when a consumer fragment collides with a pi-owned key — exact match OR ancestor/descendant — so a later `agent-config` jq merge (`.[0] * .[1]`, which replaces arrays and overwrites scalars) cannot silently clobber pi-owned policy or vice-versa. `smoke-meta-keyset-guard` proves a disjoint fragment passes and exact/array/parent-child collisions fail loud while unrelated sibling keys (`permissions.defaultMode`, `language`) stay clean; in `pnpm check`.

### Fixed (0.10.0 meta-bridge — cut-time identity symmetry)

- **`entwurf_self` closes the last pi-only identity gate for garden-native meta-sessions.** Phase 5 made native Claude Code sends replyable by garden id, but the introspection twin still used the old strict pi-env path and threw when `PI_SESSION_ID` / `PI_AGENT_ID` were absent — even when the same MCP process had a trusted sender marker. `entwurf_self` now uses the same authoritative identity resolver as `entwurf_send`: pi sessions return `origin="pi-session"` + `socketPath`; trusted meta-sessions return `origin="meta-session"`, `agentId="meta-session/claude-code"`, `replyable=true`, the garden id, and `mailboxPath`; plain anonymous external hosts still fail because they have no authoritative reply address. This closes the cut-time asymmetry: a garden-native Claude Code session can now both **send as** and **self-identify as** a replyable garden citizen. Regression coverage lives in `smoke-meta-sender-identity`, and the fix was live-confirmed from `agent-config` via native Claude Code (`entwurf_self` returned the session's garden id and `replyable: true`).

### Fixed (0.10.0 meta-bridge — doctor fail-loud drift detail)

- **`doctor-meta-bridge` surfaces a managed-config drift instead of dying silently.** The `[managed config state]` section captured the `state.py check` output with a bare `CHECK_ERR="$(… check …)"` assignment under `set -euo pipefail`. The instant `check` exited nonzero (drift), the assignment tripped `set -e` and the doctor exited 1 **after printing only the section header** — the very "which key drifted" detail the section exists to print was lost, and every later section ([plugin install], [meta-record store], the SILENT-MISS guard) never ran. The substitution is now the condition of an `if`, so its nonzero status is consumed (not a death) and the drift detail + the entire rest of the chain always print. A hermetic regression in `smoke-meta-install-state` forces a real managed-config drift behind a fully-faked claude toolchain (no real claude, no real install) and proves the doctor (a) still exits 1, (b) prints `Drift detail:`, (c) names the concrete drifted key, and (d) runs to its final summary line — i.e. no early `set -e` death anywhere. Negative-tested: re-introducing the bare assignment fails the regression on exactly those assertions.

### Added (0.10.0 meta-bridge — #34 D8 level-triggered drain gate)

- **`check-meta-session` asserts the level-triggered body-drain robustness basis (#34).** The wake **signal** (`inbox.signal`) is edge-triggered — rapid pokes can coalesce into one `FileChanged`, or a signal can be lost entirely — but each message **body** is a separate level-state file on disk, so one `readMetaInbox` drains the *whole directory*. #34 names this the `D8` robustness basis and asks the gate to *assert* it, not just let `DELIVERY.md` claim it. A new case enqueues three messages (two fresh `.msg` + one doorbell-rung `.msg.delivered`) and proves a single drain returns **all** of them, in deterministic chronological (sorted) order, with **one** `lastReadAt` receipt for the batch, every body archived to `.read`, and a re-read empty. Negative-tested: an edge-triggered "drain one per signal" regression fails on the all-three assertion while the single-message cases stay green.

### Added (0.10.0 meta-bridge — Phase 4 prune listing)

- **`./run.sh meta-bridge-prune` — listing-only meta-store janitor.** `doctor-meta-bridge` reds on corrupt JSON / duplicate `nativeSessionId` / body↔filename drift, but it intentionally does **not** fail on transcript-gone records — so a green store still silently bloats with abandoned meta-records as native sessions come and go. This separate hygiene surface scans `defaultMetaSessionsDir()` (override with a positional dir; stale window via `--ttl-days`, default 30) and classifies every record into **orphan** (parse OK but `transcriptPath` no longer exists — a strong abandonment signal, not proof: a backend path migration / cleanup / config-dir change can also vacate it), **stale** (parse OK, transcript present, `lastSeen` older than the ttl), **ambiguous** (corrupt / drift / duplicate — manual-only: the operator decides which authority survives, never a blind rm of a duplicate pair), and **keep** (live transcript + recent). It prints the exact manual `rm` commands for orphan/stale candidates and **deletes nothing** — no `--apply` in 0.10.0 (this is the conservative "list, the operator removes" scope; actual GC / TTL automation / a global agent-skill wrapper are deferred). Exit 0 on any scannable store (corrupt records are classified, not fatal); a missing store is a clean 0-record listing. The offline `smoke-meta-prune` gate builds a synthetic store covering every class and proves correct classification, exit 0, and the no-deletion invariant (wording + on-disk file count unchanged); it is in `pnpm check`.

### Added (0.10.0 meta-bridge — Phase 3 statusline)

- **Repo-owned Claude Code statusline with garden identity.** `scripts/meta-bridge-statusline.sh` preserves GLG's existing Claude statusline data (device, shortened cwd with highlighted tail, git branch, model letter, context usage) and renders it as a documented Claude Code multi-line status area: row 1 is `<device> <cwd> [branch]`, row 2 is the meta-bridge truth surface plus runtime summary, `🪛 <garden-id> cc | <model> | <context>`. The garden id is resolved on every render by scanning meta-record **bodies** for the native Claude `session_id` (`nativeSessionId`), never by filename, cache, or DB; no match falls back to `?`, missing `session_id` to `ready`, and duplicate matches to `!` while doctor remains the fail-loud surface. Before implementation, the join key was live-measured: a real Claude statusline input carried `session_id=f232cc4a-29a9-42d9-8295-e4e3707c0c40`, which matched meta-record `20260606T133915-418d94.meta.json` by body.
- **Install/doctor now own and verify `statusLine`.** The Phase-2 state manager snapshots/restores `settings.json.statusLine`, applies the repo-owned statusline command, and checks for drift. `doctor-meta-bridge` verifies the command path, executability, and a synthetic two-row statusline run; `smoke-meta-install-state` covers state capture/restore plus statusline garden-id / no-record / no-session / duplicate fallbacks and exact two-row output.

### Added (0.10.0 meta-bridge — Phase 2 stateful install/doctor)

- **Stateful Claude Code install/uninstall for the meta-bridge.** `install-meta-bridge` now gates on `python3` as a first-class runtime dependency (the FileChanged doorbell parses hook JSON with it), snapshots the operator's pre-install values into `${CLAUDE_CONFIG_DIR:-~/.claude}/pi-shell-acp.install-state.json` (mode `0600`), then asserts only the repo-owned keyset: `enabledPlugins["entwurf-meta-receive@meta-bridge-local"]`, `extraKnownMarketplaces["meta-bridge-local"]`, USER-scope `pi-tools-bridge` MCP, the single-driver `permissions.allow/deny` additions, `env.DISABLE_AUTOCOMPACT`, and the Claude single-driver scalar policy (`cleanupPeriodDays=365`, prompt/away/memory/auto-compact/progress/plan-mode toggles pinned off, `skipDangerousModePermissionPrompt=true`, `verbose=false`). New `uninstall-meta-bridge` is the honest inverse: it preflights the state before touching Claude plugin/MCP registrations; scalar/map keys restore their original value or disappear if originally absent; permission arrays remove only the items pi-shell-acp added and preserve user additions. Without state it refuses to guess and performs zero Claude-side removals. A legacy-migration path treats exact pre-Phase-2 plugin/marketplace/MCP values as pi-owned absent values so GLG's already-dogfooded install can uninstall cleanly, while policy keys remain user-owned.
- **Doctor now consumes the Phase-1/2 blockers fail-loud.** `doctor-meta-bridge` validates the state file + managed keyset, fails when `meta-bridge-hook.log` shows an *unrecovered* ` ERROR ` (only a later `INFO armed watch` clears a transient miss; degraded `UserPromptSubmit` record backfill does not; a store-blocked miss that keeps re-logging ERROR stays red — the append-only log never goes stale-red on a one-time, since-healed failure), checks `python3`, and runs a full meta-record store scan via `meta-bridge-store-doctor.ts` for corrupt JSON/schema, duplicate `nativeSessionId`, body↔filename `gardenId` drift, and backend↔wakeMode contradiction. The offline `smoke-meta-install-state` gate covers state capture/apply/uninstall, no-state refusal, legacy migration, and store-doctor failure modes, and is now in `pnpm check`.

### Added (0.10.0 meta-bridge — step 3 fs upsert)

- **`upsertMetaSession` — the idempotent filesystem upsert (#30 step 3).** Wraps the step-2 pure core with the real filesystem: `mkdir -p` the store → `readdir` → `scanByNativeId` → `decideUpsert` → **atomic** write (tmp file + rename, mode `0600`) so a crash never leaves a half-written record (the #30 "write the record before the session takes over" crash-safety gate). Idempotent end to end: the second call for the same `nativeSessionId` attaches the *same* file/garden-id (lastSeen refreshed, no shadow record), and a duplicate `nativeSessionId` already on disk throws rather than silently picking one. `defaultMetaSessionsDir()` resolves to `<pi-agent-dir>/meta-sessions` — honoring `PI_CODING_AGENT_DIR` (override `PI_META_SESSIONS_DIR`) so an isolated install/test isolates its meta-records exactly like pi's own sessions, rather than a bare `~/.pi/meta-sessions`. The function lives inside `meta-session.ts` (not a sibling `*-store.ts`): the typecheck fence forbids a root-config lib importing another `.ts` lib via a `.ts` specifier while the `.js` specifier is unresolvable under `node --experimental-strip-types`, so a separate store file could not be exercised by the deterministic strip-types gate; only node builtins were added, keeping `check-meta-session` strip-types clean (now 38 assertions, 5 real-fs temp-dir). The thin CLI/argv shell that invokes this is deferred to step 4, where its stdin contract couples to the Claude `SessionStart` payload.

### Changed (0.10.0 meta-bridge — drift sentinel pin policy)

- **`smoke-meta-async-drift` pins the backend MAJOR.MINOR line, not the exact patch.** Claude ships ~weekly (observed 2026-06-05: 2.1.163 → 2.1.165 the same day, all 9 binary markers unchanged), so an exact-patch pin screamed on every bump and the signal was lost. The version check (A) now compares only `major.minor` (**Claude 2.1.x / codex-cli 0.136.x / agy 1.0.x**) and a minor/major move is the real "re-verify markers + Gotchas + raw/LIVE probes" trigger; the binary-marker cross-validation (B) now resolves and scans the **actually installed** patch binary rather than a hardcoded version path. Patch drift within a pinned minor passes; a minor/major move still screams with exit 1 (negative-tested).

### Added (0.10.0 meta-bridge — step 2 record authority)

- **`pi-extensions/lib/meta-session.ts` + `./run.sh check-meta-session` — the meta-record authority (#30 step 2, "record authority FIRST, hook LAST").** A *meta-session* is the bib card for a native backend session (Claude Code / Antigravity / Codex) that has no pi JSONL of its own: an opaque `.meta.json` pointer that makes the native session a garden citizen — addressable + wakeable by a garden id — without pretending pi owns its transcript (Hard Rule #8). This step is pure functions + types only (no fs authority, no hook, no CLI — those are steps 3/4), so the schema and the per-backend adapter seam get cut backend-agnostically before any "hook = Claude Code" assumption can ossify. `mintMetaRecord` stamps a fresh garden id + `createdAt==lastSeen` + a delivery slot seeded from the backend descriptor; `serializeMetaRecord` is deterministic (stable key order, 2-space, trailing newline); `parseMetaRecord` crashes-not-warns on every malformed shape (`MetaRecordError`), including a **backend↔wakeMode contradiction** (a Claude record claiming `direct-inject`, or vice-versa, is corrupt — delivery mode is backend-determined); `scanByNativeId` is THE lookup authority — it scans record **bodies** by top-level `nativeSessionId` (the `.meta.json` analog of 0.9.0 `findSessionFileById`), proven against a decoy filename in a real temp dir so it can never regress to filename-parse or a derived index, and it **scans to completion and throws on a duplicate `nativeSessionId`** (authority ambiguity is fail-fast, never silently pick one); `decideUpsert` keys on record **existence** (idempotent create-then-attach, never a second id) and refuses backend/identity drift. The read-receipt aspect is **pre-drilled** (`delivery.lastEnqueuedAt/lastDeliveredAt/lastReadAt` + `markEnqueued/markDelivered/markRead`) so the later mailbox/send path never touches the schema twice (bbot review #4); the three-backend seam is declared up front (`META_BACKENDS` + `META_BACKEND_DESCRIPTORS` with honest `wakeMode` self-fetch-vs-direct-inject / `deliveryLevel`). Deterministic gate: 33 assertions, wired into the `pnpm check` static floor.
- **Garden-id grammar consolidated into a real `.js` leaf (`pi-extensions/lib/session-id.js`).** `SESSION_ID_RE` / `formatSessionTimestamp` / `generateSessionId` / `isValidSessionId` moved out of `entwurf-core.ts` into a dependency-free `.js` leaf, following the `protocol.js` pattern (resolvable identically from both the tsc-emit path and the `node --experimental-strip-types` path — a literal `.js` specifier that pure unit gates can import, which a `.ts` sibling import cannot satisfy under strip-types without breaking the root tsc emit). `entwurf-core` imports and re-exports them, so existing importers are untouched and the id grammar is now a true single source instead of one-copy-per-importer. `check-entwurf-session-identity` stays 158/158 (no regression).

### Added (0.10.0 meta-bridge — step 1 drift sentinel)

- **`./run.sh smoke-meta-async-drift` — drift sentinel + capability gate (#30 step 1).** The Claude async-delivery path rides on *undocumented* Claude Code behavior (`asyncRewake` force-prepends `Stop hook feedback:` and ignores `rewakeMessage`; the payload channel is stderr-only; `watchPaths` arms from only `SessionStart`/`CwdChanged`/`FileChanged`). Claude ships ~weekly, so the path can break silently on any bump. This gate makes it *scream* instead — direct lineage of the 0.8.x fail-fast tool-surface gates. Two tiers, mirroring `smoke-compaction-policy`: the **deterministic default** (offline, free, CI/pre-commit safe) asserts (A) the three backends are on their pinned **major.minor** lines — **Claude 2.1.x / codex-cli 0.136.x / agy 1.0.x** (patch is intentionally not pinned: Claude ships ~weekly — observed 2.1.163 → 2.1.165 same day with all 9 markers unchanged — so an exact-patch pin screams every bump and loses the signal; a minor/major move is the real re-verify trigger and does scream; the `#30` prose "agy 0.136" was a conflation with codex's version) — and (B) nine undocumented-behavior marker strings are still present in the **actually installed** Claude binary (binary cross-validation; a marker dropping to zero = the behavior was renamed/removed = the delivery path is dead). **LIVE=1** adds (C) the plugin `SessionStart` watch-arm probe (`repro-plugin-idle-wake.sh probe`, one metered `claude -p`). Negative-tested: a moved pin or a vanished marker yields `DRIFT DETECTED` + exit 1. Not yet wired into `release-gate` — it asserts on the host's installed Claude binary (environment-dependent), so it stays out of the hermetic `pnpm check` floor; promotion into the aggregate gate waits for the 0.10.0 cut.

### Added (verification docs)

- **`DELIVERY.md` defines native async-delivery capability levels (`D0–D8`) for live external sessions.** This gives Claude Code, Antigravity/agy, Codex, and pi-native Entwurf a shared diagnostic coordinate system for "can an already-running session receive async work?" without collapsing transport-specific facts into a vague works/doesn't-work claim. Companion raw probes live under `scripts/raw-async-delivery/`; current evidence records Claude Code `FileChanged`/`watchPaths`/`asyncRewake` idle wake, agy native `send-message`, and Codex direct-TUI vs app-server split.

### Changed (test harness — evidence closure)

- **`cross-cwd-resume-smoke` now asserts append-not-recreate at the file/id level (T5), not just by recall.** The cross-cwd resume gate (`verify-resume` Phase 2) proved the issue-#9 fix *semantically* — the sentinel was recalled across the cwd boundary — but never directly asserted that the resume **appended to the one true session file** rather than silently minting a shadow session in the resumer's cwd. Around the existing recall, the smoke now captures a structural baseline after spawn and re-checks it after resume: (a) exactly one session file carries the header id before and after (no shadow minted anywhere), (b) it is the same file, appended in place (turn count grew), (c) the header id and cwd never drifted (resume authority stays = header, never the resumer's process cwd), and (d) no session for that id exists under the resumer's (wrong) cwd session dir. Live-verified: spawn at a scratch project dir, resume from `$HOME`, same file appended (turns 1→2), header id/cwd stable, no shadow under the resumer's (`$HOME`) session dir.
- **`smoke-resident-garden-guard` now directly proves the resume-into-uuid friendly pre-cancel (0 tokens).** The `session_before_switch` reason `"resume"` non-garden pre-cancel was previously only backstopped by the `session_start` hard guard — the friendly path was never exercised on its own. A new RESUME-INTO-UUID section drives an in-process RPC `switch_session` into a SYNTHETIC legacy-uuid session file (a one-line `{type:"session", id:<uuid>}` header is enough, because runtime `switchSession` calls `emitBeforeSwitch("resume", path)` BEFORE `SessionManager.open`). It asserts the switch is cancelled (`cancelled:true`), the friendly "resume is blocked … not garden-native" guidance lands on stderr, the hard guard never fires, 0 tokens (no `agent_start`), the resident stays on its garden id, and no control socket boots for the uuid. The 0-token sweep is now 30/0 (NEGATIVE + REPLACEMENT + RESUME-INTO-UUID + GNEW).

### Removed (follow-up hygiene)

- **Dropped the stale "semantic-memory `_entwurf-` guidance refresh" follow-up from `NEXT.md`.** `agent-config` `skills/semantic-memory/SKILL.md` was already migrated to garden-native discovery in 0.9.0 (no `_entwurf-` filename species; identity in the JSONL header/name; `--session-file-contains` reframed as a generic path filter), so the carried item no longer described reality.

### Verification

- Final release-prep evidence before the 0.10.0 cut: `pnpm check` PASS, then `./run.sh release-gate /tmp/psa-release-gate-0.10.0.EysLWp` PASS from log `/tmp/pi-shell-acp-release-gate-0.10.0-20260606T184217.log` — `PASS=17 FAIL=0 SKIP=0` with Gemini present. Artifacts: `smoke-async-resume` `/tmp/smoke-async-resume-20260606-184348.json`, sentinel `/tmp/sentinel-20260606-184958.json` (log dir `/tmp/sentinel-20260606-184958`), session messaging `/tmp/session-messaging-smoke-20260606-185236.json`.

## 0.9.0 — 2026-06-04

0.9.0 is the garden-native identity release. This is not just an Entwurf handle rename: the garden's own denote-style naming scheme is imported into the session layer so Entwurf sessions stop being treated as a separate species of worker artifact. Resident sessions, Entwurf children, and the later meta-bridge direction all converge on the same garden session ontology — one durable `sessionId`, one human-readable and machine-parseable name surface, one rule that the session comes first and the transcript file is only its trace.

### Changed (breaking — Entwurf public handle)

- **Entwurf public handle is now `sessionId`, not `taskId` (atomic migration, Phase 3b of #28 / 0.9.0).** The garden-native session id `YYYYMMDDTHHMMSS-[0-9a-f]{6}` (= JSONL header `id`) replaces the old 8-hex `taskId` across the entire local Entwurf public surface in one slice — there is no compatibility shim and a saved-session handle from a pre-migration spawn will not resolve:
  - **Spawn** (`runEntwurfSync` + native async `runEntwurfAsync`): the parent generates the sessionId (`generateSessionId`), pre-checks for collision (`assertSessionIdAvailableForSpawn`), builds the denote-style session name (`buildSessionName`, tagged `entwurf`), and spawns with `pi --session-id <id> --name <name>`. The `*_entwurf-<taskId>.jsonl` filename species is gone — Pi names the file `<created-at>_<sessionId>.jsonl`.
  - **Resume** (`runEntwurfResumeSync` + async `spawnEntwurfResumeAsync`): looked up by header scan (`findSessionFileById`), child cwd forced to the saved header cwd, and continued with `pi --session-id <id>` (appends to the same session). Resume keeps the same durable `sessionId`; a per-process internal/diagnostic `runId` distinguishes resume runs (never a public handle).
  - **Resume identity authority = first `model_change`.** New `readSessionIdentity` reads the session's FIRST `model_change` (provider + modelId) as the locked model identity — not the last assistant message's `model` field. A later differing `model_change` (drift) or a corrupt session-name mirror (name sessionId/provider/model disagreeing with the header / first model_change) is `SessionIdentityError` fail-fast.
  - **Entwurf-resume is gated on the `entwurf` name tag.** Since the `*_entwurf-<taskId>.jsonl` species is gone, "is this an Entwurf session?" is now answered by the session name's `entwurf` tag (`requireEntwurf`): a general pi session — no `session_info` name, a non-canonical name, or a canonical name without the `entwurf` tag — is refused at resume. No compatibility path.
  - **Surfaces migrated together:** `EntwurfResult.sessionId`, `formatSyncSummary` (`Session ID:`), native `entwurf` / `entwurf_resume` / `entwurf_status` tool schemas + result text, `entwurf-async` active map (keyed by sessionId) / ack / completion payloads, the `spawn_async_resume` control RPC, the MCP bridge `entwurf` / `entwurf_resume` Zod schema + descriptions, and the cross-cwd / compaction / async-resume / sentinel / MCP-test smokes.
- **Remote/SSH entwurf is out of scope and fails fast (#11).** The garden-native sessionId collision pre-check and header-scan resume are local-filesystem only, so spawn/resume/status with a non-`local` host throws `SessionIdentityError` up front. Remote identity is a later phase.

### Changed (breaking — resident `--entwurf-control` session must be garden-native)

- **Every `--entwurf-control` session is now garden-native or it hard-exits (#28 / 0.9.0 — operator session, not just Entwurf children).** Garden identity closes over the operator's own session too: when `--entwurf-control` is enabled, the session header `id` MUST be a garden sessionId (`YYYYMMDDTHHMMSS-[0-9a-f]{6}`). pi mints a `uuidv7` when the launcher did not pass `--session-id`, so a non-garden id means the session was not born through the garden launcher — `entwurf-control` refuses it at `session_start` and `process.exit(1)`s **before any model turn**. No uuid / back-compat path. (A bare `throw` or `ctx.shutdown()` in a `session_start` handler is swallowed by pi's extension runner — verified live that the model turn still ran and leaked 26k tokens — so the guard hard-exits.)
  - **Garden launcher.** Launch resident sessions through the launcher so the id is injected up front: `pi --session-id "$(<repo>/run.sh new-session-id)" --entwurf-control …`. `run.sh new-session-id` prints one fresh garden sessionId from the `generateSessionId` SSOT (no shell-side format duplication). See README §Garden launcher.
  - **`/gnew` (`/garden-new`) starts a fresh garden session in the same terminal.** Builtin `/new` remains blocked because pi's `ctx.newSession()` mints a uuid before any extension can re-stamp it. `/gnew` uses the safe path instead: a fail-closed writer pre-creates a valid garden session JSONL header, then the command calls `ctx.switchSession(file)`, whose `SessionManager.open()` reads that garden id before `session_start`. Header, control socket, backend stream `sessionId`, and MCP-child `PI_SESSION_ID` therefore all bind to the new garden id with no torn uuid moment. If the operator quits before the first turn, the empty session remains visible with message count 0; it is a legitimate resident session, not an orphan.
  - **Status label is the screwdriver 🪛, not the word "entwurf".** The resident status reads `🪛 ready` before the first assistant turn (session file not yet on disk — model still changeable) and `🪛 <gardenId>` after (file written = model locked). The id's presence is the model-lock lifecycle signal. The status label is decoupled from the session-name tag (the word "entwurf" no longer appears in the status bar, so it can't be misread as "talking to an entwurf'd session").
  - **Resident session name is lazy and tagged `control`, never `entwurf`.** On the first turn (model now locked) `entwurf-control` sets a garden name via `pi.setSessionName(buildGardenSessionName(...))` with the `control` tag and the cwd basename as title. `buildGardenSessionName` is registry-FREE (a native model like `deepseek/deepseek-v4-pro` that is not an Entwurf spawn target passes, where the child `buildSessionName` would throw) and FORBIDS the `entwurf` tag — so a resident session is never resumable as an Entwurf child via `entwurf_resume` (the `entwurf` tag is that resume marker).
  - **Coverage:** deterministic `check-entwurf-session-identity` (now 158 assertions) covers `assertGardenNativeSessionId` (uuid→throw / garden→pass), `buildGardenSessionName` (registry-free native model, `entwurf` tag forbidden, round-trip), `computeResidentStatusLabel` (🪛 ready / 🪛 id), the regression that a `control` session is NOT `entwurf_resume`-able, and the `/gnew` writer's fail-closed guarantees (`wx`, collision refusal, full read-back, guarded orphan cleanup). Live `smoke-resident-garden-guard` proves the negative (raw uuid → nonzero exit, no turn, no socket, 0 tokens), replacement safety (builtin `/new` / `/clone` cancelled, not hard-exit), `/gnew` 0-token E2E (new garden id, socket rebound, no uuid leak), and, opt-in, backend identity after `/gnew` (`entwurf_self` reports the new garden id).

### Changed (release-gate + test harness)

- **`release-gate` now runs the two garden-native identity gates first.** `smoke-session-id-name` (Phase 3a — Pi `--session-id`/`--name` substrate through the bridge) and `smoke-resident-garden-guard` (Phase 3c — the resident `--entwurf-control` guard, NEGATIVE 0-token path) run before the Entwurf live gates so an identity-foundation break fails fast instead of surfacing as confusing downstream failures. Both take no project arg and are exempt from the scratch-isolation concern by construction: the substrate smoke runs every pi turn under its own `os.tmpdir()` agent dir + cwds (`mkdtemp`, cleaned up), and the guard's negative path writes no session file at all.
- **`smoke-async-resume` completion detection hardened against a lazy-persist false-negative.** pi persists a parent session file only at the first assistant turn-end, and a slow orchestrator can still be mid-turn long after the resume child finished — so the previous single `find_parent_session_file` lookup at completion-check time could miss a parent JSONL that was about to appear, recording FAIL even though `entwurf-async` had already delivered+persisted the `entwurf-complete` (🏁) CustomMessage. The completion phase now re-resolves the parent file every tick and polls its persisted `entwurf-complete` count (tmux pane is the secondary fast-path channel); fail-closed is preserved (no detected completion → FAIL). Removed the now-unused `wait_jsonl_count_gt` helper. Test-harness only; no runtime behavior change. Product was already correct — verified by RESUME_OK in every resume child plus the persisted 🏁 in every parent across all three backends.
- **`check-native-async` exercises a LOCAL async spawn instead of a bogus remote host.** The native async spawn smoke used `host="__native_async_smoke_bogus__"` to enter `runEntwurfAsync` cheaply, but the 0.9.0 remote-out-of-scope fail-fast (#11) now rejects any non-`local` host *before* `runEntwurfAsync` runs — so the bogus-host call no longer exercised the async path at all (and failed the gate). The smoke now spawns a local async entwurf, which both matches the 0.9.0 scope and actually drives `runEntwurfAsync` for the stale-`explicitExtensions` ReferenceError guard it exists to catch.

### Verification

- The authoritative `/gnew`-inclusive 0.9.0 release-gate is green and recorded in `BASELINE.md`: a cut-time pi-session `./run.sh release-gate` run, **17 PASS / 0 FAIL / 0 SKIP** (Gemini present, no `--allow-skip-gemini`), with the resident garden guard at 31/0 (negative + replacement + `/gnew` 0-token E2E + positive/T3) and `check-entwurf-session-identity` at 158 assertions. It supersedes the earlier pre-`/gnew` Claude Code sweep that `/gnew` had invalidated.
- The async-resume repair was confirmed in isolation (6 PASS / 0 FAIL across Claude/Codex/Gemini + direct-stdio + external negative paths) before the full gate cycle; `/gnew` adds its own deterministic writer coverage plus live resident-guard smoke coverage.
- Backend-axis note (Hard Rule #7): `/gnew` T3 backend identity was live-measured on the release-gate default Claude lane (`claude-sonnet-4-6`) only. Codex/Gemini `/gnew` T3 runs are carried forward in `NEXT.md`; the general runtime matrix still remains covered by `smoke-all` across all three backends.

## 0.8.2 — 2026-06-01

### Fixed

- **Release-gate sentinel hardened against full-run-only false failures (project-scoped fallback + bounded MCP warmup grace).** The S2 session-file fallback now searches only the current project session dir instead of all of `~/.pi/agent/sessions`, preventing unrelated live `entwurf-*.jsonl` files from another cwd from being mistaken for this cell's worker. The ACP-Claude parent path also documents and bounds a test-harness cold-start race: on a brand-new ACP child, the first prompt can reach for the `entwurf` MCP tool before the backend's pi-tools-bridge child has finished registering it (`No such tool available`, so no worker spawned), especially when prompts remove the natural warmup work a model would normally do before the tool call. Spawn/resume now give exactly one short warmup-grace re-run when no worker turn exists and the raw stream shows that uncallable-tool signal (`SENTINEL_READY_RETRIES`/`SENTINEL_READY_BACKOFF`, default 1×3s), then fail hard. The 2026-06-01 green full sentinel did not need that retry; deterministic runtime readiness still belongs upstream (e.g. waiting for injected MCP servers to reach a terminal `mcpServerStatus`). Test-only change; no runtime behavior change.
- **Claude Opus 4.8 signed thinking-block 400 now invalidates poisoned ACP mappings.** A resumed Claude ACP session can fail with `API Error: 400 messages.<i>.content.<j>: \`thinking\` or \`redacted_thinking\` blocks in the latest assistant message cannot be modified` after Opus 4.8 tool-use turns. The bridge now classifies that narrow Anthropic transcript-validity surface as transcript poison, logs the existing `[pi-shell-acp:prompt-error] reason=transcript_poison`, closes the backend child, and drops the persisted `pi:<sessionId> → acpSessionId` mapping so the next turn naturally lands on `path=new` instead of retrying the same broken Claude transcript forever. `verify-transcript-poison` covers the raw API error, the pi-shell-acp diagnostic-attached form observed on a dev host, and adjacent negative cases.

### Changed

- **Bumped `@agentclientprotocol/claude-agent-acp` 0.38.0 → 0.39.0.** The upstream diff is intentionally small: 0.39.0 mainly adds `--hide-claude-auth` behavior and, more importantly for this incident, advances transitive `@anthropic-ai/claude-agent-sdk` 0.3.154 → 0.3.156. That SDK version corresponds to Claude Code 2.1.156, whose upstream version history says it fixed the Opus 4.8 "thinking blocks were modified" API error. Added direct `@anthropic-ai/sdk@0.100.1` to satisfy the newer SDK peer (`>=0.93.0`) without relying on pi's older devDependency copy.

### Verification

- Final release-gate evidence before cut: `/tmp/pi-tmux-release-gate-082.log` — `PASS=15 FAIL=0 SKIP=0`, run from the repo cwd against scratch project `/tmp/claude-1000/psa-rg-082.HVwOvk` with no `--allow-skip-gemini`.
- Sentinel evidence: `/tmp/sentinel-20260601-121604.json` passed 6/6 inside the release gate; earlier focused full sentinel `/tmp/sentinel-20260601-120416.json` also passed 6/6. The bounded MCP warmup grace did not fire in the green run.
- Continuity / messaging evidence: `verify-resume` passed cross-cwd recall, and `/tmp/session-messaging-smoke-20260601-121843.json` passed 4/4.

## 0.8.1 — 2026-05-31

Hotfix track for #29 — package-installed Entwurf ACP routing.

### Fixed

- **Entwurf ACP routing now resolves package-installed `pi-shell-acp` (#29).** When `pi-shell-acp` was installed via a Pi settings package source (`git:github.com/junghan0611/pi-shell-acp` or `npm:@junghanacs/pi-shell-acp`), Entwurf's bridge resolver returned null for `git:` / `npm:` sources, so a `provider=pi-shell-acp` target spawned a `pi --no-extensions --provider pi-shell-acp` child that died with `Unknown provider "pi-shell-acp"` before any session file existed. `resolveExplicitExtensionSpec` now maps user-scope `git:`/`npm:` sources to their installed roots (`~/.pi/agent/git/<host>/<path>`, `~/.pi/agent/npm/node_modules/<name>` — the latter keyed on the bare package name with any `@version` stripped), matching pi PackageManager's layout without importing pi internals. Local checkout sources keep their prior behavior.
- **Unresolved `pi-shell-acp` routing fails fast instead of warning-then-spawning.** The spawn path (`getRegistryRouting`) now throws `EntwurfRoutingError` before launching a guaranteed-broken child, and the resume paths (sync + async) surface an explicit `acp_bridge_unresolved` failure, rather than emitting a warning and spawning anyway. Fail-fast scope is explicit ACP intent only — registry `provider=pi-shell-acp`, resume `recordedProvider=pi-shell-acp`, and opt-in Codex-via-ACP; the Claude-only heuristic keeps its warning-only `pi-claude-code-use` fallback.
- **`check-bridge` negative-path `entwurf_resume` test is now env-hermetic.** The `[4b]` unknown-taskId case asserts the external-MCP-host sync error token `session_not_found`, but it inherited the launcher's environment — running `release-gate` from inside a live pi session (which exports `PI_SESSION_ID` / `PI_AGENT_ID`) made the resume default to the replyable-caller async path, whose error text omits that token, so the gate failed for the launcher's identity rather than for any bridge defect. The case now unsets both vars so the result is deterministic regardless of who launches the gate.
- **`check-bridge` is now an objective direct-MCP/protocol gate, not a backend self-recognition gate.** The attempted per-backend forced-call probe removed the old `NOT_VISIBLE` self-report escape, but a full release-gate still exposed Claude L1 variance: the child refused to call `entwurf_self` while the surrounding operational gates had already proven ACP-parent orchestration. `check-bridge` now owns only the direct MCP server contract (`tools/list` + `mcp/pi-tools-bridge/test.sh` negative paths). Live backend tool-callability/orchestration belongs to `smoke-async-resume` and `sentinel`, whose assertions are based on operational artifacts rather than a model's description of its tool schema.
- **`verify-resume` now uses neutral continuity prompts instead of `secret token` wording.** The old prompt pair (`test-token-123`, `What was the secret token?`) could trigger Claude safety/refusal behaviour and make continuity look broken when the bridge was actually fine. The gate now plants and recalls an ordinary word (`owl`), matching VERIFY.md's prompt-hygiene rule so release-gate continuity checks measure continuity, not safety interpretation.

### Added

- **`run.sh check-package-source-routing`** — deterministic gate (no backend, no spawn) pinning the package-source → install-root mapping and the fail-fast routing contract across the full matrix (local path / git user / npm user with and without a version spec / install-missing / project-scope-unseen / no-source, over local and remote), plus the local self-root fallback and the resume `unresolvedAcpIntent` signal. Wired into `pnpm check`.
- **`run.sh smoke-installed-entwurf-acp`** — credential-free live counterpart that reproduces git- and npm-installed package sources in isolated agent dirs, drives the real resolver to compute each bridge `-e`, then spawns a `pi --no-extensions -e <bridge> --list-models pi-shell-acp` child and asserts the provider registers (no `Unknown provider`, no `No models matching`). It now includes a packed-tarball topology proof (`npm pack` → install under `<agentDir>/npm/node_modules/@junghanacs/pi-shell-acp` → settings `npm:@junghanacs/pi-shell-acp` → resolver `-e` → `pi --no-extensions -e <bridge> --list-models pi-shell-acp`) before the registry publish exists. Wired into `release-gate` ahead of the Entwurf live gates so a green repo-checkout gate can no longer hide a broken official install path or publish-shape install root.
- **Local self-root bridge fallback.** When settings package-source resolution misses on a local spawn (e.g. a dev `pi -e /abs/path/pi-shell-acp` with no matching settings source), the resolver falls back to the loaded module's own package root via `import.meta.url`. Remote (SSH) spawn is excluded — a local path cannot cross SSH — and continues to require settings/source mapping.
- **`PI_CODING_AGENT_DIR` and `PI_SETTINGS_PATH` are now honored by the Entwurf resolver**, matching pi's `getAgentDir()`, so an isolated install-topology smoke can point both pi and the resolver at the same temp agent dir (and at a temp settings file independent of `<agentDir>/settings.json`). Remote root construction stays on the plain `~/.pi/agent` layout so a local override never leaks into an SSH path.

### Documentation

- README install section distinguishes the provider-registration smoke (`smoke-all`) from the Entwurf ACP-routing smoke (`smoke-installed-entwurf-acp` / `check-package-source-routing`).
- `docs/setup-clean-host.md` Stage 5 adds the credential-free package-source Entwurf ACP routing check, distinct from the two-session `entwurf_send` peer-messaging surface.

### Changed

- **`prepare` script is `husky 2>/dev/null || true`.** The bare `husky || true` still exited 0 on consumer/git-install machines (husky is dev-only) but printed a cosmetic `husky: command not found` line. Redirecting stderr drops the noise; behavior is otherwise unchanged.

### Verification

- Final release-gate evidence before cut: `/tmp/pi-tmux-release-gate-0811c.log` — `PASS=15 FAIL=0 SKIP=0`, run from the repo cwd against scratch project `/tmp/psa-release-gate-0811c.Z7L4VB` with no `--allow-skip-gemini`.
- The new install-topology live gate passed inside the release gate: `smoke-installed-entwurf-acp (#29)` proved git source, npm source, and packed-tarball source routing against the final `junghanacs-pi-shell-acp-0.8.1.tgz` package shape.
- Artifact cross-check: `/tmp/smoke-async-resume-20260531-181934.json`, `/tmp/sentinel-20260531-182435.json`, and `/tmp/session-messaging-smoke-20260531-182737.json` all point at the scratch session dir, not the repo session dir.

## 0.8.0 — 2026-05-29

Release-gate consolidation and pi 0.77 alignment. This release makes the full static + live verification path a single command, fixes the pi-provider auth boundary exposed by pi 0.77, aligns ACP dependencies, and moves the curated Claude Opus surface to Opus 4.8 only. The OpenClaw plugin remains a parked sibling track and is intentionally not migrated in this cut.

### Changed

- **`./run.sh release-gate` is now the release prerequisite.** The gate runs the deterministic `pnpm check` floor plus every live per-invariant gate, treats Gemini availability skips as release failures, pins `LIVE=1` for the compaction-policy probe, and prints a single PASS/FAIL/SKIP summary. `prepublishOnly` intentionally stays static+pack (`pnpm check` + `check-pack-install`); a green `release-gate` artifact is the documented manual prerequisite before publishing.
- **Dependencies aligned to the pi 0.77 / ACP current floor.** `@earendil-works/pi-{ai,coding-agent,tui}` are pinned to `0.77.0`, `@agentclientprotocol/claude-agent-acp` to `0.38.0`, and `@zed-industries/codex-acp` to `0.15.0`. `check-dep-versions` now asserts the pi devDeps and fresh-temp pack-install peer pins in addition to the ACP server pins.
- **Curated Claude Opus surface retired 4.7 and exposes 4.8 only.** `claude-opus-4-8` is required from the pi 0.77 registry and must report a 1M context window; the old placeholder-clone path for Opus is gone. `claude-opus-4-7` is now forbidden in the live curated model list. Historical VERIFY/CHANGELOG rows keep 4.7 as historical evidence.
- **ACP backend `--exclude-tools` / `-xt` policy is fail-fast for built-ins.** Excluding backend-native built-ins such as read/bash/edit/write would make pi's declared tool surface diverge from the backend's actual tool surface, so the provider rejects that request before backend launch. Pi-side extension tools such as `entwurf` remain excludable.

### Fixed

- **Corrected the pi provider auth boundary (#26).** The provider registration now uses an explicit no-auth sentinel instead of the legacy `ANTHROPIC_API_KEY` validation shim. pi-shell-acp still does not provide, proxy, copy, or require Claude/Codex/Gemini credentials; backend auth belongs to the official backend CLI child process. Static guards now reject any root bridge `apiKey: "ALL_CAPS_ENV"` regression.
- **Closed the sentinel async-delivery regressions.** ACP parent sentinel spawns now include the control socket they need, and both async completion delivery paths share the same stale-context best-effort guard instead of crashing the parent when a completion arrives after session replacement.
- **Preserved scratch cwd hygiene for full release gates.** `release-gate` now runs every live gate from the supplied project directory, including gates that take no project argument (`smoke-async-resume`, `check-bridge`, `check-native-async`, `sentinel`, `session-messaging`, `smoke-compaction-policy`, and `xt-tool-surface`). A repo-cwd invocation with a scratch project no longer writes new test sessions into the repo session directory.
- **Hardened `session-messaging` delivery assertions.** The smoke now checks the full MCP response for delivery success instead of grepping only a path-length-sensitive preview slice.
- **Made `smoke-cancel` robust to unrelated backend process cleanup.** The gate still fails on a positive process-count delta (leak), but no longer treats a negative delta from old unrelated `codex-acp` processes exiting during the smoke as a release blocker.

### Documentation

- Documented the external MCP host PATH boundary: GUI/editor-launched MCP servers may not inherit the interactive shell PATH, so `PI_TOOLS_BRIDGE_ENV_FILE` or an explicit MCP `env.PATH` may be required when `entwurf` needs to spawn `pi`.
- Updated clean-host and model-surface docs for the 0.77 / Opus 4.8 release floor.

### Verification

- Final release-gate evidence before cut: `/tmp/release-gate-0.8.0-final2-20260529-164313.log` — `PASS=14 FAIL=0 SKIP=0`, run from the repo cwd against scratch project `/tmp/pi-shell-acp-release-gate-20260529` with no `--allow-skip-gemini`.
- Artifact cross-check: `/tmp/smoke-async-resume-20260529-164342.json` and `/tmp/sentinel-20260529-164759.json` contain no repo session-dir paths; sentinel recorded six scratch session files and async-resume recorded the direct-stdio async session under the scratch session dir.
- `smoke-async-resume` passed 6/6 including `A.async.claude-sonnet-4-6`; this run did not hit the intermittent Sonnet model-argument variance path.

## 0.7.6 — 2026-05-27

Async-resume regression repair. Closes the most awkward intermediate state on the entwurf surface — short spawn defaulting async (0.7.0, `ad4413e`) while long resume blocked the parent turn (Phase 0.5, `agent-config e5aa5a1`, 2026-04-24) — and restores the pre-Phase-0.5 native pattern across both the native pi tool surface and the MCP bridge surface that pi-shell-acp Claude (and any other replyable pi-session caller) actually uses. Verified live across Claude, Codex, and Gemini (Hard Rule #7), plus a backend-agnostic handler-level proof + the external rejection path.

### Changed

- **`entwurf_resume` native default flipped `sync` → `async` (Phase A).** Restores the pre-Phase-0.5 behavior where long-running resumes (review / research / build) detach and deliver completion as a followUp message instead of blocking the parent turn. The async branch (`pi-extensions/entwurf.ts:929-1137` at the time) was already alive and unchanged — only the schema `default` and the `params.mode ?? "..."` runtime fallback were inverted. This completes the 0.7.0 axis symmetry that left resume on the Phase 0.5 `sync` default — producing the inverted state where short spawn (often <5s) detached while long resume blocked. Sync stays available as `mode="sync"` opt-in for short status-check resumes (<5s).

- **MCP `entwurf_resume` exposes `mode` with conditional default + replyable gate (Phase B Step 3).** The user-facing path: pi-shell-acp Claude and any other replyable pi-session caller of the MCP bridge now get async by default; external MCP hosts (Claude Code standalone, Codex CLI, Gemini CLI) stay on sync because they cannot receive followUp delivery. The discriminator is the existing `buildSendSenderEnvelope` replyable status — the same gate `entwurf_send` already uses for `wants_reply` rejection. A static `default: "async"` would have inverted external-host UX; the conditional default closes that. Explicit `mode='async'` from an external host is rejected with the canonical `ENTWURF_RESUME_ASYNC_REJECT_REASON` text, mirroring the `wants_reply=true` rejection pattern. Implementation note: the MCP handler does NOT clone the async launcher — it delegates back into the parent pi session via a new `spawn_async_resume` entwurf-control RPC (Step 2), so completion delivery stays in the pi extension layer where it belongs ("this bridge is not a second harness" invariant).

- **`entwurf_resume` `cwd` is sync-only at the MCP surface (silent-ignore guard).** The async launcher uses the saved session header cwd as authority (#9); the previous (pre-0.7.6) MCP schema accepted `cwd` but the async path silently dropped it. Now the handler rejects `effectiveMode='async' + cwd` explicitly with a canonical reject reason so callers do not believe their override took effect when it didn't. The replyable check still fires first when both could apply — callers see the more fundamental wiring break before the cwd detail.

### Added

- **`pi-extensions/lib/entwurf-async.ts` — shared async resume launcher + state (Phase B Step 1).** Hoists the async resume body (the 235-line block formerly at `pi-extensions/entwurf.ts:929-1137`) plus `activeEntwurfs`, `AsyncEntwurfInfo`, `findEntwurfSession`, `isProcessAlive`, and `ENTWURF_ENTRY_TYPE` into a single library module. Both the native `entwurf_resume` tool and the new entwurf-control `spawn_async_resume` RPC import the same `spawnEntwurfResumeAsync(...)` launcher and read/write the same `activeEntwurfs` Map — `/entwurf-status` sees every async task regardless of which surface spawned it (SSOT). The launcher accepts callbacks (`appendActiveEntry` / `deliverCompletion`) rather than depending on ExtensionAPI directly, so the lib stays platform-neutral and each callsite supplies its own parent-session notification surface. `shellQuote` source parity now spans three sites (added `pi-extensions/lib/entwurf-async.ts` to `check-shell-quote` `SOURCE_SITES`).

- **`spawn_async_resume` entwurf-control RPC (Phase B Step 2).** New command in the entwurf-control dispatcher: `{ type: "spawn_async_resume", taskId, prompt, host? }` → respond with `{ taskId, originalTaskId, sessionFile, pid, text }` on success, propagate the launcher's throws (Identity Preservation Rule, missing session file, missing cwd authority) verbatim as RPC errors. Lets the MCP bridge surface dispatch replyable async resumes by delegating into the parent pi session's extension context instead of cloning the launcher.

- **`check-async-resume-gate` deterministic gate (Phase B Step 4).** New `scripts/check-async-resume-gate.ts` exercises the conditional-default + cwd-silent-ignore logic — 16 assertions across 6 mode-resolution cases (replyable/external × {omit, sync, async} combinations) + 7 invariants (canonical reject text shape, no-silent-downgrade regression guard, defensive `replyable: undefined` handling, cwd guard ordering). Resolution logic lives in `mcp/pi-tools-bridge/src/resume-mode.ts` so the gate can import it without triggering the MCP server's `main()` side effect. Wired into `pnpm check` between `check-plugin-prompt-format` and `check-models`. No spawn, no socket, no API cost.

- **`smoke-async-resume` live gate (Phase B Step 5, three-backend axis).** New `scripts/smoke-async-resume.sh` (432 lines, pattern from `session-messaging-smoke.sh`). Six cases:

  - **A.async.{claude,codex,gemini}** — disposable tmux pi session per backend, prompt the backend procedurally (no identity claims) to chain MCP `entwurf` sync-only spawn → `entwurf_resume(mode='async')`, assert "Resume spawned (async)" ack AND "🏁 resume … completed" followUp in the pane. This proves the replyable MCP → control-RPC → native async launcher path on all three backends. The omitted-mode conditional default itself is pinned by `check-async-resume-gate`; the live gate uses explicit `mode='async'` so model prompt-following cannot hide the async branch.
  - **D.direct_stdio_async_handler** — handler-level proof independent of any backend's prompt-following: sets PI_SESSION_ID/PI_AGENT_ID env directly, stdio-calls the MCP bridge to spawn an entwurf and then `entwurf_resume(mode='async')`. Asserts the async ack text returns. Separates "handler correctness" from "backend prompt-following capability."
  - **B.external_async_reject** — external (no PI_SESSION_ID) + explicit `mode='async'` → reject with canonical text.
  - **C.external_autosync_shape** — external + mode omitted → auto-sync path reached (asserts via `session_not_found` on a synthetic taskId).

  Reference baseline run (2026-05-27, artifact `/tmp/smoke-async-resume-20260527-194013.json`): 6 PASS / 0 FAIL / 0 SKIP, three-backend equality closed, strict fail-closed (`❌ resume` is FAIL, only `🏁 resume … completed` is PASS). The final smoke also captured a useful boundary lesson: user-role identity assertions like "you ARE replyable" are rightly rejected by Claude as prompt-injection-shaped; the smoke prompt is therefore procedural and lets the MCP env decide replyability. Cost for the final full run was ~$0.11 (overall Phase B evidence formation ~$0.55). Required before every release that touches the entwurf surface; not in the deterministic `pnpm check` chain because it spends ACP turns.

### Verification

- `pnpm check` — 13 deterministic gates pass (`check-mcp`, `check-shell-quote` 17 (3 source-parity sites + reference body + 13 behavior cases), `check-plugin-empty-final-recovery` 34, `check-plugin-prompt-format` 22, `check-async-resume-gate` 16, `check-models` 3 passes, `check-backends` 136, `check-registration` 8, `check-dep-versions` 6, `check-sdk-surface` 0 unannotated casts, `check-pack` 52-file invariant — was 48 in 0.7.5, +4 for `pi-extensions/lib/entwurf-async.ts`, `mcp/pi-tools-bridge/src/resume-mode.ts`, `scripts/check-async-resume-gate.ts`, `scripts/smoke-async-resume.sh`).
- `./run.sh smoke-async-resume` — 6 PASS / 0 FAIL / 0 SKIP across Claude + Codex + Gemini (final strict fail-closed baseline reference run above).
- Three-backend equality (Hard Rule #7) — Claude, Codex, Gemini all GREEN with live evidence.

### Repository

- Commit chain (`main`): `ff85fa9` Phase A native default flip → `4b89b81` Step 1 lib extraction → `0107ce4` Step 2 control RPC → `684c97b` Step 3 MCP mode + conditional default → `69ff04b` Step 4 deterministic gate → `b28d1bb` cwd silent-ignore fix → `b6ef765` Step 5 live smoke → `24ee129` 0.7.6 release docs/version → `b98774b` pre-release surface-doc alignment + fail-closed smoke → `d198da0` procedural smoke prompt.
- AGENTS.md, README, VERIFY.md, NEXT.md, and MCP/source comments updated to the final 0.7.6 surface: MCP `entwurf` spawn remains sync-only; MCP `entwurf_resume` is conditional-default async for replyable pi-session callers and sync/reject for external non-replyable hosts.
- NEXT.md — async-resume repair moves out of active state. Phase A and Phase B complete; next focus returns to Asymmetric Mitsein / session-continuity hygiene.

## 0.7.5 — 2026-05-21

Dependency-audit-driven patch release. Absorbs three concurrent upstream upgrades without touching the bridge's public surface (settings, MCP injection contract, sessionId addressing, invariants). Operators upgrading from 0.7.4 should observe the same baseline tracked on issue #24 (96% prompt cache hit, zero compactions, stable role-preserving prompt). Bridge metadata, plugin docs, and the post-release follow-up split round out the cut.

### Changed

- **`@earendil-works/pi-{ai,coding-agent,tui}` 0.74.0 → 0.75.4.** One minor plus four patches absorbed. The new `agent_end.willRetry` event field flows through the existing generic notification path (event-mapper has no name-keyed handler), the 0.75.4 system-prompt XML-boundary change is added by pi's internal assembly so `engraving.ts` / `pi-context-augment.ts` continue to inject identity via `_meta.systemPrompt` without double-wrapping, and the strengthened `ctx.abort()` preflight semantics (stops later confirmations, restores queued interactive input) are absorbed at the single bridge call site (`pi-extensions/entwurf-control.ts`) without code change. `npm-shrinkwrap.json` bundling is upstream-only (pi's own published install) and conflicts no `check-pack` invariant. HTTP idle-timeout improvements absorb automatically. `run.sh check-pack-install` peer-install pins updated 0.74.0 → 0.75.4 in lock-step.

- **`@agentclientprotocol/sdk` 0.21.0 → 0.22.1.** One minor plus one patch. `schema v0.13.2` (0.22.0) narrows `ImageContent.data` and `.mimeType` from optional to required, so `PromptRequest.prompt: Array<ContentBlock>` now refuses our looser internal `PromptContentBlock` union directly. Resolved with a wire-boundary conversion inside `sendPrompt` rather than narrowing the internal alias, so pi-side `url`-only image content blocks degrade to a `[image: <uri>]` text fallback instead of being silently dropped. `check-sdk-surface` confirms the typed connection (`resumeSession`, `closeSession`, `prompt`, `cancel`, `unstable_setSessionModel`) is unchanged in shape and identifiers — zero `(connection as any)` casts. Event-ordering fix (0.22.1) and the new unstable session-delete handling (0.22.0) flow through without bridge-side adoption.

- **`@agentclientprotocol/claude-agent-acp` 0.33.1 → 0.36.1.** Three minors plus one patch. Bedrock gateway authentication (0.34) and the gateway-auth flaky-bypass fix (0.36.1) are upstream-only with no surface touching our code. The SDK settings-resolution defaults change (0.35) is contained inside the backend's defaults layer — `provider.options` continues to pin the fields we care about (model, context window, permission posture). The new plan-state hook (0.35) and `additionalDirectories` experimental field (0.36) have no event-mapper handler, so they pass through generically without bridge-side intervention. `closeSession` (acp-bridge.ts) keeps the same typed signature; we do not adopt the new experimental session-delete method — close-on-shutdown remains sufficient. `run.sh CLAUDE_ACP_REQUIRED_VERSION` bumped in lock-step (`check-dep-versions` assertion #4).

- **`plugins/openclaw/README.md` documents the child skill PATH + emacs socket env contract.** ACP-route bots that invoke skills (gitcli, denotecli, emacs, …) inside an OpenClaw Docker container need `PATH` to include the per-skill bin dirs and `PI_EMACS_AGENT_SOCKET` to be the full socket path (short-name resolution fails on the standard bind-mount layout). Worked example: nixos-config 3477206. A NixOS Nix-store hash refresh note is included for hosts that bind-mount `/nix/store` into the container. Plugin-side env preparation is the permanent home; this README addition is the operator contract until that code fix lands (see #21).

- **`package.json#pi.image` reverted to `pi-shell-acp-demo.gif`.** The hero image (`docs/assets/pi-shell-acp-hero.jpg`) added in 0.7.4 surfaced in an unintended slot on the pi.dev gallery card; `demo.gif` better fits the "what this package actually does" role of the gallery image. `hero.jpg` remains the README banner (line 5). Refs #22.

### Repository

- All bumps land with `pnpm check` GREEN across 12 gates (`check-mcp`, `check-shell-quote`, `check-plugin-empty-final-recovery`, `check-plugin-prompt-format`, `check-models`, `check-backends`, `check-registration`, `check-dep-versions`, `check-sdk-surface`, `check-pack` plus lint + typecheck). `check-pack` reports the same 48-files invariant; the typed-surface gate stays at zero unannotated casts.
- NEXT.md realigned: new top-priority box for the 0.7.5 dep-audit round with a baseline-preservation cross-check table keyed to issue #24's 2026-05-21 baseline cmt. The prior Phase 3.4 box demoted to Phase 3.4/3.5 with the #23 RFC-bound split decision — ClawHub `@junghanacs` handle release deferred to RFC #2320 / #2333 outcome (weeks-months timeline per ClawSweeper v3 review), Phase 3.4 npm publish proceeds independently. Plugin-side env-preparation code fix (#21) moved to a post-0.7.5 follow-up (0.7.6 candidate) so it does not block the dep-audit release; the nixos-config consumer-side workaround (3477206) keeps operators unblocked in the meantime.
- AGENTS.md verification command list now records the actual sentinel runner shape: `./run.sh sentinel [cells]` (omit cells = all six), not the older project-path form. This matches the Tier B 6-cell validation path used for 0.7.5.

## 0.7.4 — 2026-05-20

Patch release for the post-#20 OpenClaw stabilization line. The root npm artifact ships the new deterministic recovery / prompt-format gates plus the refreshed public docs and gallery metadata; the OpenClaw plugin remains a separate unpublished sibling package, but this tag is the stable baseline that the upcoming plugin `0.1.x` prerelease should depend on.

### Fixed

- **OpenClaw plugin no longer primes the model to emit chat-completion artifacts (issue #20 follow-up incident).** Oracle bbot verification on `claude-opus-4-7` after the empty-final fix landed observed a new visible-body leak class: the model emitted its actual reply, then a fabricated `User: …` next-turn line, then a Cline-style `</environment_details>` close tag. None of those tokens exist in our code, OpenClaw, claude-agent-acp, or the ACP source — they came from the model's own training. Root cause was the earlier `buildConversationPrompt` form: it serialized OpenClaw's `context.messages` into a literal `User: …` / `Assistant: …` transcript prefix, which primed the model to continue the chat-completion pattern. Real OpenClaw provider plugins (anthropic/openai/google transport streams) never do this — they preserve role information as a native message-array payload via `transformTransportMessages`. The new serializer carries the same role information as JSON-as-data (`[Prior conversation context]\n[ {"role":"user","content":"…"}, … ]`) with a scoped non-continuation instruction (the instruction targets the context echo, NOT a blanket "no JSON in reply" — so legitimate "respond in JSON" user requests still work). The new `stripChatCompletionTail` sanitizer is applied final-only (post-recovery, pre-`done`) with narrow patterns: `</environment_details>` is the **allowlisted** closing tag (generic `</tag>` would chop legitimate XML); the `User:` / `Human:` / `Assistant:` strip requires a **blank-line boundary** (`\n{2,}`) and caps the trailing text at 160 chars (so a quoted single-line `Last entry: User: anonymous` is preserved). The sanitizer also enforces the issue #20 empty-visible-body invariant — if stripping would leave an empty body, the helper substitutes the placeholder instead, so OpenClaw never receives an empty assistant body. This is a stub-only shim — Phase 1.4 ts refactor swaps to real ACP stdio framing and `buildConversationPrompt` disappears entirely.

- **OpenClaw plugin no longer leaks empty assistant turns to OpenClaw's raw-prompt render fallback (issue #20).** Post-`#17` regression on the ACP path: Active Memory `context_pre_compute` returned `status=ok` with a non-empty summary, but the assistant turn surfaced no visible body — the user saw raw `<command-name>` / `<command-message>` prompt fragments from OpenClaw's fallback render. Root cause was a pair of asymmetric recovery branches inside `finalizeChild`: `partialOverridesFinal` fired only on abnormal exit and `recoveredFromPartial` fired only when finalMessage was null, so a clean `message_end{role:"assistant", content:[]}` slipped past both. The fix unifies the recovery decision into the new `resolveRecoveredFinalMessage` helper in `plugins/openclaw/src/index.ts`, adds `finalIsEmpty` cover so both partial-recovery branches treat an empty-content final the same as a missing final, and synthesizes a minimal placeholder text block on a clean exit with no partial available so OpenClaw never receives an empty assistant body. Recovery length comparisons use trimmed text so a whitespace-only partial (`"   "`) cannot be promoted into a visible-empty final — the same surface class the main fix closes. The sibling `inner.message` carrier inside `message_update` events is now normalized symmetrically with `inner.partial`. Abnormal exits with no recovery option still surface the existing diagnostic error event (stderr tail preserved).

### Added

- **`./run.sh check-plugin-prompt-format` deterministic shape gate.** New `scripts/check-plugin-prompt-format.ts` exercises `buildConversationPrompt` invariants (8 cases — empty / single-turn / multi-turn / NEVER emits literal `User:` or `Assistant:` transcript lines / skips toolResult / skips empty-text / JSON round-trips / non-continuation instruction is context-scoped not a blanket "no JSON" rule) plus `stripChatCompletionTail` invariants (10 cases — passthrough / `User:` / `Human:` / `Assistant:` require blank-line boundary / `</environment_details>` allowlist case-insensitive / arbitrary `</tag>` preserved / combined leak / 160-char length cap / inline mid-text preserved / empty input passthrough) plus `sanitizeFinalAssistantMessage` empty-final invariant guard (4 cases — preserves non-leak content / strips combined leak but keeps real reply / falls back to placeholder when sanitize would empty the body / falls back to placeholder when all content is leak). No pi process, no network, no API cost; runs in the root `pnpm check` chain.

- **`./run.sh check-plugin-empty-final-recovery` deterministic recovery-decision gate.** New `scripts/check-plugin-empty-final-recovery.ts` exercises every branch of `resolveRecoveredFinalMessage` on synthetic `AssistantMessage` inputs — 19 cases covering null / empty / valid / whitespace-only final crossed with null / valid / whitespace-only partial crossed with clean / abnormal exit, plus an invariant pass that asserts no recovered final ever carries empty (including whitespace-only) content. No pi process, no network, no API cost; runs in the root `pnpm check` chain alongside the other deterministic gates.

### Changed

- pi package gallery / README hero surface now uses `docs/assets/pi-shell-acp-hero.jpg` instead of the runtime demo loop. `package.json#pi.image` points the pi.dev gallery card at the GLGMAN hero shot, and the README places the same hero image above the npm badge so the package detail page is more likely to pick the intended header image first.
- OpenClaw prerelease plugin metadata and Docker-lab docs now record `2026.5.18` as the validated production baseline while preserving the `>=2026.5.12 <2026.6.0` compatibility floor.

## 0.7.3 — 2026-05-19

Patch release for the OpenClaw / Telegram operational validation path. The root npm artifact change is intentionally narrow: ACP tool and permission notices are now rendered as safe one-line fragments, so backend-provided titles or summaries containing Markdown fences / newlines cannot make Telegram treat the rest of the turn as one giant code block. The source tree also records the prerelease OpenClaw plugin #18 config-resolution fix and oracle Stage 1 GREEN evidence, but `plugins/openclaw/` remains a separate unpublished package and is not shipped in the root `@junghanacs/pi-shell-acp` tarball.

### Fixed

- **Tool / permission notice fragments are Markdown-safe and one-line.** `event-mapper.ts` now sanitizes the text used in `[tool:start]`, `[tool:running]`, `[tool:done]`, `[tool:failed]`, `[tool:cancelled]`, and `[permission:*]` notices: whitespace collapses to a single space, triple-backtick runs become an explicit `[fence]` placeholder, remaining backticks become ordinary quotes, and titles / summaries are truncated after sanitation. This closes the Telegram renderer failure where a sliced tool summary containing an unclosed code fence swallowed following `[tool:start]` notices and assistant text.

### Repository / plugin prerelease trail

- `plugins/openclaw` source now resolves plugin-scoped config from OpenClaw's nested `config.plugins.entries["pi-shell-acp"].config` path and validates configured `spawnTimeoutSeconds` / `piBinaryPath` fail-loud. Oracle Stage 1 confirmed the #18 bootstrap-timeout RC fix (`timeoutMs=60000→600000`) and the bbot β path cold turn. This is recorded for monorepo continuity only; the plugin is still installed from source / future sibling package, not from the root npm package.
- Envelope identity sanitation (#19) is explicitly deferred to a later separate sprint. 0.7.3 does not attempt to change the sender-envelope contract.

## 0.7.2 — 2026-05-19

Patch release for a registry-artifact regression discovered after the first `npm publish`. Source repo tracks `100755` on `run.sh`, `mcp/pi-tools-bridge/start.sh`, the `demo/*.sh` pair, and `scripts/*.sh`, and the locally produced `npm pack` tarball preserved those modes. The artifact uploaded to the registry, however, normalized every `.sh` to `0644` — fresh `pi install npm:@junghanacs/pi-shell-acp@0.7.1` left the README-documented direct entry point (`"$(npm root -g)/@junghanacs/pi-shell-acp/run.sh" install .`) and the `pi-tools-bridge` MCP startup script non-executable, surfacing as `Permission denied` and a silent MCP launch failure on the consumer side. 0.7.2 restores the executable bit through a `postinstall` hook and locks the regression with a new dry-run gate.

### Fixed

- **Executable bit restored on every shipped `.sh` after install.** New `scripts/postinstall-chmod.cjs` runs at `postinstall` time and `chmod 0755` `run.sh`, `mcp/pi-tools-bridge/start.sh`, `mcp/pi-tools-bridge/test.sh`, `demo/demo.sh`, `demo/demo-baseline.sh`, and every `*.sh` under `scripts/`. Hand-written in CJS so it runs regardless of the consumer's package `type` and never depends on resolving its own `package.json`. Each `chmod` is wrapped in its own `try` — Windows, read-only mounts, or any other filesystem refusal logs a warning and continues, so an install can never fail because of a chmod refusal.

### Added

- **`.sh` mode regression gate in `./run.sh check-pack`.** The dry-run inspector now reads each entry's `mode` from `npm pack --dry-run --json` and fails closed if any tracked `.sh` ships without the executable bit. The repo's source files already track `100755` and the local pack preserves that, but a contributor's umask or a `git update-index --chmod=-x` would silently drop the bit; this gate makes that case fail at `pnpm check` time. The registry-side mode normalization (the actual root cause behind 0.7.1's break) remains outside our control — the `postinstall` hook above is the defense for that.
- `scripts/postinstall-chmod.cjs` added to the `check_pack` / `check_pack_install` required-file lists so an accidental drop of the chmod script itself is caught at publish gate time.

## 0.7.1 — 2026-05-19

Patch release for the first npm publish path. `v0.7.0` was tagged on GitHub but intentionally not published to npm after the final dry-run found a lifecycle-script interaction; 0.7.1 carries the same public package surface with the publish guard fixed.

### Fixed

- Fixed `prepublishOnly` under `npm publish --dry-run`: the nested `check-pack-install` smoke now runs `npm pack --dry-run=false`, overriding npm's inherited `npm_config_dry_run=true` lifecycle environment. Without the override, `npm pack` printed the scoped tarball name but did not create the `.tgz`, causing the publish guard to fail with `tarball not produced` before a real publish could be exercised.

## 0.7.0 — 2026-05-18

Phase 2 packaging-surface refactor closes and the clean-host install preflight clears on a real Ubuntu target (`cleanhost`: Stages 0–3, 4a, Stage 4 prep settings, and 4b authenticated runtime smoke for Claude / Codex / Gemini all verified — see [`docs/setup-clean-host.md`](./docs/setup-clean-host.md)). The 0.7.0 cut adopts the `@junghanacs` npm scope and pins the publish-ready surface; the actual `npm publish` is held for a separate round so the patch and the registry push do not blur into one another.

### Added

- Dry-run tarball invariant gate: `./run.sh check-pack` (also `pnpm check-pack`). Runs `npm pack --dry-run --json`, then asserts that runtime-critical files and the public verification/docs surface are present and that private/dev residue is absent. Part of the default `pnpm check` so every commit catches a packaging drift.
- Heavy publish gate: `./run.sh check-pack-install` (also `pnpm check-pack-install`). Closes the remaining three items in #13's publish checklist — actual `npm pack`, `tar -tf` invariant cross-check, and a fresh-temp project install smoke that `pnpm add`s the produced tarball plus the 0.74.x peer baseline (`@earendil-works/pi-{ai,coding-agent,tui}` + `typebox`) and probes the installed `@junghanacs/pi-shell-acp/package.json` to confirm `pi.extensions` arrives intact. A final **pi package loader smoke** then runs `pi -e <tmp>/node_modules/@junghanacs/pi-shell-acp --list-models pi-shell-acp` and grep-asserts the output contains both `pi-shell-acp` and the `claude-sonnet-4-6` model anchor — meaning pi accepted the package as a real extension and registered the provider, not just that the tarball was a well-shaped npm artifact. `--list-models` does not spawn the Claude/Codex/Gemini backends, so the smoke stays credential-free. Kept out of the default `pnpm check` because of the 5–15s dependency-resolution cost.
- `prepublishOnly` package script wires `pnpm run check && pnpm run check-pack-install` so any future `npm publish` fails closed if either the existing nine gates, the dry-run invariants, or the actual install path regress.
- `test:pack` package script — alias for `pnpm run check-pack && pnpm run check-pack-install`. Matches the `prepublishOnly` / `test:pack` pair named in #13's publish checklist; lets operators run the same dry-run + actual-install verification without invoking the full `pnpm check` pipeline.

### Changed

- **In-pi `entwurf` default mode flipped from `sync` to `async`.** `pi-extensions/entwurf.ts` now defaults to `async` — spawn returns a Task ID immediately and the parent turn is free; completion arrives as a follow-up notification. `sync` stays available as explicit opt-in for short status checks (<5s). The slash-command surface (`/entwurf`) matches: bare `/entwurf <task>` is async, `/entwurf sync <task>` opts into the blocking path, and `/entwurf async <task>` is preserved as a backward-compat no-op so pre-0.7.0 muscle memory keeps working. Rationale: review / research / build calls dominate spawn usage, and blocking the parent turn for >30 s reads as "stuck" to the operator — this UX failure was the 2026-05-19 publish-prep finding (sibling GPT-5.4 + GLG observation). External MCP host surface (`mcp/pi-tools-bridge/index.ts`) remains sync-only by design; the tool description carries that statement verbatim. Async via MCP is a deferred design round (see NEXT.md "pi-tools-bridge MCP async surface"). AGENTS.md "Entwurf Orchestration" updated to state the in-pi vs external-MCP asymmetry explicitly.
- **npm scope adopted — `pi-shell-acp` → `@junghanacs/pi-shell-acp`.** Bare name was never on npm and the OpenClaw plugin sibling already lives under the same scope (`@junghanacs/openclaw-pi-shell-acp`), so the scoped form is source-of-origin parity with that sibling and unambiguously points at the GitHub repo of record. The runtime provider id `pi-shell-acp` is **unchanged** — model strings (`pi-shell-acp/claude-sonnet-4-6`), settings keys (`piShellAcpProvider`), log prefixes (`[pi-shell-acp:bootstrap]`), and the `--provider pi-shell-acp` CLI surface keep their existing names. The scope migration affects only the npm publish identity and the install paths derived from it.
- **`package.json` version `0.6.0` → `0.7.0`** in the same patch as the scope rename so the first published version is unambiguously the scoped artifact. No 0.6.x is ever published under either name.
- **`run.sh` install / pack surface updated for the scope:**
  - `PACKAGE_NAME` constant rewritten as the scoped form with an SSOT comment block explaining why this is the npm identity and `PROVIDER_ID` is not.
  - `check_pack_install` tarball name updated from `pi-shell-acp-${version}.tgz` to `junghanacs-pi-shell-acp-${version}.tgz` — npm's scoped-pack naming rule (strip `@`, replace `/` with `-`).
  - `check_pack_install` install-probe `import('pi-shell-acp/package.json')` updated to `import('@junghanacs/pi-shell-acp/package.json')`.
  - `check_pack_install` pi loader smoke install path updated from `$tmp/node_modules/pi-shell-acp` to `$tmp/node_modules/@junghanacs/pi-shell-acp`.
  - Other `pi-shell-acp` substring grep / `endswith` checks in `run.sh` (install scanner discovery, MCP path detection) work unchanged against scoped paths — the trailing path segment is the same.
- **README install table swapped to the scoped form** in all four `npm:` install paths (global + project, `pi install` + `pi install -l`). The `git:github.com/junghan0611/pi-shell-acp` paths are unchanged — git source identity is the repo URL, not the npm name. The "not on npm yet" inline note was retitled from "tracked in #13" to "0.7.0 publish pending" to reflect where the work actually stands.
- README install surface restructured into the four `pi install` paths that `packages.md` defines — `npm:` and `git:`, each in **global** (default) and **project** (`-l` flag) scope — plus a fifth local-clone path for hacking on the bridge. Each path now shows the exact location of `run.sh install .` after install (`$(npm root -g)/@junghanacs/pi-shell-acp/`, `./.pi/npm/node_modules/@junghanacs/pi-shell-acp/`, `~/.pi/agent/git/...`, `./.pi/git/...`, or the cloned directory) so operators do not have to guess where the post-install hook lives. Lead paragraph carries the auth-boundary statement — pi-shell-acp does not provide Claude credentials or bypass any backend auth; the operator's local `claude`/`codex`/`gemini` trust is what the bridge uses. Codex/Gemini moved under a new `### Backend prerequisites` sub-section, and the OpenClaw plugin sibling (`@junghanacs/openclaw-pi-shell-acp`) is explicitly called out as separate from the root install. A second callout warns against filtering the four `pi.extensions` entries — they ship as one set (provider + entwurf + entwurf-control + model-lock) and partial filtering can leave the model lock or entwurf surface in a broken state.
- `package.json` metadata aligned with pi package gallery conventions (sample cross-check against `pi-synthetic-provider`, `pi-firecrawl`, `pi-exa-mcp`, `pi-claude-code-use`, `pi-telegram`):
  - `keywords` expanded to include `pi`, `pi-extension`, `pi-coding-agent`, `ai-provider`, `acp-bridge` for gallery discoverability.
  - Explicit `files` allowlist added — runtime sources (`index.ts`, `acp-bridge.ts`, `event-mapper.ts`, `engraving.ts`, `pi-context-augment.ts`, `protocol.js`, `pi-extensions/`, `mcp/`), public verification surface (`run.sh`, `scripts/`, `prompts/`, curated `demo/` entries, the three README-referenced gifs under `docs/assets/`, `pi/{entwurf-targets.json, settings.reference.json, skill-plugin-example/}`), and operator docs (`AGENTS.md`, `BASELINE.md`, `VERIFY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`). The OpenClaw plugin sibling (`plugins/openclaw/`, published separately as `@junghanacs/openclaw-pi-shell-acp`) is excluded.
  - `typebox` added to `peerDependencies` (`"*"` range) — `pi-extensions/entwurf.ts` uses `Type.Object` / `Type.Union` / `Type.Literal` and pi packages.md requires this peer.
- **peerDependencies range** confirmed at `"*"` for all peers (`@earendil-works/pi-{ai,coding-agent,tui}`, `typebox`) per the pi `packages.md` rule (L166: "list them in `peerDependencies` with a `"*"` range and do not bundle them"). Same pattern across every sample inspected (`pi-firecrawl`, `pi-exa-mcp`, `pi-claude-code-use`, `pi-synthetic-provider`, `pi-telegram`). No tightening to `^0.74.0` / `>=0.74.0 <0.75.0` — pi peer compat is tracked through the documented 0.74.x baseline, not through range pins.
- `resolveCodexAcpLaunch` now mirrors the Claude resolver pattern — `require.resolve("@zed-industries/codex-acp/package.json")` first, PATH `codex-acp` as fallback. Closes the three-backend equality gap noted in NEXT.md cross-repo follow-ups (`AGENTS.md` Hard Rule #7): operators no longer need a separate `pnpm add -g @zed-industries/codex-acp` step when `pi-shell-acp` is installed; the codex-acp bin already pinned in `dependencies` is used directly. `env:CODEX_ACP_COMMAND` override remains the highest-priority path; `source` field exposes `env:CODEX_ACP_COMMAND` / `package:@zed-industries/codex-acp` / `PATH:codex-acp` so the resolution path is observable. AGENTS.md "Runtime Dependencies" updated.

### Fixed

- **`files` allowlist leaked `.cast` artifacts into the npm tarball.** The initial Patch 1 entry included `docs/` as a directory, which pulled `*.cast` asciinema recordings into the tarball even though they are git-ignored (`*.cast` in `.gitignore`). Caught during reviewer cross-check of Phase 2 commits. Fix: replaced `docs/` with explicit entries for the three tracked gif assets the README actually references (`pi-shell-acp-demo.gif`, `pi-shell-acp-doomemacs.gif`, `pi-shell-acp-entwurf.gif`). Added `\.cast$` to the `check-pack` and `check-pack-install` forbidden patterns so the same drift cannot recur. Tarball drops from 43 → 41 files and ~390 kB smaller.

### Release invariant checklist (operator review at cut)

Phase 2 packaging-surface refactor closes the refactor axis; operational validation (NEXT.md 2.7 / 2.8 / 2.12) lives in a separate sprint. The automated half (`pnpm check` + `pnpm test:pack`) is green at the cut; this checklist is the human-eye half — operator review *before `npm publish`* (not before cut), so the boxes stay unchecked here and get walked through manually in the publish-prep round.

- [ ] **no Claude credentials in pi-shell-acp** — `grep -rE 'apiKey|token|secret|credential' acp-bridge.ts index.ts pi-extensions/` returns only env-var override names and the `.credentials.json` symlink passthrough in the Claude overlay. No bundled tokens, no fallback auth payload, no `package.json` dependency on any credential package.
- [ ] **no subscription resale** — README `## Install` lead paragraph and AGENTS.md "North Star" capability-dignity language are unchanged. The `npm pack` tarball ships no Claude / Anthropic OAuth payload (`tar -tf` output inspected against the publish-gate forbidden patterns).
- [ ] **no auth bypass** — backend spawn paths (`resolveClaudeAcpLaunch` / `resolveCodexAcpLaunch` / `resolveGeminiAcpLaunch`) launch the operator's native `claude` / `codex-acp` / `gemini` binary. The Claude overlay passes `.credentials.json` through as a symlink; Codex / Gemini rely on the binary's native auth flow. pi-shell-acp itself stores no auth state.
- [ ] **explicit local backend boundary** — every spawn site in `acp-bridge.ts` uses `node:child_process` `spawn` / `execFileSync` against a local executable (resolved via override → `require.resolve` → PATH). No `fetch` / `https.request` / network call to any non-pi backend; `engraving` and `pi-context-augment` carriers stay in-process.
- [ ] **fail-loud** — `McpServerConfigError`, `ModelSwitchLockedError`, `assertLegacyCompactionKnobUnset`, `isTranscriptPoisonError`, and the `check-sdk-surface` marker policy all in place. AGENTS.md "Crash, Don't Warn" honored. `check-sdk-surface` reports `0 cast(s) present, 0 OK + 0 DEBT — all annotated` at the current commit.
- [ ] **no hidden transcript restoration** — persisted session record schema (`parsePersistedSessionRecord`) carries only `{ sessionKey, acpSessionId, model, backend, capabilities }` plus identity fields — no transcript snapshot. `isTranscriptPoisonError` invalidates the persisted record when the backend rejects a resume; the session re-bootstraps fresh rather than silently masking the failure.
- [ ] **OpenClaw plugin separate package** — `plugins/openclaw/` ships as `@junghanacs/openclaw-pi-shell-acp` (separate npm name). Root `files` allowlist excludes `plugins/` (verified by the `^plugins/` forbidden pattern in `check-pack` and `check-pack-install`); `pnpm check:plugins` runs `tsc -p .` on each `plugins/*` workspace as an independent gate.

## 0.6.0 — 2026-05-17

Development release. Phase 1 feature-freeze closeout: OpenClaw plugin prerelease (Oracle daily-use verified) + Asymmetric Mitsein workflow surface (external MCP `entwurf_send`) shipped together ahead of the 2026-06-15 Anthropic third-party agent billing split. Phase 2/3 are refactor-only.

### Added

- **`entwurf_send` accepts identity-enhanced sender envelopes from external MCP hosts** (commit `5217e6c`). The pi-tools-bridge MCP surface previously required a pi session sender envelope from both `entwurf_self` and `entwurf_send`. The send path is now relaxed: when this MCP is wired into an external host (Claude Code, Codex, Gemini CLI), `entwurf_send` delivers into live pi sessions with `origin="external-mcp"` and `replyable=false`. The receive (`entwurf_self`) path still requires a pi session sender envelope — fail-loud, no silent coerce. `wants_reply=true` is rejected from external senders because there is no pi-session address to reply to. Receivers render `from: ... [external MCP]` and `sessionId: external-mcp (non-replyable)`. The asymmetry is by design: external hosts can push into pi, but receiving a reply requires being a pi session. See AGENTS.md "Entwurf Orchestration" and README "Entwurf" sections.

- **OpenClaw plugin (prerelease)** at `plugins/openclaw/`. New monorepo-lite sibling package — `pnpm-workspace.yaml` `packages: ["plugins/*"]`. Surfaces `pi-shell-acp/<model-id>` as a first-class OpenClaw provider; five curated models route through Claude / Codex / Gemini ACP backends via the upstream pi-shell-acp bridge:
  - `pi-shell-acp/claude-sonnet-4-6`, `pi-shell-acp/claude-opus-4-7`
  - `pi-shell-acp/gpt-5.4`, `pi-shell-acp/gpt-5.5`
  - `pi-shell-acp/gemini-3.1-pro-preview`

  Phase 1.8/1.9 verification on Oracle Docker (2026-05-15): `glg-b-bot` direct DM GREEN under both Sonnet and Opus, workspace/SOUL/USER/memory read, Telegram delivery (`sendMessage ok`), child pi clean exit/finalize. Manual install only — `openclaw plugins install <path> --dangerously-force-unsafe-install` until ClawHub registration. Not published to npm. Docker boundary, pi agent overlay (`~/.pi`) volume policies, Docker repro lab (`examples/docker-lab/`), and entwurf scope (`--no-tools --no-session --offline`) documented in `plugins/openclaw/README.md` and `AGENTS.md`. Plugin npm name reserved: `@junghanacs/openclaw-pi-shell-acp`.

- **Asymmetric Mitsein workflow pattern**. Documented operating shape between pi GPT힣 (Mattering, slow context-rich) and Claude Code Opus (fast effort surface) ahead of the 2026-06-15 Anthropic third-party agent billing split. tmux / copy-paste is the egress (operating-system tool, repo-zero); `entwurf_send` is the ingress (already implemented). External MCP caller patterns landed in `~/repos/gh/agent-config/home/AGENTS.md` "External MCP caller patterns" section. See NEXT.md "Immediate Priority — 2026-05-17 sprint" for the SSOT.

### Fixed

- Bumped `@agentclientprotocol/claude-agent-acp` from `0.32.0` to `0.33.1`, picking up upstream origin-aware handling for `task-notification` followups so autonomous background-task results no longer bleed into the user-turn lifecycle. First fix candidate for issue #16's background-notification / human-turn boundary failure.
- **ACP `entwurf_send` message visibility regression** (`e31823c`). Disabled the late `customMessage` promotion on the ACP path — the post-stream box arrived after sync tool calls, making the message look like a fresh send. In-stream `[tool:start]/[tool:done]` notice carries the visibility instead. Native and tool-result paths preserve the receive-side renderer + `ENTWURF_SENT_MESSAGE_TYPE` context filter. Re-entry condition: when pi gains an in-stream passive UI append/update path, this is reconsidered (parked as issue #8).

### Changed

- Bumped `@zed-industries/codex-acp` from `0.13.0` to `0.14.0`, aligning the bridge with the current Codex ACP release and its Codex 0.129 / exec-output handling updates.
- Reconfirmed the external `gemini-cli` `0.42.0` path-resolution invariant used by the Gemini overlay; pi-shell-acp still treats Gemini as a PATH runtime rather than a package dependency.
- README "External MCP wiring" split into two options: (A) `claude mcp add` registration (host-managed) vs (B) `~/.mcp.json` declarative (operator-managed). Both surface the same `pi-tools-bridge` entry. `entwurf_self` requires a pi session sender envelope; `entwurf_send` delivers from explicitly wired external MCP hosts, replyable only for pi-session senders.
- Root README gains an "Anthropic subscription billing" note framing the 2026-06-15 third-party agent billing split. `pi-shell-acp` respects that distinction — no bypass, no emulation — and preserves capability dignity across all three backends (invariants #7, #9, #10). The recommended runtime mix leans toward paths outside Anthropic's Agent SDK metering (Codex / Gemini); Claude remains a strong coding worker invoked when its quality is worth the credit cost.

### Plugin — `plugins/openclaw/` development trail (prerelease history, 2026-05-14 ~ 2026-05-16)

Documented here for replay; not part of the public 0.6.0 surface beyond the README/AGENTS files inside `plugins/openclaw/`.

- TS migration: `src/index.js` → `src/index.ts` (commit `6cea5c3`). Single-file TS stub; multi-file split (`src/provider.ts`, `src/stream/*`) is Phase 1.4 work.
- Compiled runtime shipped at `dist/` (commit `1c73569`). OpenClaw's `runtimeExtensions` slot consumes `dist/index.js`; source ships via `extensions: ["./src/index.ts"]`. `dist/` intentionally committed during prerelease (see `.gitignore` SSOT comment); transitions to `prepublishOnly: pnpm build` + `plugins/*/dist/` ignore at Phase 2 npm/ClawHub publish gate.
- Issue #17 outbound boundary hardening (`6cea5c3` fix, `918f5ef` ci guard, `1c73569` dist, `fa3b8f7` two-layer): outbound message boundary normalize + final-role guard + abnormal-flag fan-out + outbound text-only. DIAG 7-field probe (`finalRole`, `finalTextLen`, `finalTextHead`, `partialTextLen`, `partialOverridesFinal`, `abnormal`, `timeoutFired`) for telemetry. 1-stage streaming-off validation GREEN at release; 2-stage streaming-on validation and `[tool:trace]` inline resolution remain open follow-ups.
- Pre-install hardening (`340e58f`), Docker repro lab (`4e8237c`), Telegram delivery bridge shim (`98c8741` + `7071f4d` + `02c9c36`), curated catalog expansion to include `claude-opus-4-7` and `gpt-5.5` (`950e11b`), Docker install layers + three-backend auth (`169fa0b`), entwurf scope under invariant #9 (`635012b`), host-adapter pointer + auth boundary invariant in root (`b66e358`), Docker auth boundary R1/R3/R5/R6/R7 closeout (`61cfd4c`), install model split (prerelease vs self-contained) + pi agent overlay boundary (`8476104`).

### Docs

- AGENTS.md: "Entwurf Orchestration" section formalizes the sender envelope contract — `replyable=true` requires a pi sender envelope (`PI_AGENT_ID` / `PI_SESSION_ID`); `external-mcp` sender envelope is delivery-only.
- `plugins/openclaw/README.md`: Docker boundary section (in-container login default vs host passthrough advanced opt-in) + pi agent overlay (`~/.pi`) volume policies (4a persist runtime state vs 4b host overlay passthrough).
- NEXT.md realigned 2026-05-17: Phase 1 = 0.6.0 dev release (OpenClaw verification ✅ Phase 1.8/1.9 + Asymmetric Mitsein sprint); Phase 2/3 = refactor-only. Open question — endpoint envelope beyond pi sessions — and Design archive — receiver wake path via MCP mailbox + Claude Code `asyncRewake` — captured as design input for the operational-validation iteration.

### Known limitations (post-release operational validation continues)

- Asymmetric Mitsein workflow validation (Immediate Priority sprint Step 3a) is a 1-month fast iteration in progress at release time. Real-use trigger phrases, friction patterns, and frequency data are being captured ahead of `./run.sh smoke-external-mcp` automation (Step 3b) and demo materials (Step 3c). Step 3 work is **operational validation, not feature work** — 0.6.0 is the feature freeze; Step 3 outputs flow into Phase 2 4-axis verification.
- OpenClaw plugin remains manual-install-only; ClawHub registration is Phase 3.
- Plugin `mcpInjection`, `lockConflictPolicy`, `entwurfTargetsPath` configSchema keys are reserved (not yet wired); they land in Phase 1.4 ts refactor.
- Claude Code receiver wake path (MCP mailbox + `asyncRewake`) is design archive only — no implementation in 0.6.0. Real demand measurement happens during Step 3a; implementation considered only if friction accumulates.

## 0.5.0 — 2026-05-14

### Changed — pi-shell-acp session model lock

pi-shell-acp sessions are now locked to their starting model after the session starts. The lock has two layers:

- `pi-extensions/model-lock.ts` is the primary UX guard. Once a conversation is anchored (`agent_start`, resume/fork, reload with messages, or startup with existing messages), `model_select` transitions that touch `pi-shell-acp` are immediately reverted to the previous model. This covers `pi-shell-acp -> native`, `native -> pi-shell-acp`, and `pi-shell-acp/X -> pi-shell-acp/Y`. Native-to-native switching remains free.
- `ensureBridgeSession` is the bridge fallback/direct-call guard. If a live pi-shell-acp bridge session is asked to serve a different model, it throws `ModelSwitchLockedError` before closing the old ACP child, invalidating persisted state, or bootstrapping a new backend session.

Fresh startup/new sessions with no messages stay unlocked until the first prompt. Pre-turn model selector changes and CLI `--model` overrides are configuration, not violations. Resume/fork sessions lock immediately because their model identity was already anchored by the original session.

**Wire-level evidence the bridge fallback matters.** A live pi session that switched from Claude sonnet to Codex gpt-5.4 produced — *before* this change —

```text
[pi-shell-acp:shutdown]  closeRemote=true invalidatePersisted=true closedRemote=ok childExit=exited
[pi-shell-acp:bootstrap] path=new backend=codex acpSessionId=019e2481-...
```

The Claude backend was reaped and a fresh Codex backend bootstrapped, while pi JSONL still pointed at the original Sonnet conversation. With the bridge fallback active, the same direct/reuse-path flow produces

```text
[pi-shell-acp:model-switch] path=reuse outcome=locked
                            fromModel=claude-sonnet-4-6 toModel=gpt-5.4
                            reason=pi_shell_acp_session_locked_to_starting_model
```

— no `shutdown` line, no `bootstrap path=new`. The next prompt reuses the original ACP session (`path=reuse backend=claude`).

**This is not transcript-clean.** pi-core (`AgentSession.setModel()` in `packages/coding-agent/src/core/agent-session.ts`) mutates `agent.state.model` and calls `appendModelChange()` before the extension or provider boundary can refuse. Extension-side revert therefore leaves `model_change` as `X -> Y -> X`; bridge fallback leaves the attempted `X -> Y` record. A fully clean refusal requires a pi-core model-switch preflight/hook that this repo intentionally does not patch.

#### Surface changes

- `pi-extensions/model-lock.ts` + `package.json`
  - New extension-side model lock. It tracks when the session is anchored with `session_start`, `agent_start`, and existing message entries.
  - `startup` / `new` with no messages: unlocked until first prompt.
  - `resume` / `fork`: immediately locked.
  - `reload`: preserves an already locked module state or reconstructs lock from existing message entries.
  - Defensive fallback: if reading entries fails, lock rather than silently allowing a handoff.
  - Reentry guard prevents loops when the extension calls `pi.setModel(previousModel)` to revert.

- `acp-bridge.ts`
  - New exported `ModelSwitchLockedError` carrying `{ sessionKey, fromBackend, toBackend, fromModel, toModel }`.
  - `ModelSwitchOutcome` type: `"respawn"` → `"locked"`. The earlier `"respawn"` outcome is retired.
  - `ensureBridgeSession` reuse-path mismatch (previously: close + invalidate persisted + `startNewBridgeSession`) now logs `path=reuse outcome=locked reason=pi_shell_acp_session_locked_to_starting_model` and throws `ModelSwitchLockedError`.
  - The lock fires **above** `isSessionCompatible` so it catches same-backend AND cross-backend switches identically. An earlier prototype that lived inside the `existingCompatible` branch silently let cross-backend switches fall through to the incompatible-fallback and spawn a fresh session — the wire-level evidence above is exactly that hole.
  - `enforceRequestedSessionModel` (bootstrap path) is unchanged. Bootstrap is the lifetime starting point, not a mid-life switch.

- `run.sh`
  - New `check-model-lock` deterministic gate. `scripts/check-model-lock.ts` covers the 18-case policy matrix: four provider quadrants, same-model no-op, pre-turn free selection, post-`agent_start` lock, resume/fork immediate lock, reload with entries, reload preserving prior lock, and defensive lock on entry-read failure.
  - `smoke-model-switch` rewritten and generalized to four-argument form (`backend_a model_a backend_b model_b`). Three cases now run: within-backend Claude (sonnet → opus), within-backend Codex (gpt-5.4 → gpt-5.5), and cross-backend (Claude sonnet → Codex gpt-5.4). Pass criteria assert `outcome=locked`, exactly one `[pi-shell-acp:bootstrap] path=new backend=<backend_a>` line, `ModelSwitchLockedError instanceof` check, no `outcome=respawn` anywhere, no `path=new backend=<backend_b>` on cross-backend, and a successful post-refusal turn on the original session.

- Docs
  - AGENTS.md / README.md / VERIFY.md now describe the two-layer lock: extension-side revert as the normal path, bridge-side refusal as fallback, and the transcript-dirty caveat.

#### Scenarios covered by this guard

- Fresh startup/new before the first prompt: free. This preserves CLI `--model` override and pre-turn model selector configuration.
- After first prompt: any switch touching `pi-shell-acp` is reverted by the extension.
- Resume/fork: locked immediately, even before the next prompt.
- Reload: lock is preserved or reconstructed from existing message entries.
- Native-to-native switches: free.
- Direct bridge/reuse-path mismatch: refused by `ensureBridgeSession`. This is the fallback for direct calls or missing/failed extension coverage and prevents the silent-respawn hole.
- Bootstrap-time model resolution (`enforceRequestedSessionModel` after new/resume/load): unaffected — bootstrap is the lifetime starting point, not a mid-life switch.
- entwurf resume model override: already blocked separately by the Identity Preservation Rule (no `model` parameter on the entwurf resume surface).
- Different-process reopen of a saved JSONL under a different `--model`: out of scope by design. Saved persistent records do not carry `modelId`; lock applies only to live bridge sessions in this process.

#### Migration

- Operators who switched models mid-session by relying on the old respawn behavior must now open a new pi session for the new model once the current session is anchored. There is no in-process knob; this is the policy.
- Tooling that grepped for `outcome=respawn` on the model-switch log line must look for `outcome=locked` instead. The legacy outcome value is gone; any occurrence in fresh logs after the upgrade is a regression signal.

### Changed — 0.5.0 declaration: bridge does not implement compaction

The bridge no longer implements compaction. ACP backends compact natively; the pi session survives that. The bridge boundary stays explicit. This pays back the 0.4.x debt where both Claude (`DISABLE_AUTO_COMPACT=1` + `DISABLE_COMPACT=1`) and Codex (`-c model_auto_compact_token_limit=9223372036854775807`) auto-compaction were disabled at the bridge surface — a deliberate, temporary expedient while the bridge surface was being shaped, now removed.

| Layer | Default | Knob |
|---|---|---|
| pi JSONL compaction | blocked — pi-side summary does not reduce the backend transcript | `PI_SHELL_ACP_ALLOW_PI_COMPACTION=1` opts back in |
| backend-native compaction | **always allowed (no bridge knob)** | — configure the backend through its own native interface if you need to alter it; the bridge intentionally does not surface backend-specific compaction names |
| legacy `PI_SHELL_ACP_ALLOW_COMPACTION` | — | **fail-fast** at spawn intent with a next-action message pointing at `PI_SHELL_ACP_ALLOW_PI_COMPACTION` |

#### Surface changes

- `acp-bridge.ts`
  - Claude `bridgeEnvDefaults` no longer ships `DISABLE_AUTO_COMPACT` / `DISABLE_COMPACT` at all. The adapter carries identity-isolation pins only (`CLAUDE_CONFIG_DIR`).
  - Claude overlay `settings.json` now includes an explicit empty `hooks: {}` map. This keeps operator hooks hidden while matching the Claude SDK's configured-hooks shape; LIVE A/B probes showed that omitting the key made organic auto-compact consume the triggering turn for a meta-summary instead of answering the user prompt.
  - Codex `resolveCodexAcpLaunch` no longer emits `-c model_auto_compact_token_limit=9223372036854775807` at all. The bridge does not inject the threshold pin anywhere.
  - `resolveBridgeEnvDefaults(backend)` returns the adapter's identity-isolation pins as-is — no compaction option, no filtering. The earlier `disableBackendCompaction` option, the `isBackendCompactionDisabledByOperator()` reader, the `codexAutoCompactArgs()` helper, the `CODEX_DISABLE_AUTO_COMPACT_ARGS` constant, and the `COMPACTION_GUARD_ENV_KEYS` filter set are all removed.
  - `resolveAcpBackendLaunch` calls `assertLegacyCompactionKnobUnset()` on entry. Every spawn path (Claude, Codex, Gemini) crosses this surface, so the legacy single knob is rejected before any ACP child can launch on stale semantics. The error message points at `PI_SHELL_ACP_ALLOW_PI_COMPACTION` (the only remaining bridge knob) and tells the operator that backend-native compaction is always allowed — there is no longer a bridge knob to opt out.
  - Identity-isolation env (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `CODEX_SQLITE_HOME`, `GEMINI_CLI_HOME`, `GEMINI_SYSTEM_MD`) is unrelated to compaction and ships unconditionally — pinned at `check-backends` as a hard contract.

- `index.ts`
  - `session_before_compact` cancels by default and emits an honest message: "pi-side compact does not reduce the backend transcript; backend-native compaction is handled by the ACP backend itself; send `/compact` as a backend prompt or let the backend auto-compact". The `PI_SHELL_ACP_ALLOW_PI_COMPACTION=1` opt-back-in path is documented in the same message.

- `run.sh`
  - `check-backends` assertions inverted to the 0.5.0 contract: default Codex launch must NOT contain `model_auto_compact_token_limit`; default Claude env must NOT contain `DISABLE_AUTO_COMPACT`/`DISABLE_COMPACT`; legacy `PI_SHELL_ACP_ALLOW_COMPACTION=1` must throw at spawn intent. 137 assertions ok at this initial declaration. (See the *0.5.0 maintainer cleanup* entry below for the post-cleanup count.)
  - **Organic compact path closed for Claude (2026-05-13) and Codex (2026-05-14).** Initial Claude organic-context-full probes reproduced Claude SDK compaction on a saturated Sonnet session and showed the pi mapping survived, but also exposed a prompt-sacrifice failure when the Claude overlay omitted the `hooks` key. Adding `hooks: {}` fixed the turn shape: organic auto-compact now emits the compact status and then answers the triggering user prompt; explicit `/compact` still produces the expected compact-boundary turn and the next prompt answers from compacted context. Codex later passed both the lowered-threshold cheap stand-in and the real GPT-5.4 native-window saturation probe (`used` 244k → 84k, substantive compacting turn, sentinel preserved). The bridge still forwards backend output as-is and does not hydrate or rewrite transcript. Gemini context-pressure remains unverified.
  - New `./run.sh smoke-compaction-policy [--step=NN]` runner that wraps `scripts/compaction-policy-smoke.ts`. Originally six steps total (01/02/05 deterministic, 03/04/06 live); step 01 was retired in the later maintainer cleanup, leaving five steps with 02/05 forming the deterministic gate (no spawn, no network) and 03/04/06 the live release-evidence probe — under `LIVE=1` they drive a real ACP child per backend via `runEntwurfSync` + `runEntwurfResumeSync` (same infrastructure as cross-cwd-resume-smoke), plant a unique sentinel, send literal `/compact` as a backend prompt (NOT pi-host `/compact` — entwurf delivers the string as a normal user message into the ACP child), then send a recall prompt and assert the sentinel survives. Same `taskId` across all three turns, so persisted-mapping reuse is also covered. The probe uses a **dual-classifier** for backend-compact evidence: a text classifier over the (b)-turn reply (`compacted` / `summarized` / `context reduced`) AND a wire classifier over the bridge stderr's `[pi-shell-acp:usage]` lines (explicit `used=0` compact_boundary, or >=50% used drop). Pass requires positive evidence from EITHER classifier plus sentinel recall — survival alone is necessary but not sufficient. The dual shape exists because each backend signals compaction on a different ACP wire surface: codex-acp emits "Context compacted" in the assistant text, while claude-agent-acp suppresses the textual ack and posts an explicit `used=0` synthetic usage_update via the SDK's `compact_boundary` event (acp-agent.js:477-498). Text-only or wire-only would mis-judge them; both run together and either suffices. Cost a few cents per backend. This is NOT a product surface — there is no user-facing `/acp-compact` command; the probe is release evidence, not a feature. Step 06 (Gemini) is exploratory — Gemini ACP does not advertise `/compact` and the probe records the actual observation, not a release claim. Step 05 verifies the wrapper throw directly (5a `resolveAcpBackendLaunch`) and verifies at source level that the production spawn entry (`createBridgeProcess`) carries the same `assertLegacyCompactionKnobUnset()` guard — bypass between the two paths was a reviewer-found regression and the smoke now guards against it.

#### Migration

`PI_SHELL_ACP_ALLOW_COMPACTION=1` in 0.4.x meant two things at once: pi-side compact was allowed AND the backend guards were stripped (so backend-native compact could run). 0.5.0 keeps just the pi-side opt-in; backend-native compaction is now always allowed, so there is no second bridge knob.

- **0.4.x `PI_SHELL_ACP_ALLOW_COMPACTION=1` → 0.5.0 `PI_SHELL_ACP_ALLOW_PI_COMPACTION=1`.** Backend-native compaction is already allowed by default in 0.5.0 (no knob needed), so the only piece of the old broad semantic that still needs an opt-in is the pi-side one. Setting just `ALLOW_PI_COMPACTION=1` reproduces the full 0.4.x `ALLOW_COMPACTION=1` behavior.
- **If you need to alter a specific backend's auto-compaction**, configure that backend through its own native interface. The bridge intentionally does not surface backend-specific compaction names; historical recipes are preserved below only as restoration context.
- **Bridge will refuse to spawn while `PI_SHELL_ACP_ALLOW_COMPACTION=1` is still set.** The throw at spawn intent names `PI_SHELL_ACP_ALLOW_PI_COMPACTION` and explains that backend-native compaction is now bridge-knob-free. No silent acceptance.

#### Docs

- README §Compaction policy rewritten around the declaration; the backend-auto-compaction matrix row inverted; `model_auto_compact_token_limit` reference settings row updated; roadmap 0.5.0 line restated as declaration rather than guard split.
- AGENTS / README Claude overlay notes now call out the explicit empty `hooks: {}` shape: operator hooks remain hidden, but Claude SDK organic compaction gets the configured-empty settings form that keeps the triggering turn clean.
- VERIFY §1A.4 compaction-policy note rewritten; new `0.5.0 compaction policy` evidence row at L3 backed by `smoke-compaction-policy`; the 0.4.x long-session fact-retention baseline annotated as needing a 0.5.0 re-baseline; cross-vendor §13 paragraph adjusted to reflect that the no-excuse-for-forgetting framing is 0.4.x-specific.
- New `demo/compaction-policy-smoke/README.md` documenting the six-step surface (later updated to five — see the maintainer cleanup entry below).

### Changed — 0.5.0 maintainer cleanup: backend-specific compaction knob references retired

After the 0.5.0 declaration ("bridge does not implement compaction") was validated end-to-end on 2026-05-14 — Codex Pattern A pass (LIVE step 04, our automated probe; cross-confirmed by GLG-direct agent-shell + pi-shell-acp + codex-acp dialogue), Codex Pattern B cheap-induction pass (lowered threshold; native auto-compact path reachable end-to-end through the bridge with sentinel preserved across two consecutive organic compacts), and Codex Pattern B real-saturation pass (default GPT-5.4 threshold, `used` 244k → 84k, substantive compacting turn, sentinel preserved) — the maintainer pass removed the remaining places where pi-shell-acp's code and operator-facing docs named backend-specific compaction knobs.

**Reason — symmetry / consistency, not loss of knowledge.** Knowing the names is itself an awareness of backend internals and inconsistent with the bridge thesis. Even a negative assertion ("our argv must NOT contain X") presumes we know X exists, and an operator-facing recipe ("for Codex inline `-c X=…` via Y") teaches an asymmetric "how to disable compact per backend" hint that quietly re-anchors the bridge as something that owns the compaction concern. The 0.4.x→0.5.0 transition needed those strings while the policy was being shaped and verified. Once the policy is verified, they are debt.

#### Removed

- `scripts/compaction-policy-smoke.ts` step 01 (`spawn intent has no backend compaction guard`). The step's negative assertion enumerated `DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`, and `model_auto_compact_token_limit` directly. LIVE steps 03/04/06 cover the same regression surface — if the bridge ever re-injects a backend-side compaction guard, backend-native compaction stops working end-to-end and those live probes turn red. `ALL_STEPS` is now `["02","03","04","05","06"]`; REGISTRY drops the `"01"` entry; the import of `resolveBridgeEnvDefaults` (only used by step 01) is dropped from the smoke driver.
- `run.sh` `check-backends`: the explicit `assert.ok(!codexLaunch.args.some(arg => arg.includes('model_auto_compact_token_limit')), ...)` line was removed. The `deepEqual` against the expected argv list is the single source of truth — anything not in that expected list is not pinned. The Claude env assertions were also generalized from two exact compaction-name negative assertions to one identity-isolation key-set assertion, paired with the same key-set assertion for Codex. Count remains 136 after the maintainer cleanup.
- `acp-bridge.ts` inline comments at `resolveCodexAcpLaunch`, the codex overlay TOML header, and the codex env block: generalized from "bridge does not pin `model_auto_compact_token_limit`" to "bridge does not pin any codex-side compaction knob". Behavior unchanged; only the comment surface stopped naming codex internals.
- `README.md` "Operating-surface contract — Codex backend" table: the `model_auto_compact_token_limit` row was removed (the bridge does not pin it, and the row's only operator-facing content was a per-backend recipe — which is precisely what the cleanup retires).
- `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `VERIFY.md` compaction-policy paragraphs: the "for Claude `DISABLE_AUTO_COMPACT=1` … for Codex inline `-c model_auto_compact_token_limit=…` via `CODEX_ACP_COMMAND`" recipe collapsed to "configure that backend through its own native interface — the bridge intentionally does not surface backend-specific compaction names".
- `demo/compaction-policy-smoke/README.md`: "Six steps" → "Five steps" with an explicit retirement note for step 01; the backend-specific recipe paragraph generalized.

#### Restoration recipe

If a future need ever requires reintroducing per-backend guard awareness — for a regression test, for a release-evidence probe targeting a specific backend behavior, or because a backend changes its compaction semantics in a way that defeats live-probe detection — the historical source is *this CHANGELOG* itself. Earlier entries in this 0.5.0 release block (above) still name the exact backend-specific strings:

- `acp-bridge.ts` `resolveCodexAcpLaunch` "no longer emits `-c model_auto_compact_token_limit=9223372036854775807`" — codex argv guard.
- `check-backends` "default Codex launch must NOT contain `model_auto_compact_token_limit`; default Claude env must NOT contain `DISABLE_AUTO_COMPACT`/`DISABLE_COMPACT`" — both guard names.
- Migration "If you need a specific backend's auto-compaction off, export the backend's own native env/argv from your shell (`DISABLE_AUTO_COMPACT=1` for Claude; for Codex, inline `-c model_auto_compact_token_limit=…` via `CODEX_ACP_COMMAND`, or export `CODEX_HOME`)" — the recipe shape.

These history entries are intentionally left in place. The retirement is a thesis-alignment choice, not a loss of knowledge.

#### Not removed

- Identity-isolation env carriers (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `CODEX_SQLITE_HOME`, `GEMINI_CLI_HOME`, `GEMINI_SYSTEM_MD`) keep their per-backend names. They are unrelated to compaction; they are the bridge's identity/overlay surface, which is per-backend by design.
- LIVE step 04's `PI_ENTWURF_ACP_FOR_CODEX=1` env extras and the Codex/Claude probe-time references inside `scripts/compaction-policy-smoke.ts` remain — those are spawn-routing and live-probe surfaces, not bridge-side compaction policy.
- The 0.4.x→0.5.0 transition fact entries above stay as-is. They are the restoration source.

#### Evidence

- `demo/compaction-policy-smoke/probes/2026-05-14-codex-step04-A/` — Pattern A pass (explicit `/compact`; text + sentinel signal).
- `demo/compaction-policy-smoke/probes/2026-05-14-codex-B-threshold/` — Pattern B cheap stand-in (lowered-threshold organic auto-compact, sentinel preserved across two consecutive compacts, bridge mapping survives).
- `demo/compaction-policy-smoke/probes/2026-05-14-codex-B-saturation/` — Pattern B real native-window saturation (13 turns drove `used` 17k → 244k ≈ 94.5% on GPT-5.4; codex-rs native default `auto_compact_token_limit` fired organic auto-compact on turn 12, wire `used` 244089 → 84549 = 65% drop crossing the 50% classifier threshold; substantive 982-word answer in the compact turn; post-compact sentinel recall preserved; bridge mapping intact across all 13 turns). Codex GPT-5.4 native threshold ≈ 245k versus Claude Sonnet 4.6 ≈ 120k — same probe shape, honestly asymmetric backend defaults, same thesis.

**Gemini axis closed as an honest ACP asymmetry, not as a pass** (5/14, evidence triangulated across source, native CLI cross-check, and PM sibling review):

- **ACP command registry source**: `gemini-cli/packages/cli/src/acp/acpCommandHandler.ts:23-31` registers `memory, extensions, init, restore, about, help` only. `compress`/`compact`/`summarize` are NOT in the ACP registry. CLI body (`packages/cli/src/ui/commands/compressCommand.ts:10-13`) implements `compress` with aliases `summarize, compact` — but this is a TUI-only surface.
- **Organic compression on ACP path**: `gemini-cli/packages/core/src/core/client.ts:673-677` — every turn start calls `tryCompressChat(prompt_id, false)`; on success it yields `GeminiEventType.ChatCompressed`. But `gemini-cli/packages/cli/src/acp/acpSession.ts` switch has no `ChatCompressed` case → `default: break` silently drops the event. **Compression may happen, but the ACP wire never sees it.**
- **Context-pressure final surface**: if compression is insufficient, `ContextWindowWillOverflow` → `acpSession.ts:369-371` → `stopReason: 'max_tokens'`.
- **GLG direct CLI cross-check (5/14)**: Native Gemini CLI `/compress` reduced 93620 → 12936 tokens in a real session, confirming the CLI mechanism is real and works *outside* ACP. The asymmetry — `/compress` exists, but only outside ACP — is recorded as honest negative, not paved over.
- **PM sibling review (gpt-5.5 medium, 5/14)**: explicitly corrected an earlier "Gemini axis closed" framing to "closed as honest ACP asymmetry, not as a pass". The release-grade phrasing committed: *"Native Gemini CLI supports /compress (alias /compact, /summarize), but Gemini ACP does not expose that command. Organic compression may happen inside Gemini CLI, but ACP does not surface ChatCompressed on the wire today. If pressure remains, ACP surfaces max_tokens. pi-shell-acp does not inject backend-specific Gemini compression knobs."*
- **No LIVE saturation probe for Gemini**: Gemini Pro 1M+ window saturation is cost-disproportionate (Codex 258k probe was already at the upper end of cheap), and inducing compression by injecting Gemini-specific knobs (`compressionThreshold`, `contextManagement`) into the overlay would violate the 0.5.0 maintainer cleanup thesis (bridge does not surface backend-specific compaction names). Source + native CLI cross-check + PM review is the release-grade evidence chain here.
- **Operator-facing UX at `max_tokens`**: "Gemini ACP reached context pressure; native CLI has `/compress` but ACP does not expose it here. Start a fresh session or reduce context."

## 0.4.17 — 2026-05-12

### Fixed

- Drop the persisted `pi:<sessionId>` → `acpSessionId` bridge mapping when a resumed/loaded session's prompt fails with an Anthropic transcript-validity 400 — currently the `cache_control cannot be set for empty text blocks` and `API Error: 400 messages: text content blocks must be non-empty` surfaces. The poison failure is surfaced via `[pi-shell-acp:prompt-error] reason=transcript_poison`; the dead mapping is invalidated before any subsequent bootstrap, so the next bootstrap — even if the host re-enters within the same CLI invocation — uses `path=new` instead of the poisoned `acpSessionId`. The bridge does not force a same-turn retry of its own; recovery is just the existing `resume → load → new` ladder running against the now-empty persisted record. Fixes [#12](https://github.com/junghan0611/pi-shell-acp/issues/12).

### Changed

- Cold resume now treats the saved session header cwd as the authority and fails fast when neither that header cwd nor an explicit `options.cwd` override is available, instead of silently falling back to the resumer's `process.cwd()`. This prevents #9-style hydration loss from reappearing through the `runEntwurfResumeSync` and async `entwurf_resume` paths — both now refuse to spawn against the resumer's cwd. The `entwurf_resume` tool descriptions (MCP and pi-native) and `EntwurfResumeOptions.cwd` doc-comments are updated to call out the header-cwd authority explicitly; the `cwd` override remains as a debug/migration escape hatch that may forfeit backend continuity. Addresses the cwd-authority portion of [#10](https://github.com/junghan0611/pi-shell-acp/issues/10); the broader ontology RFC (peer handle, `contact_peer` verb, registry) stays parked.

## 0.4.16 — 2026-05-12

### Fixed

- Restored cross-cwd `entwurf_resume` backend hydration for ACP-routed siblings. The resume child now starts from the saved session header cwd when no explicit cwd override is supplied, preserving the existing `pi:<sessionId>` → `acpSessionId` bridge record instead of silently falling back to `newSession` and losing prior-turn memory. This fixes [#9](https://github.com/junghan0611/pi-shell-acp/issues/9) without promoting `taskId` to an identity carrier.

### Added

- Added a `verify-resume` Phase 2 cross-cwd fact-recall gate (`scripts/cross-cwd-resume-smoke.ts`) that plants a unique sentinel in a spawned sibling, resumes it from a different cwd through the MCP-shaped path, asserts recall, and captures child stderr through the existing `PI_ENTWURF_CHILD_STDERR_LOG` knob so future bootstrap fallthroughs are visible.
- Added a recorded entwurf demo GIF under `docs/assets/` and linked it from the README. The recording covers spawn, MCP `entwurf_resume` recall, and live `entwurf_send`, serving as visible end-to-end evidence for the #9 fix.

### Changed

- Expanded the TypeScript fence to a third `scripts/tsconfig.json` pass so strip-types verification scripts with explicit `.ts` imports are typechecked alongside the root and MCP configs.

## 0.4.15 — 2026-05-11

### Changed

- Align README / AGENTS 0.5.0 direction with NEXT.md: the next release is a compaction guard split / backend-native compaction escape hatch, not a caller-supplied recap hint slot or compact→new-session handoff.
- Promote ACP `entwurf_send` success echoes into first-class `[entwurf sent →]` UI messages using the Armin-style custom message + context-filter pattern, while keeping MCP sends on the MCP path and native sends on native tool rendering. Claude, Codex, and Gemini are covered through backend-specific ACP payload shapes.
- Remove remaining active `gpt-5.2` smoke/sentinel references in favor of `gpt-5.4`, add the `smoke-gemini` npm script, and refresh stale verification comments around triple-backend smoke and typecheck coverage.

### Fixed

- Prevent `entwurf-sent` UI echoes from leaking into LLM context in pi-shell-acp sessions that do not load `--entwurf-control`, and avoid empty late Gemini sent boxes when ACP tool arguments cannot be recovered.
- Make ACP `entwurf_send` detection robust across Claude/Codex/Gemini title shapes and permission-result labels rely on ACP option `kind` instead of backend-specific optionId substrings.
- Repair `scripts/session-messaging-smoke.sh` for the 0.4.14 `sessionId` schema and sender-envelope requirement so the 4-case matrix is self-contained again.

## 0.4.14 — 2026-05-11

### Changed — issue #7 surface unification (session-bridge retracted)

`session-bridge` is removed from the bundled 0.4.14 surface. `pi-shell-acp` now ships one MCP server only — `pi-tools-bridge` — and that server owns the full cross-session surface across Claude, Codex, and Gemini. The bundled tool set is now exactly five tools: `entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers`, `entwurf_self`.

This is a release-surface retraction, not a history rewrite. Older docs and baseline rows that mention the two-server / eight-tool shape remain as historical evidence of what 0.4.8–0.4.13 exposed. Current README / AGENTS / VERIFY / BASELINE language now distinguishes that history from the 0.4.14 live surface.

### Added — `entwurf_self` and sender-envelope transparency

`entwurf_self` absorbs the old self-introspection role. It returns the current session envelope — `sessionId`, `agentId`, `cwd`, `timestamp` — plus the active control-socket path, making the session's own identity objectively checkable through the same MCP surface that messaging uses.

`entwurf_send` now defaults to the same sender envelope on live peer messaging paths (MCP tool, slash command, in-process tool). The receiver renders who sent the message, from which cwd, and when. `agentId` is a single field (`pi-shell-acp/<model>`): school × model is one identity.

Startup one-shot CLI intentionally keeps sender info opt-in (`--entwurf-send-include-sender-info`). A short-lived sender process exits immediately after delivery, so attaching a reply-shaped envelope by default would falsely imply a live reply path.

### Fixed — structural `PI_SESSION_ID` / `PI_AGENT_ID` MCP env wiring

The sender envelope no longer depends on ambient `process.env` timing. `index.ts` forwards `options.sessionId` structurally into `EnsureBridgeSessionParams.piSessionId`; `acp-bridge.ts` injects `PI_SESSION_ID` and `PI_AGENT_ID` into both the backend child env and the `pi-tools-bridge` stdio MCP entry via `enrichMcpServersWithEnvelope()`. This closes the live ACP failure GPT caught in `./run.sh check-bridge`: Codex/Gemini MCP children were not guaranteed to inherit the session envelope unless the env array was populated explicitly.

### Changed — install/remove migration and Gemini MCP allowlist

`./run.sh install` now writes only `pi-tools-bridge` and prunes the legacy bundled `session-bridge` entry from older installs when it matches the repo-managed launcher path. `pi/settings.reference.json` now lists only `pi-tools-bridge`. The Gemini overlay's MCP allowlist is correspondingly narrowed to `mcp.allowed:["pi-tools-bridge"]`.

### Changed — model-switch reuse path now respawns

Reuse-path model mismatch no longer attempts in-place `unstable_setSessionModel`. Doing so would leave the already-spawned MCP child broadcasting stale `PI_AGENT_ID`. 0.4.14 therefore requires `path=reuse outcome=respawn fallback=new_session reason=pi_agent_id_env_requires_respawn`, followed by a fresh bridge spawn. Bootstrap enforcement after a fresh spawn remains unchanged.

### Changed — `wants_reply` etiquette marker (was `reply_requested`)

Peer-message reply hint renamed from `reply_requested` to `wants_reply` and re-scoped from a transport contract into a human-conversation etiquette marker — no wait, no polling, no delivery tracking. Default flipped from `true` to `false`: most peer messages (notifications, handoff packets, status pings) leave it unset, and the receiver render shows the `(wants reply)` badge only when the sender explicitly opts in. `parseSenderInfo` keeps a legacy `reply_requested` fallback so pre-rename transcripts still render correctly.

Receiver / sender direction is now visually unambiguous: `renderSessionMessage` uses `[entwurf received ⟵]` and the MCP `entwurf_send` tool result uses `[entwurf sent →]` (with `to:` / `from:` / `mode:` / preview block). Same transport, opposite arrows — end-to-end transcripts never blur who-said-what.

The receiving model is no longer told it is "obliged" to ack; that wording (carried in the old `entwurf_send` description) recreated a topology gate the carrier paragraph split in `pi-context-augment.ts` removed. The receiver decides based on the message body; `wants_reply` only surfaces intent.

### Verification

Release-local gates closed on the unified surface: `pnpm typecheck`, `mcp/pi-tools-bridge/test.sh`, `./run.sh check-mcp`, `./run.sh check-backends`, and `./run.sh check-bridge` all passed green. `check-bridge` now expects the 5-tool `pi-tools-bridge` surface and validates visibility + invocation on Claude, Codex, and Gemini.

## 0.4.13 — 2026-05-07

### Fixed — `skillPlugins` fail-fast contract (silent silent-drop closed)

`index.ts` now validates each `skillPlugins` entry at settings parse time. Each path must be absolute, point at an existing directory, and contain `.claude-plugin/plugin.json`; any violation throws `settingsConfigError` and aborts session bootstrap. The previous shape parsed the field as a string array and forwarded it directly into `claudeCodeOptions.plugins` (`acp-bridge.ts:1059`), so a typo, a relative path, or a directory missing the manifest was silently dropped by the Claude Agent SDK at session-spawn time — leaving the operator's skill invisible without a failure signal. That is exactly the "warnings make agents flail; broken tool state must surface as broken tool state" anti-pattern from §Code Principle, just landing one layer up the stack.

This is a bugfix, not a behavior change: the README:149 line "Explicit Claude plugin roots (`.claude-plugin/plugin.json` + `skills/*/SKILL.md`)" was already the documented contract, and §Code Principle was already the documented enforcement style. The bridge simply was not enforcing them. Operators with valid `skillPlugins` paths see no change. Operators with an invalid path now get a precise error at session start that names the missing piece, instead of a Claude session that boots without their skill.

Backend scoping: this validator runs at settings parse time regardless of the configured backend, but only `buildClaudeSessionMeta` actually consumes `skillPlugins`. Codex and Gemini ignore the field entirely — they expose skills through `~/.codex/skills/` and `~/.gemini/skills/` passthrough — so the stricter validation cannot regress those backends. It only stops a malformed Claude install from booting silently.

### Added — Skill install surface, owned by pi-shell-acp

- README "Custom Skills" section — first-class install guide that previously lived as a single table cell on the `skillPlugins` row of the settings reference. Covers minimum plugin shape, where to put the directory (with the explicit "do not put plugin roots under `~/.pi/agent/`" guard), settings shape, the new fail-fast contract, and the verification one-liner that points at VERIFY §1A `Q-SKILL-CALLABLE`.
- `pi/skill-plugin-example/` — self-contained minimum plugin layout the bridge accepts. Two files (`.claude-plugin/plugin.json` + `skills/hello/SKILL.md`) plus a directory shape; consumers copy and rename. Lives inside this repo so a first-time consumer never has to navigate to agent-config to find a working starting point.
- README backend capability matrix — split the single "Skill surface" row into two rows ("Skill install surface (declarative)" vs "Skill runtime callable surface"). The previous shape conflated `skillPlugins` (a Claude-only declarative install field) with the per-backend `~/.{backend}/skills/` passthrough (a runtime callable surface available on all three), which made it hard for a consumer to map their question onto the right mechanism.

### Changed — Reference consumer link tone (surface ownership tightened)

The README "Reference consumer" line previously read "for a real production setup — skills, prompts, themes on top of pi-shell-acp — see agent-config", which positioned agent-config as the install starting point and routed careful readers into agent-config's own directory conventions (especially `~/.pi/agent/claude-plugin/`) as if they were pi-shell-acp contracts. The line now points at the new `§Custom Skills` for the install surface and explicitly names agent-config's path layout as agent-config's own convention, not a bridge contract. Same link, repositioned authority.

This is a documentation-side correction of the surface ownership leak that had `skillPlugins` as a row in a settings table while the install narrative lived in a separate consumer repo.

## 0.4.12 — 2026-05-07

### Fixed — Entwurf registry recovery (oracle install regression root cause)

`pi-extensions/lib/entwurf-core.ts` `loadEntwurfTargets` no longer caches `EntwurfRegistryError`. The previous shape stored both successful registries and validation errors in a single slot, so a missing/parse-failed registry on first call poisoned every subsequent call from the same MCP/pi process — even after the operator repaired the file. The oracle install regression manifested exactly this way: a stale operator-copied `~/.pi/agent/entwurf-targets.json` produced an `EntwurfRegistryError`, and the cached error survived a symlink relink within the same Gemini session, so every entwurf spawn kept failing until session restart.

The cache is now positive-only with `mtime`-based invalidation. A successful registry is hot-cached for spawn performance, but operator edits to the file are picked up on the next `loadEntwurfTargets()` call without restarting pi or the MCP bridge.

### Changed — Fail-fast install policy for `entwurf-targets.json`

`run.sh ensure_agent_dir_symlinks` no longer silently preserves a stale `~/.pi/agent/entwurf-targets.json`. The v0.4.x policy treated any pre-existing file or differently-pointing symlink as an "operator override" and let install pass; that hid the oracle drift for several releases until the symptom surfaced as a sentinel failure.

The new policy honors only two explicit exits:

- `./run.sh setup:links --force` — back up a stale regular file (timestamped `.bak`) or relink a wrong symlink to the canonical `pi/entwurf-targets.json`.
- `PI_ENTWURF_TARGETS_PATH=/path/to/custom.json` — entwurf-core opts out of `~/.pi/agent/entwurf-targets.json` entirely, freeing the slot from policy.

A regular file byte-identical to the canonical (via `cmp`) is still treated as "already correct, silent". A symlink already pointing at the canonical is also silent. Drift in either form (stale regular file or symlink to a different path) prints a `diff` plus the two exits and exits 1, which propagates through `set -euo pipefail` to fail `install` / `setup` immediately rather than at smoke or sentinel time.

This is observably breaking for any operator running on a v0.4.x install with a drifted local file; the failure message names both repair paths explicitly.

### Added

- `./run.sh setup:links [--force]` — repair `~/.pi/agent/entwurf-targets.json` without re-running the full `setup` flow. The `EntwurfRegistryError` message has named this command since v0.4.x but the subcommand did not exist; this release closes that gap so the error guidance is now executable.

## 0.4.11 — 2026-05-07

### Gemini capability parity restored — skills + MCP advertise + invocation

The 0.4.8 / 0.4.9 baselines recorded a "Gemini MCP function-schema advertise asymmetry" and shipped it as documented backend behaviour. After re-reading upstream `gemini-cli` (`packages/core/src/config/config.ts` `maybeRegister` 3744–3768; `packages/cli/src/acp/acpSessionManager.ts` `newSessionConfig` 278–334; `packages/core/src/tools/mcp-client.ts` `connectAndDiscover` 1235), that reading is retracted: the asymmetry was overlay-induced, not upstream. The bridge — not the gemini binary — was hiding the advertise channels. Three layers of closure (skills advertise, MCP advertise, MCP invocation) had to open in sequence.

#### Layer 1 — Skills advertise

- **`tools.core` widens 7 → 8 keys.** `activate_skill` joins the read/write/edit/exec quartet (Read-class split as `read_file`/`list_directory`/`glob`/`grep_search`). Without it, gemini's `maybeRegister(ActivateSkillTool, ...)` skips registration entirely, the tool never reaches `getFunctionDeclarations`, and the model cannot see any skill — even when `~/.gemini/skills/` is fully populated. Same `tools.core` gate that already controls Read/Write/Edit/Exec, no special path.
- **`skills.enabled` flips `false` → `true`.** The earlier closure was over-tight: it disabled the skill discovery system entirely (`Config.skillsSupport && this.adminSkillsEnabled` 1502–1518), so even if the tool registered, `discoverSkills` never ran. With the toggle on, `SkillManager.discoverSkills` (skillManager.ts:54) reads operator skill SKILL.md entries through `Storage.getUserSkillsDir()`.
- **`skills` joins `GEMINI_OVERLAY_PASSTHROUGH`.** Same shape as Claude (`OVERLAY_PASSTHROUGH` already includes `skills`) and Codex (`OVERLAY_PASSTHROUGH_CODEX` already includes `skills`). Operator-curated agent skills under `~/.gemini/skills/` (typically a symlink to `~/repos/gh/agent-config/skills/` in this fleet) flow through into the overlay's `Storage.getUserSkillsDir()` resolution.

#### Layer 2 — MCP advertise

The diagnostic that finally closed this layer: admin.toml's `mcpName = ["pi-tools-bridge", "session-bridge"]` array shape failed gemini-cli's policy zod schema. The schema (`packages/core/src/policy/toml-loader.ts:39–70`) declares `mcpName: z.string().optional()` — strings only — while `toolName` accepts both strings and arrays. The array form silently failed `safeParse`, which (`toml-loader.ts` `validationResult.success === false` → `continue`) invalidates the **entire admin policy file**, leaving the priority 5.x admin tier empty. The deny-all rules in lower tiers then statically excluded every advertised MCP tool from `getFunctionDeclarations`.

- **`geminiOverlayAdminPolicyToml()` rewrites the MCP allow rule.** First attempt split per-server (`mcpName = "pi-tools-bridge"` + `mcpName = "session-bridge"`) so zod validation passed, advertise opened. The text was later collapsed into a single `mcpName = "*"` allow when invocation diagnostics (Layer 3) showed per-server matching was unreliable across paths; the per-server *whitelist* role moved one layer earlier (see Layer 3).
- **`mcp.excluded:["*"]` removed from overlay settings.** `isInSettingsList` (mcpServerEnablement.ts:65–88) does only exact case-insensitive name matches — no wildcards. The string `"*"` matched nothing real and was decorative, not load-bearing. The `mcp.allowed` whitelist is what actually scopes the surface (`canLoadServer` 122–137). Keeping the bogus entry would have implied a wildcard semantic the engine does not implement.
- **Admin policy was not a direct `PolicyEngine.check()` advertise gate, but advertise was still shaped by policy-driven exclusions.** `tool-registry.ts:647 getFunctionDeclarations` builds its surface through `getActiveTools()` → `config.getExcludeTools()` → `policyEngine.getExcludedTools(...)`, so the model-visible schema can still be narrowed indirectly by policy/exclusion state even though advertise does not run the invocation-time `PolicyEngine.check()` path. The 7-name allow widens to 8 (the `activate_skill` addition) for invoke-time symmetry with the registered surface.

Net effect after Layer 1+2: Gemini sessions see the same skill catalog as Claude/Codex sessions in the same overlay (e.g. `semantic-memory`, `denotecli`, `entwurf-peek`) and the same MCP tool function-schema entries (`mcp_pi-tools-bridge_entwurf`, `mcp_session-bridge_session_info`, …) that Claude and Codex have always seen. MCP advertise needs no patch on the gemini side: ACP `newSession.mcpServers` already merges into `settings.merged.mcpServers` (acpSessionManager.ts:285) and registers via `discoverMcpTools` → `toolRegistry.registerTool` (mcp-client.ts:1235), bypassing `tools.core`.

#### Layer 3 — MCP invocation

After Layer 2, advertise was green but the model's `entwurf_send` call returned `Tool execution denied by policy.` The `[PolicyEngine.check]` debug log showed `MATCHED rule: priority=5.05, decision=deny` — the catch-all DENY at admin priority 50 (= tier 5.x slot 50/1000 = 5.05) was winning. The priority-100 per-server `mcpName="<name>"` allow rules (5.10) somehow did not match in the invocation path. Walking `policy-engine.ts:577 check` vs `:872 getExcludedTools` showed both call the same `ruleMatches`, but the `serverName` resolution differed in shape between the two paths in observed runtime. Rather than chase the upstream nuance, the rule was simplified.

- **`mcpName = "*"` single allow rule** at priority 100. The per-server **whitelist role moves to settings.mcp.allowed**, which `canLoadServer` (mcp-client-manager.ts `isBlockedBySettings` 260–278) enforces *before* the policy engine sees the tool. Only `pi-tools-bridge` and `session-bridge` ever reach the policy layer; an admin-policy MCP whitelist would be a redundant second filter. The trade is a slightly more permissive admin tier in exchange for `getExcludedTools` and `check` agreeing on every MCP tool call. Layered defense is preserved (settings whitelist still gates connection), the advertise/invoke asymmetry is gone.
- **Verified end-to-end.** Layer 3 closure validated by:
  1. `check-bridge` Gemini line — visibility shows all 4 `mcp_pi-tools-bridge_*` tools, invocation calls `entwurf_send` against a bogus target and surfaces the expected missing-target boundary (not a generic policy denial).
  2. Live operator session — `entwurf` spawn + `entwurf_resume` against a sibling GPT, full sync conversation context preserved across the two MCP calls.

#### Verification surface

- **`check-bridge` adds the Gemini line** (`validate_pi_tools_bridge_backend "gemini" "pi-shell-acp/gemini-3.1-pro-preview"`, conditional on `gemini` on PATH, mirroring `smoke-all`'s skip pattern). The `validate_pi_tools_bridge_backend` body already covers visibility (model self-report of `pi-tools-bridge` callable schema entries) + invocation (real `entwurf_send` call to a bogus target). With Gemini added, the same gate that proved Claude / Codex MCP parity now proves Gemini MCP parity automatically on every release. The earlier baselines could not have caught this regression because the gate did not exist for the Gemini backend; that gap is closed.
- **`check-backends` 134 → 137 assertions.** One swap (`mcp.excluded:["*"]` deepEqual → `'excluded' not in mcp` absence), three additions (skills passthrough seed/symlink/SKILL.md reachability), reflecting the new overlay shape.

#### Documentation surface

- **README, AGENTS.md, BASELINE.md, VERIFY.md retract the asymmetry framing.** The 0.4.8 / 0.4.9 BASELINE PASS rows now read as "closure was tighter than capability dignity required"; the closure remains valid for *operator* settings/memory/history isolation, but the skill + MCP channels are reopened for the pi-injected surface. Hard Rule #9 widens: the tool/MCP/skill surface row gains the symmetric passthrough + advertise wording. VERIFY claim row L1 → L4 (direct gemini comparison + bridged interview).

## 0.4.10 — 2026-05-06

### Changed

- Added `gemini-3.1-pro-preview` as the only curated pi-shell-acp Gemini ACP model and explicit-only Entwurf target. Flash is intentionally removed from the curated surface; 3.1 Pro is the subscription-backed high-quality Gemini ACP route.
- Hardened `.pi/prompts/make-release.md` release-note extraction: replaced the fragile `awk` range snippet with a small Python block keyed by `VERSION="$ARGUMENTS"`, so slash-command release runs do not fail with empty `--notes-file` output on a valid `## <version> — YYYY-MM-DD` section.
- Entwurf Codex surface narrowed to `gpt-5.4` + `gpt-5.5` only. `DEFAULT_ENTWURF_MODEL` is now `openai-codex/gpt-5.4`, and the target registry drops `gpt-5.2` / `gpt-5.4-mini` on both the native `openai-codex` and ACP-routed `pi-shell-acp` paths. This makes the natural no-model default match current policy instead of relying on callers to remember a preferred model.

## 0.4.9 — 2026-05-06

### L5 — Memory containment (gemini)

The 0.4.8 surface-isolation matrix closed five Gemini channels (native body, operator memory path, tool surface, GEMINI.md hierarchical discovery, MCP whitelist). 0.4.9 closes a sixth — **memory persistence**. pi-shell-acp is the canonical memory authority on the pi side (semantic-memory + Denote llmlog); no backend may run a parallel memory layer that survives across sessions. The Claude and Codex sides already enforce this (Claude via `CLAUDE_CONFIG_DIR` overlay + `disallowedTools` + `skillPlugins:[]`, Codex via `-c memories.{generate,use}_memories=false` + `-c history.persistence="none"` + `-c features.memories=false`). 0.4.9 adds the matching closure for Gemini.

- **`experimental.memoryV2:false` + `experimental.autoMemory:false` pinned in overlay `settings.json`.** memoryV2 is Gemini's "edit `GEMINI.md` / `MEMORY.md` directly via `edit/write_file`" mode (default `true` upstream); autoMemory is the background extraction agent that writes `.patch` files into a project memory inbox (default `false` upstream). The `GEMINI_SYSTEM_MD` override already replaces Gemini's system prompt body, so memoryV2's prompt steering never reaches the model — but the explicit pin holds even if the override path ever breaks (defense in depth). The overlay `settings.json` closure widens from 14 keys to 16.
- **`<configDir>/{tmp,history,projects}/` swept at every spawn.** `ensureGeminiConfigOverlay` now unconditionally `rmSync`s these three subtrees and recreates them empty, so any `tmp/<slug>/memory/MEMORY.md`, `tmp/<slug>/.inbox/<kind>/*.patch`, command-history subtree, or `projects/` directory content written by a previous gemini session does not carry. The binary-owned `<configDir>/projects.json` file is a separate overlay-private project map and is not part of this sweep; the operator's native `~/.gemini/projects.json` still never flows through. The L4 closure (`context.fileName` sentinel + `memoryBoundaryMarkers:[]`) already keeps Gemini from *reading* memory files; the L5 sweep is filesystem hygiene + defense-in-depth in case L4 ever breaks. The constant is renamed from `GEMINI_OVERLAY_EMPTY_DIRS` to `GEMINI_OVERLAY_SWEPT_DIRS` to reflect the stronger contract.
- **Root-level `<configDir>/GEMINI.md` and `<configDir>/MEMORY.md` swept by the existing stale-entry cleanup.** Neither name is on `GEMINI_OVERLAY_BINARY_OWNED`, so the cleanup loop's fall-through `rmSync` removes them at every spawn. The model can still try to write these files within a session via `write_file`, but they cannot survive into the next one.
- **`check-backends` 124 → 134 assertions.** Two assertions for the new `experimental.{memoryV2,autoMemory}` keys; five for the L5 sweep behaviour (pre-seed `tmp/<slug>/memory/MEMORY.md`, autoMemory inbox patch, root `GEMINI.md`, root `MEMORY.md` → confirm none survive the next `ensureGeminiConfigOverlay` call); three for the engraving substitution defuse below.

### Engraving substitution defuse (gemini)

Recent gemini-cli (post 0.42-nightly, [`packages/core/src/prompts/utils.ts`](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/prompts/utils.ts) `applySubstitutions`) walks the `GEMINI_SYSTEM_MD` override file and rewrites `${AgentSkills}`, `${SubAgents}`, `${AvailableTools}`, and `${<toolName>_ToolName}` with their runtime values. The substitution is intended for gemini-shipped templates, but the same pass runs over the operator-supplied override file — so any `${...}` literal inside an engraving (e.g. a shell example) silently mutates on the gemini backend only, while landing verbatim on Claude (`_meta.systemPrompt`) and Codex (`-c developer_instructions`).

- `defuseGeminiSubstitutions` slides the `$` and `{` apart with a zero-width space (U+200B) before writing `system.md`. Every substitution regex misses; the model still reads the same visual string, but Gemini's carrier bytes are intentionally not byte-identical to Claude/Codex for affected `${...}` literals. Restores the cross-backend invariant that the same engraving is not semantically interpolated differently on Gemini. Documented inline at the function definition with the gemini-cli source pointer.

### Internal — Backend dependency bumps

- **`@agentclientprotocol/claude-agent-acp` 0.31.4 → 0.32.0.** SDK pin stays at `@agentclientprotocol/sdk@0.21.0`; transitive `@anthropic-ai/claude-agent-sdk` advances 0.2.121 → 0.2.126. Visible bridge-side change: Claude session updates may now carry `_meta._claude/origin` on `usage_update` notifications when the underlying message is a task-notification followup (autonomous work triggered by a system message rather than the user prompt). The bridge's event-mapper passes `_meta` through unchanged, so the new field flows to pi without code change. Internal `toolUpdateFromEditToolResponse` → `toolUpdateFromDiffToolResponse` rename is consumed inside claude-agent-acp; bridge does not import the symbol.
- **`@zed-industries/codex-acp` 0.12.0 → 0.13.0.** Codex 0.124 → 0.128.0. Rust agent-client-protocol pin stays at `=0.11.1` (same as Zed and the TS SDK 0.21.0 wire). codex-acp internals shifted to async `AuthManager` + `EnvironmentManager` and added a `ThreadGoalUpdated` event — emitted as plain agent text via `client.send_agent_text("Goal updated (active): …")` and forwarded by the bridge as ordinary text. Mode IDs (`read-only` / `auto` / `full-access`) and the `-c features.<key>=false` gating surface are unchanged.
- **devDeps `@mariozechner/pi-{ai,coding-agent,tui}` 0.70.2 → 0.73.0.** Aligns the typecheck fence with the version operators are running. pi-mono 0.71.0 removed the built-in `gemini-cli` *provider* (Token Plan API route), not the `google` API source — `getModels("google")` still ships `gemini-3-flash-preview` (1,048,576 context, 65,536 maxTokens), so `check-models` assertions hold. ExtensionAPI gained `getEditorComponent()` accessor + `thinking_level_select` event + `ProviderConfig.name` + `MessageEndEventResult` — all additive; the bridge does not subscribe to any of these surfaces.

### Documentation

- AGENTS.md Hard Rule #9 widens the surface-isolation matrix to include L5 — Memory containment (per backend), and re-states pi-shell-acp's role as the canonical memory authority.
- Comment drift fix in `acp-bridge.ts`: the placeholder note "`if (systemMdResolution.value)` always takes the override branch" now reflects the upstream `value && !isDisabled` semantic gemini-cli adopted along with the prompt-provider refactor.

### Internal — Release flow standardization

- **Removed `scripts/release.sh`** and the `package.json` `release` script entry. The `--notes-from-tag --title v<version>` pattern paired with lightweight tags was the root cause of v0.4.7 / v0.4.6 / v0.4.1 / v0.3.x shipping with empty release bodies and bare-version titles. The script produced lightweight tags (no annotation message), then `--notes-from-tag` rendered an empty body — consistent low-quality releases by design. Removed rather than patched.
- **`.pi/prompts/make-release.md` rewritten** as a self-contained release procedure. Pre-flight 0–7 (argument shape / clean tree / tag absent / CHANGELOG section / version match / `pnpm check` / `gh` auth + repo/permission consistency / push dry-run) → tag → push → agenda stamp (`pi:release:` tag, release-page link) → CHANGELOG section extracted as `--notes-file` → `gh release create --title "v<version>" --notes-file …` → `gh release view` verify → Google Chat notify → temp-file cleanup. Each step's bash block restates `VERSION="$ARGUMENTS"` and re-derives `REMOTE`/`REPO_URL`/`REPO_NAME`/`REPO_TAG` so slash-command bash invocations split across the agent do not silently drop variables. Title is fixed to `v<version>`; theme lives in the CHANGELOG body's first H3, not the title. `npm publish` and downstream consumer bumps (agent-config 4-file pin) are explicitly out of scope.

## 0.4.8 — 2026-05-03

### Added

- **Gemini CLI as a third ACP backend.** `gemini --acp` joins Claude Code and Codex on the bridge surface. Two reasons converged: pi-mono v0.71.0 removed its built-in Google Gemini provider (operators were told to switch to another provider), and Gemini CLI promoted its `--acp` flag from `--experimental-acp` to the supported surface. The bridge picks the path back up rather than losing Gemini access entirely or routing through API-key/Vertex provider paths. Set `backend: "gemini"` in `piShellAcpProvider`, or pick `pi-shell-acp/gemini-3-flash-preview` and inference will route to the gemini adapter.
- **`run.sh smoke-gemini`** runs the new explicit Gemini smoke (initialize / newSession / single prompt round-trip / shutdown). `smoke-all` now invokes it after Claude and Codex when `gemini` is on PATH; if not, smoke-all skips with a clear notice rather than failing — operators who don't use the gemini backend stay green. The PATH dependency is documented (`pnpm add -g @google/gemini-cli`); pi-shell-acp does not bundle a separate `*-acp` server package for Gemini because the gemini CLI binary itself is the ACP server.
- **`GEMINI_ACP_COMMAND`** environment override mirrors `CLAUDE_AGENT_ACP_COMMAND` and `CODEX_ACP_COMMAND`. Operators can run `gemini --acp --debug` or wrap the launch in a script without touching settings.json.
- **One curated Gemini model**: `gemini-3-flash-preview`, sourced from pi-ai's `google` registry (1,048,576 context). This is what `gemini --acp` defaults to today — bootstrap logs show `fromModel=gemini-3-flash-preview` before the bridge calls `unstable_setSessionModel` to apply the requested model. 2.5 / 3.1 / lite / numbered-snapshot variants are intentionally excluded from the curated surface; non-curated ids still route to the gemini backend through the broader pi-ai registry fallback in `inferBackendFromModel`.
- **One entwurf target** under `provider: "pi-shell-acp"`: `gemini-3-flash-preview`, `explicitOnly: true`. There is no native pi google provider to disambiguate against on 0.4.8, but the flag keeps the policy stable if pi reintroduces one.

### Surface isolation — closed channels (baseline 2026-05-03)

Earlier 2026-05-01 baseline ran with the gemini adapter ACP-connected but not pi-surface-isolated. 0.4.8 ships the closure on five channels, each with both code-level (synthetic test in `check-backends`) and model-side (operator baseline interview) evidence.

- **L1 — native system body.** `GEMINI_SYSTEM_MD = <overlay-home>/.gemini/system.md` replaces gemini-cli's bundled "Instruction and Memory Files" body. The overlay always appends a carrier-isolation canary line (`GEMINI_SYSTEM_MD_CANARY_PISHELLACP_V1`); a baseline operator can ask the model to quote it (and only it) to confirm the carrier reaches the same prompt slot Claude reaches via `_meta.systemPrompt` and Codex reaches via `-c developer_instructions`. 2026-05-03 baseline: model classified the canary string under "actual system prompt (Developer Instruction)", confirming the file replaces native body rather than landing on a different surface.
- **L2 — operator memory path.** `GEMINI_CLI_HOME` redirects gemini's `homedir()` so the binary resolves `Storage.getGlobalGeminiDir()` to `<overlay-home>/.gemini/` instead of `~/.gemini/`. Earlier baseline read `~/.gemini/tmp/junghan/memory/MEMORY.md` as a username leak; the substring `junghan` was actually a `Storage.getProjectIdentifier()` slug of the `/home/junghan` cwd, not a username field — the closure handles both readings, and the operator's real `~/.gemini/{history, projects.json, tmp/<slug>/memory, trustedFolders.json, settings.json}` is now never read. 2026-05-03 baseline: model reports overlay tmp paths (`<overlay-home>/.gemini/tmp/<cwd-slug>`), not the operator's `~/.gemini/` tree.
- **L3 — tool surface.** `tools.core` 7-name allow + `--admin-policy` (priority tier 5.x — beats Default / Extension / Workspace / User policies) deny-all + same 7-name allow. The 7 names map to 4 capability classes (Read = `read_file` / `list_directory` / `glob` / `grep_search`; Write = `write_file`; Edit = `replace`; Exec = `run_shell_command`) — same operating-surface boundary as Claude `Read/Bash/Edit/Write`, with the read-class split admitted honestly so the model does not see "visible but deny'd" tools. 2026-05-03 baseline: model invoked all 4 read-class tools without any `denied by admin policy` response.
- **L4 — `GEMINI.md` hierarchical discovery.** `context.fileName` set to a sentinel (`__pi_shell_acp_disabled_context__`), `memoryBoundaryMarkers: []` to kill parent traversal, `includeDirectoryTree: false` to drop cwd dir-tree auto-attach. 2026-05-03 baseline: model reports no `GEMINI.md` awareness in cwd, parent chain, or home.
- **MCP whitelist.** `mcp.allowed: [pi-tools-bridge, session-bridge]` + `mcp.excluded: ["*"]` keep gemini-side ambient MCPs (operator-configured stdio in `~/.gemini/settings.json`, http/sse in extensions) from surfacing. 2026-05-03 baseline: model enumerates only the two bridge servers.

### Documented asymmetry — MCP function-schema advertise

Gemini ACP accepts the bridge's stdio MCP servers via `mcpServers`, but does **not** register them as model-visible function-schema entries the way Claude and Codex do. In the 2026-05-03 baseline, the model described MCP / custom-tool access as shell-mediated (`run_shell_command`) rather than direct function calls. This is recorded as an observed Gemini ACP surface asymmetry, not something the overlay can close. Operators on the gemini backend should not expect entwurf / semantic-memory / etc. to appear as `mcp__<server>__<tool>` function entries. Recorded in the README backend-capability matrix.

### Internal — Backend adapter shape

- **`AcpBackend` widened to `"claude" | "codex" | "gemini"`** with a third entry in `ACP_BACKEND_ADAPTERS`. The gemini adapter sets `buildSessionMeta` to `() => undefined` (Gemini ACP exposes no `_meta.systemPrompt`), uses the same `[{ type: "text", text }]` first-user augment as Claude and Codex, and pins `bridgeEnvDefaults` to `{ GEMINI_CLI_HOME: <overlay-home>/, GEMINI_SYSTEM_MD: <overlay-home>/.gemini/system.md }`. Both env pins survive `PI_SHELL_ACP_ALLOW_COMPACTION=1` — they are operator-config-isolation invariants, not policy choices.
- **Engraving delivery for the gemini backend** is via `GEMINI_SYSTEM_MD = <overlay-home>/.gemini/system.md`, written at every spawn by `ensureGeminiConfigOverlay()`. The file equivalent of Claude's `_meta.systemPrompt = <string>` and Codex's `-c developer_instructions="<...>"`. The carrier-isolation canary line keeps the file non-empty in the no-engraving placeholder branch (so `getCoreSystemPrompt`'s `if (systemMdResolution.value)` always takes the override branch) and gives baseline a deterministic quote target.
- **Session compatibility.** `geminiSystemPromptText` joins `systemPromptAppend` and `codexDeveloperInstructions` in `isSessionCompatible` / `isPersistedSessionCompatible` — changing the engraving on the gemini backend forces a fresh spawn, since the carrier is materialized at spawn time as a file.
- **`PI_SHELL_ACP_GEMINI_CONTEXT=<int>`** operator override mirrors `PI_SHELL_ACP_CLAUDE_CONTEXT`. Default surface exposes the full registry capacity (1,048,576 for `gemini-3-flash-preview`); operators inline a tighter ceiling for cost / context-management when needed.
- **`check-backends` 110 → 124 assertions.** Gemini launch resolution (PATH path + `GEMINI_ACP_COMMAND` override appending `--admin-policy`), env pins (`GEMINI_CLI_HOME`, `GEMINI_SYSTEM_MD`), absence of session-meta carrier, settings.json shape (14 closure keys), admin-policy 7-name read-class allow, system.md canary in both engraving and no-engraving branches, overlay-private empty dirs, symlink passthrough whitelist, idempotence.
- **`check-models`** widens the curated allowlist to seven ids (Claude 2 + Codex 4 + Gemini 1) and adds context-window assertions for the gemini line against pi-ai's `google` source.

### Notes

- **No subscription-billing parity claim.** Gemini ACP supports `oauth-personal` ("Log in with Google"), `gemini-api-key`, `vertex-ai`, and `gateway` auth methods. Whether ACP-mode quota under `oauth-personal` matches ordinary `gemini` CLI mode is a separate verification axis (cf. google-gemini/gemini-cli#20421); pi-shell-acp 0.4.8 does not assert parity.
- **No `resumeSession` advertisement from Gemini.** Gemini ACP advertises `loadSession: true` only — the bridge's existing `resume > load > new` fallback handles this without code changes. Continuity goes through `loadSession` for Gemini, identical to Codex.

## 0.4.7 — 2026-04-30

### Added

- **Added optional Emacs agent socket support.** `--emacs-agent-socket <name>` tells pi-shell-acp which Emacs server socket an agent should use for Emacs operations. The value is propagated to ACP children as `PI_EMACS_AGENT_SOCKET`, added to the first-user pi context augment, and folded into the bridge config signature so switching between terminal (`server`) and Emacs-internal (`pi`) sessions cannot accidentally reuse a child with stale socket context.
- **Documented Doom Emacs / pi-coding-agent usage.** README now shows the Emacs frontend shape `(setq pi-coding-agent-extra-args '("--entwurf-control" "--emacs-agent-socket" "pi"))` and includes a Doom Emacs demo GIF.

## 0.4.6 — 2026-04-30

### Fixed

- **Restored Hard Rule #2 (`resume > load > new`) on the resume path.** Since SDK 0.20.0 promoted `resumeSession` out of the `unstable_*` namespace, every call to `(session.connection as any).unstable_resumeSession({...})` had thrown `TypeError: ... is not a function`, been silently caught by the bootstrap fallback, and routed every session to `loadSession` instead. Capability check still advertised resume support, but Hard Rule #2 was quietly violated. The bridge now calls the typed `resumeSession` / `closeSession` methods directly. This matters because claude-agent-acp's `loadSession` replays the entire session JSONL back to the bridge as `sessionUpdate` notifications which the bridge discards under Hard Rule #8 (no transcript hydration); resume skips the replay entirely. The longer the session, the larger the wasted bootstrap; openclaw-style long-running sessions would have made the cost user-visible.
- **Dropped five redundant `as any` casts on typed SDK methods.** `prompt`, `cancel`, and `unstable_setSessionModel` (×2) on `ClientSideConnection` are typed by the SDK; the casts were leftover from when those methods were experimental. With strict mode on, dropping them means tsc will fail on the next SDK rename instead of shipping a dead call.

### Changed

- **Bumped ACP SDK pins.** `@agentclientprotocol/claude-agent-acp` 0.31.0 → 0.31.4 and `@agentclientprotocol/sdk` 0.20.0 → 0.21.0. Tracks the upstream stable surface and the `@anthropic-ai/claude-agent-sdk` 0.2.121 transitive.

### Internal — Static gate against ACP SDK casts

- **New `./run.sh check-sdk-surface` (and `pnpm check-sdk-surface`).** Static awk gate over `acp-bridge.ts` that requires every `(connection as any)` cast to have a `SDK_CAST_OK` (permanent gap) or `SDK_CAST_DEBT` (tracked for removal) marker on the same line or the immediately preceding line. Wired into `pnpm check` and the husky pre-commit hook. The 0.20.0 `unstable_resumeSession` rename would have been caught by tsc if the original code hadn't used `as any`; this gate makes the bypass visible at code-review time so the next class-of-bug doesn't ship silently.
- **AGENTS.md Hard Rule #10 documents the principle.** "SDK surface calls must use the typed connection." Markers are required, not optional. The fix is structural, not vigilance.

### Internal — Strict typing fence

- **Flipped root tsconfig `strict: false` → `strict: true`.** First run surfaced 24 errors: 23 implicit-any warnings on `registerTool` executor callbacks plus one real `RpcResponse | null` narrowing bug in `sendRpcCommand` that strict-false had been hiding. Pi-shell-acp tools are called by other agents that will silently accept malformed shapes; strict-on is the right floor.
- **Extended the `EntwurfSendParams` pattern to four more sites.** `entwurf`, `entwurf_status`, `entwurf_resume`, `entwurf_peers` now each define a local params type alongside their schema and type the `execute` signature explicitly (`_toolCallId: string`, `params: <Specific>`, `_signal: AbortSignal | undefined`, `_onUpdate: AgentToolUpdateCallback<unknown> | undefined`, `_ctx: ExtensionContext`). TS2589 on `pi.registerTool`'s generic keeps schema-to-type inference blocked; explicit annotation is the workaround.
- **Typed `entwurf_send`'s `renderResult`** with `AgentToolResult<unknown>`, `ToolRenderResultOptions`, and the same theme shape its sibling `renderCall` already used.
- **Dropped two `(params as { provider?: string }).provider` runtime casts** in `entwurf`'s execute body — `EntwurfParams` declares `provider` directly.
- **Fixed `sendRpcCommand`'s `RpcResponse | null` narrowing.** Resolves directly with the just-received message on the no-event path; only the event-waiting branch stashes the response. Behavior preserved; the type now narrows correctly.
- **Brought `pi-extensions/entwurf-control.ts` into the biome formatter fence.** Removed the `!pi-extensions/entwurf-control.ts` exclude from `biome.json`. Auto-fix surface was tiny (import organize + format); three dead suppression comments (`biome-ignore` / `eslint-disable` for `noExplicitAny`, which is project-wide off) were removed.

### Internal — Single-source `protocol.js`

- **Deleted `protocol.ts`; `protocol.js` is now the only source for the shared `<project-context` wire marker.** The duplication carried no sync invariant — an export added to one would have silently missed the other. With only one string-literal export, JSDoc types are unnecessary; `.js` can serve as the single source.
- **Added `allowJs: true` to root tsconfig** so `protocol.js` enters the tsc program and is emitted through `check-models`. `checkJs` is intentionally left off — the file's surface is a single string-literal export with nothing for strict-check to gain.

### Internal — fence consolidation

Every `.ts` source file in the repo is now reached by `pnpm typecheck`. Previously two surfaces lived outside the fence:

- `pi-extensions/entwurf-control.ts` was excluded from the root tsconfig. The exclude hid type drift introduced by the 0.5.0 sessionId-only refactor: residual `sessionName` / `session.name` reads in `renderCall`, `entwurf_peers` description, and peers output; `pi.on("session_switch", ...)` and `pi.on("session_fork", ...)` handlers registered against event names that pi-coding-agent 0.70.x does not expose (`session_start{reason: "fork" | "new" | "resume"}` covers them); a renderer reading `result.isError` against an `AgentToolResult<T>` type that does not declare it (the framework spreads it onto the result at runtime); a typebox-version mismatch (`@sinclair/typebox` 0.34 mixed with pi-coding-agent's typebox 1.x via `StringEnum`) silently widening parameters to `unknown`; a dead `getMessagesSinceLastPrompt` helper.
- `mcp/` was excluded wholesale. Both bridges run via `node --experimental-strip-types` and were never type-checked anywhere. Inside, `mcp/session-bridge/src/index.ts` still resolved targets via `<sessionName>.alias` symlinks and a name scan — the same alias surface that `entwurf-control.ts` declared dead since 0.5.0, but on a different physical directory and a different audience (humans operating Claude Code, not AI peers).

Both surfaces are now inside the fence and the invariants are reconciled:

- Root `tsconfig.json` stays emit-capable so `./run.sh check-models` can keep tsc-emitting the project entry into `.tmp-verify-models/` for runtime introspection. A new `mcp/tsconfig.json` extends the root and adds the strip-types-runtime concessions (`allowImportingTsExtensions`, `noEmit`); `pnpm typecheck` runs both as a sequential pair. `AGENTS.md` § Typecheck Boundary documents the new shape and pins the rule that no `.ts` source file may sit outside both configs.
- `pi-extensions/entwurf-control.ts`: dead handlers (`session_switch`, `session_fork`) and dead helper (`getMessagesSinceLastPrompt`) removed; defensive runtime cast at the post-exhaustive-switch fallback; `result.isError` access replaced with a documented runtime cast that reads the framework's spread-injected field plus a `details.error` fallback (with the `||` vs `?:` precedence bug fixed); residual `sessionName`/`session.name` reads removed at the addressing surfaces; `Type` imported from `@mariozechner/pi-ai` to align the typebox universe with `StringEnum` and with what `pi.registerTool` consumes; `execute(params)` and `renderCall(args)` annotated with an explicit `EntwurfSendParams` type so the schema (runtime) and the type (compile-time) describe the same contract on both sides — schema-to-type inference is then bypassed and TS2589 cannot resurface. The two concrete revisit conditions for collapsing back to schema-inferred params are documented inline.
- `pi-extensions/entwurf.ts` and `package.json` finish the typebox single-source: `Type` is imported from `@mariozechner/pi-ai` here too, and `@sinclair/typebox` is removed as a direct dependency. pi-coding-agent's typebox 1.x continues to flow in transitively.
- `mcp/session-bridge/`: the alias-claim path in `createAlias` is now atomic — `fs.symlink` into a unique tmp path, then `fs.rename` onto the alias path. POSIX rename atomically replaces the destination, closing the unlink-then-symlink window where two concurrent same-name starts could both observe "no alias" and both write one. The file header documents why the human-aliased addressing surface is intentionally kept here while entwurf addressing is sessionId-only — different audience, different cost/benefit, no polling timer, fall-through to live-session scan if the alias is stale.

Why this is in the changelog and not folded into a feature release: the previous "typecheck green" state was green only because the broken files were outside the fence. Closing the fence forced every silent invariant violation to surface and be reconciled. The maintainer treats fence breaches as latent bugs, not as test-coverage choices, and the public log should reflect that.

## 0.4.5 — 2026-04-29

### Fixed

- **Restored pi / AGENTS context for ACP backends without growing the system-prompt carrier.** `appendSystemPrompt: false` remains the safe default: Claude still receives only the short engraving through `_meta.systemPrompt`, and Codex still receives engraving through `developer_instructions`. The rich pi context now rides a one-shot first user-message augment so both backends actually receive the bridge identity narrative, pi operating context, `~/AGENTS.md`, `cwd/AGENTS.md`, and date/cwd.
- **Avoided Claude Code OAuth "extra usage" failures from large custom system prompts.** The pi context no longer needs to be inserted into Claude's `_meta.systemPrompt = <string>` carrier, which had caused subscription sessions to be classified as metered usage when the carrier grew beyond the SDK-default shape.
- **Made entwurf-spawned ACP sessions receive the home context without duplicating project AGENTS.** Entwurf tasks already carry `cwd/AGENTS.md` in `<project-context ...>` tags; the bridge now detects that marker, removes only the duplicate cwd AGENTS section from the first-user augment, and preserves `~/AGENTS.md`, bridge narrative, pi base context, and date/cwd.
- **Failed loudly when configured AGENTS files cannot be read.** Missing AGENTS files are still allowed, but if `~/AGENTS.md` or `cwd/AGENTS.md` exists and cannot be read, bootstrap throws instead of silently starting a context-poor agent.
- **Separated capability descriptions from concrete tool names.** The first-user augment now tells agents to treat the actual callable tool schema as source of truth. Native pi, Claude ACP, and Codex ACP expose different tool names for similar capabilities (`read/bash/edit/write`, `Read/Bash/Edit/Write/Skill`, `exec_command/apply_patch/...`), so agents must not claim a tool exists only because AGENTS.md or the augment mentions it.
- **Fixed prompt hygiene around first-message prepends.** The augment is separated from the original user prompt with a blank line, preventing `Current working directory: ...<project-context ...>` concatenation in entwurf first prompts.

### Changed

- **Engraving is now an optional operator personal surface.** `prompts/engraving.md` ships as a minimal placeholder (`각인이라고 여기`); empty or missing engraving files are skipped. Bridge identity and operating context moved to the first-user augment.
- **Shared the `<project-context` wire marker through `protocol.ts`.** Entwurf generation and ACP-side de-dup detection now import the same dependency-free constant, keeping the wire-format marker single-sourced across root emit and MCP strip-types execution paths.

### Verification

- Re-ran paired identity interviews against Claude ACP and Codex ACP. Both now recognize pi-shell-acp, receive home/project AGENTS context, and distinguish prompt/context claims from actual callable tool schemas. Entwurf resume against a Sonnet sibling confirmed both `~/AGENTS.md` and project AGENTS context were retained across resume.

## 0.4.1 — 2026-04-29

Patch release closing a release blocker carried since 0.3.0 and adding the missing direct human-facing entwurf surface, plus removing the alias addressing layer the operating model has outgrown.

### Fixed

- **Entwurf extensions actually load.** `pi-extensions/entwurf.ts` and `pi-extensions/entwurf-control.ts` have lived in the repo since 0.3.0 but were never wired into `package.json`'s `pi.extensions` array, so neither the `--entwurf-control` flag nor the `/entwurf` / `/entwurf-status` / `/entwurf-sessions` slash commands actually loaded. The MCP bridge expected sockets at `~/.pi/entwurf-control/`, which an unloaded control extension never creates — leaving the entwurf surface documented in README/AGENTS.md effectively dead at runtime. Both entries are now in `pi.extensions`.

### Added

- **`/entwurf-sessions`** now surfaces cwd, model id, and idle state per live session via a new `get_info` RPC command, with `[N]` indices for direct addressing and per-session error rows when an individual peer fails to respond. The displayed list is cached so `/entwurf-send` can address by index.
- **`/entwurf-send <index|sessionId> <message>`** — the previously missing interactive surface for a human operator to message another live entwurf session directly. Defaults to `follow_up` mode and auto-attaches `<sender_info>` so the receiving side can reply via the `entwurf_send` MCP tool. The MCP `entwurf_send` tool path remains the agent-facing surface (errors crash the call so the agent cannot paper over a misroute); the new slash command is the human surface and reports failures as ordinary notifications.
- **`get_info` RPC command** on the entwurf control socket — returns `sessionId`, `cwd`, `model { id, provider }`, and `idle` for the serving session. Used by `/entwurf-sessions` enrichment; reusable by future tooling.
- **`gcStaleSockets()`** runs once per `startControlServer()` and cleans dead `.sock` entries from `~/.pi/entwurf-control/`. Pre-0.4.1 `.alias` symlinks left in the directory by older builds are also swept on encounter, retiring the GC TODO at `pi-extensions/entwurf-control.ts:213`.

### Removed (BREAKING — entwurf-control surface only)

The alias layer — `<sessionName>.alias` symlinks under `~/.pi/entwurf-control/` mirroring pi's `SessionManager.sessionName` via a 1s `setInterval` polling timer — is removed entirely. With per-session compaction disabled, the operating model is short-lived sessions ending in recap+new (see roadmap), so a human-friendly alias has little time to accumulate value, and the polling timer was the sole reason a kernel-driven socket-push design needed wall-clock work at all. The three race surfaces it carried — concurrent `syncAlias`, timer-vs-shutdown, symlink-vs-listener — are now structurally absent.

- `entwurf_send` MCP tool: `target` parameter renamed to `sessionId`; alias resolution removed. Use `entwurf_peers` to discover live ids.
- `entwurf_peers` MCP response: `name` and `aliases` fields removed from each session entry.
- `entwurf_send` extension tool (in-process): `sessionName` parameter removed; `sessionId` is now required.
- `--entwurf-session` CLI flag: only accepts a sessionId (UUID).
- `/entwurf-sessions` output drops the parenthetical `(alias)` label.
- `/entwurf-send`: `<alias>` form removed; `<index|sessionId>` only.

This change is independent of agent-config's `--session-control` extension under `~/.pi/session-control/` (its ingested copy of the alias surface is intentionally kept — different cost/benefit, no polling timer, no race surface) and of the bundled `mcp/session-bridge/` MCP (Claude Code-side; its `SESSION_NAME` alias is set once from cwd at `start.sh` and is the stable identity surface that side needs).

### Identity verification

A four-case identity interview was captured against 0.4.0 + this patch — OpenRouter Sonnet, pi-shell-acp Sonnet, native Codex, pi-shell-acp Codex. Both pi-shell-acp cases recognize `pi-shell-acp` as the bridge surface and enumerate `mcp__pi-tools-bridge__*` and `mcp__session-bridge__*` correctly. The two non-bridge cases honestly report that the entwurf MCP is "described in AGENTS.md but not in my schema" — the boundary is real and the agent sees it. The transcripts are being moved to BASELINE.md as part of 0.4.x, alongside the longer-term plan to publish session-level verification data (see roadmap).

## 0.4.0 — 2026-04-28

PI-native identity carriers for both ACP backends — Claude via system-prompt replacement, Codex via codex `Config` `developer_instructions` — with whitelist overlays isolating operator config, memory, sessions, rules, history, and (codex-specific) the SQLite thread/memory state DB. The model API itself is unchanged on each side; pi-shell-acp now owns everything above the model's minimum identity prefix and below the backend authentication.

### Changed

- **Engraving carrier — Claude.** Previously delivered via `_meta.systemPrompt.append`, additive on top of the claude_code preset. Now delivered via `_meta.systemPrompt = <engraving string>` (claude-agent-acp `acp-agent.ts:1685`, sdk.d.ts:1695), which makes claude-agent-acp pass the string directly into the SDK's `Options.systemPrompt` slot — full preset replacement. The claude_code preset's `# auto memory` guidance, per-cwd MEMORY.md path advertisement, working-directory section, git-status section, and todo-handling guidance all drop out of the system prompt. The engraving sits directly above the SDK's hard-wired minimum identity prefix (_"You are a Claude agent, built on Anthropic's Claude Agent SDK."_), which is the boundary pi-shell-acp deliberately respects. Verified by interview against the Claude backend (BASELINE.md, first run): the agent correctly identifies as a PI-native operating surface on top of the Claude API, refuses to claim auto-memory it does not have, and asks before running side-effecting capability checks.
- **Engraving carrier — Codex.** Previously delivered as a first-prompt `ContentBlock` prepend, which lands at user-message authority. Now delivered as `-c developer_instructions="<engraving>"` at codex-acp child spawn time, which materializes inside the codex `developer` role between the binary's `permissions` / `apps` / `skills` instruction blocks. codex-acp does not honor `_meta.systemPrompt` (verified against the Rust source — `codex-acp/src/thread.rs` `meta.get(...)` call sites all target MCP tool approval keys, none target prompt-level surfaces); `developer_instructions` is the highest stable identity carrier the codex stack offers. Structurally one config layer below the Claude side's preset replacement, but equivalent in authority intent. The new carrier participates in `bridgeConfigSignature` / session compatibility, so changing the engraving forces a fresh codex-acp spawn — reusing an existing child against a stale carrier would surface the previous identity to the model.
- **Compaction toggle no longer affects identity isolation.** Previously, `PI_SHELL_ACP_ALLOW_COMPACTION=1` set the entire `bridgeEnvDefaults` block to `undefined`, which dropped `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `CODEX_SQLITE_HOME` along with the Claude compaction-guard pair. That silently turned operator config inheritance back on the moment compaction was allowed. The toggle now strips only the compaction-guard env keys (`DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`); identity-isolation env stays regardless. Identity isolation is an invariant; the compaction knob is policy.

### Added

- **Whitelist overlay — Claude.** `~/.pi/agent/claude-config-overlay/` is now built from a fixed allowlist instead of mirroring `~/.claude/` minus `settings.json`. Author-controlled `settings.json` (`permissions.defaultMode = "default"`, `autoMemoryEnabled: false`); passthrough symlinks for `auth.json`, `cache`, `debug`, `session-bridge`, `session-env`, `shell-snapshots`, `skills`, `stats-cache.json`, `statsig`, `telemetry`; overlay-private empty `projects/` and `sessions/`; binary-managed `.claude.json` and `backups/`. Anything else (`CLAUDE.md`, `hooks/`, `agents/`, `todos/`, `tasks/`, `history.jsonl`, `settings.local.json` carrying personal env / GitHub PAT, `plugins/` operator enablement, ...) is intentionally not in the overlay. Stale entries from earlier blacklist-style overlays are wiped on first bootstrap with this code.
- **Whitelist overlay — Codex.** Narrower than Claude because codex's leak surfaces run deeper. `CODEX_HOME` *and* the new `CODEX_SQLITE_HOME` env both pinned to `~/.pi/agent/codex-config-overlay/` so the codex thread/memory state DB cannot drift outside the overlay through env or future code paths. Author-controlled `config.toml`; passthrough symlinks for nine entries (`auth.json`, install metadata, non-data caches, `skills`); overlay-private empty `memories/`, `sessions/`, `log/`, `shell_snapshots/`; binary-managed `state_5.sqlite{,-shm,-wal}` + `logs_2.sqlite{,-shm,-wal}` (both DB groups). Operator entries hidden by the whitelist: `history.jsonl`, `rules/` (codex execution policy, not narrative memory), `AGENTS.md` (auto-loaded by `codex-rs/agents_md.rs` as user instructions), the operator's personal `config.toml` fields. Pre-migration overlays carrying stale operator-side symlinks for the binary-managed entries get those symlinks stripped on first bootstrap with this code, so codex re-initializes fresh state.
- **Three-layer codex memory isolation.** `codexDisabledFeatures` default gains `memories` so codex stops loading operator memory entries into the developer-role context. Two more layers pinned at launch via the new `CODEX_OPERATOR_ISOLATION_ARGS` group: `memories.generate_memories=false`, `memories.use_memories=false`, `history.persistence="none"`. Plus the overlay's empty `memories/` directory itself. Defense in depth against a future codex build flipping the feature gate or renaming the keys.
- **`resolveBridgeEnvDefaults(backend, { allowCompaction })` exported helper.** Single source of truth for how the spawned child's env defaults compose with the compaction toggle. Routed through `createBridgeProcess` and exercised directly by `check-backends` so the compaction-vs-isolation separation is pinned at unit-test time, not just at production startup.
- **`tomlBasicString(value)` helper** for the Codex carrier. JSON's escape rules are a strict subset of TOML basic-string escapes (`\\`, `\"`, `\n`, `\r`, `\t`, `\uXXXX`), so `JSON.stringify(value)` produces a TOML-valid quoted form usable directly as the value half of `-c developer_instructions=<...>`. Used by both the spawn-array path and the `CODEX_ACP_COMMAND` shell-override path.
- **`BASELINE.md`** — paired-language identity-check interview (Korean + English) any human operator can run against a fresh pi-shell-acp session, plus history entries for the first PI-native baseline runs on both backends.

### Removed

- `buildCodexBootstrapPromptAugment` and the codex adapter's `buildBootstrapPromptAugment` handler. The first-prompt `ContentBlock` prepend was the previous codex carrier; `developer_instructions` replaces it. The interface point on `AcpBackendAdapter` remains for future backends that lack a higher-authority carrier.

### Verification

`check-backends` grew from 52 → 110 assertions across the two PI-native commits and the migration / compaction-isolation fix that followed. The new invariants:

- TOML escape contract for `developer_instructions` (presence/absence based on input, multi-line + embedded-quote escaping).
- Claude overlay leak canaries — operator-side `MEMORY.md` and `hooks/` must not be reachable through the overlay.
- Codex overlay leak canaries — operator-side memory, sessions data, `history.jsonl`, `rules/`, `AGENTS.md`, `log/`, `shell_snapshots/`, and the four state/logs DB files (state_5.sqlite + WAL/SHM, logs_2.sqlite + WAL/SHM) must not be reachable through the overlay.
- Migration regression — pre-migration overlays carrying stale operator-side symlinks for binary-managed entries get those symlinks stripped on first run with the new code.
- `resolveBridgeEnvDefaults` — Claude with compaction allowed strips compaction-guard env but keeps `CLAUDE_CONFIG_DIR`; Codex with compaction allowed keeps both `CODEX_HOME` and `CODEX_SQLITE_HOME` (codex's compaction guard is a launch-arg threshold, not env).
- Idempotence on second call.

### Notes for upgraders

The first session bootstrap after upgrading from 0.3.x will silently migrate the existing overlay shape. Stale symlinks carrying operator data — including, on the codex side, symlinks pointing at the operator's real `state_5.sqlite*` thread/memory state DB — are wiped automatically. The upgrade path needs no manual intervention. After the first session, `~/.pi/agent/{claude,codex}-config-overlay/` should match the whitelist shape described above; if it doesn't, the migration ran in a different process and the overlay rebuild on the next bootstrap will converge.

## 0.3.1 — 2026-04-28

### Added

- **Operator warning when `codexDisabledFeatures: []` is set explicitly.** The empty-array case opts the codex backend fully out of bridge feature gating (codex native `multi_agent` / `apps` / `image_generation` / `tool_suggest` / `tool_search` all become callable), which differs from key-absent (default `DEFAULT_CODEX_DISABLED_FEATURES` applies). The two cases were conflated in agent-config 0.2.x as "redundant defense-in-depth" — the `[]` was originally a workaround for the 0.2.1 `params.codexDisabledFeatures.spread` crash, then survived the 0.2.2 nullish-guard fix and silently flipped the codex tool surface from fail-closed to fail-open. Bridge now emits a one-shot stderr warning on first bootstrap whenever explicit `[]` is observed (`[pi-shell-acp:warn] codexDisabledFeatures=[] in settings.json explicitly opts out ... To restore the fail-closed default, remove the codexDisabledFeatures key`). Throttled to once per process — does not repeat on prompt or model switch. Key-absent and partial-disable cases stay silent. Surfaced after a Codex identity-check session reported `spawn_agent` / `mcp__codex_apps__github_*` as available native tools on a fresh 0.3.0 install where the operator's `~/.pi/agent/settings.json` carried the legacy `[]` knob.

## 0.3.0 — 2026-04-27

### Fixed

- **claude-agent-acp child no longer silently exits when the SDK's auto-detect resolves the wrong libc variant.** claude-agent-acp 0.31.0 (`dist/acp-agent.js:1298`) reads `process.env.CLAUDE_CODE_EXECUTABLE` only and ignores the `_meta.claudeCode.options.pathToClaudeCodeExecutable` pi-shell-acp passes. NODE_PATH (set by the pnpm-installed pi-coding-agent wrapper) hoists both musl and glibc variants of `@anthropic-ai/claude-agent-sdk-linux-<arch>-*`; the SDK's `[musl, glibc]` resolution order picks musl first and spawn fails with ENOENT on glibc hosts → child silent exit → "Internal error" after retry. pi-shell-acp now sets `CLAUDE_CODE_EXECUTABLE` in the child env from `resolveClaudeCodeExecutable()` (libc-aware). Operator's exported var still wins (process.env spread last). Surfaced as "Internal error" on oracle ARM aarch64.

- **`~/.pi/agent/entwurf-targets.json` auto-symlinked at install time.** `pi-extensions/lib/entwurf-core.ts:45` reads `~/.pi/agent/entwurf-targets.json`, but the package shipped the canonical version only at `<install_dir>/pi/entwurf-targets.json`. Without manual setup, any `entwurf` tool call threw `EntwurfRegistryError` (lazy — no surface during plain `pi --model ...` runs but blocks delegation immediately). `run.sh install_local_package` now creates the symlink idempotently and preserves any operator override (file or differently-targeted symlink left untouched).

## 0.2.2 — 2026-04-27

### Fixed

- `ensureBridgeSession` no longer crashes with `TypeError: params.codexDisabledFeatures is not iterable` when callers omit the `codexDisabledFeatures` field. The 0.2.0 introduction of the `codexDisabledFeatures` knob added required spreads in `createBridgeProcess` and the reuse path, but `loadProviderSettings`'s default fallback only covers callers that go through `index.ts` (i.e. the production `pi --model ...` path). Smoke embed scripts in `run.sh` (and any third-party caller) bypass that fallback and were exposed to the spread crash. Both spread sites now normalize via `params.codexDisabledFeatures ?? DEFAULT_CODEX_DISABLED_FEATURES`, matching what `loadProviderSettings` would have applied. Universal — any backend (claude, codex), any caller path. Surfaced as "Internal error" in pi sessions on a fresh consumer install.
- `run.sh` smoke embed scripts (`smoke-claude/codex`, `smoke-cancel`, `smoke-model-switch`) now declare `codexDisabledFeatures: []` explicitly so caller intent is visible at the embed site, not only via the `acp-bridge.ts` fallback.

### Docs

- `AGENTS.md` § Entwurf: cross-reference the resident-side naming pair `MITSEIN.md` in agent-config (Mitsein/Entwurf as Heidegger pair — pi-shell-acp owns the entwurf side, resident conventions live in agent-config). Also clarify the bare-model auto-resolution rule in the target-registry bullet.

## 0.2.1 — 2026-04-27

### Fixed

- Consumer install no longer breaks when `husky` is not installed (dev-only dep). The `prepare` script falls through with `|| true`, so `pi install git:github.com/junghan0611/pi-shell-acp` works on machines that don't have husky. Previously failed with `husky: command not found (sh: line 1, exit 127)` on consumer install paths (e.g. Oracle).

## 0.2.0 — 2026-04-27

First public release. Used daily by the maintainer; not promised to work elsewhere yet.

### ACP bridge

- Provider `pi-shell-acp` registers with pi. Models route to backends by curated allowlist (`claude-sonnet-4-6` / `claude-opus-4-7` → Claude, `gpt-5.x` from `openai-codex` → Codex), with prefix fallback for non-curated IDs.
- Bootstrap order is `resume > load > new`, with `pi:<sessionId>` persisted under `~/.pi/agent/cache/pi-shell-acp/sessions/`.
- Per-turn `usage_update` (or `PromptResponse.usage` fallback) drives the pi footer context meter; the bridge does not maintain a separate meter.

### Operating-surface contract

- Claude side: `tools` defaults to `[Read, Bash, Edit, Write]` (auto-adds `Skill` when `skillPlugins` is non-empty). `disallowedTools` default blocks the SDK's deferred-tool advertisement (`Cron*`, `Task*`, `Worktree*`, `EnterPlanMode`/`ExitPlanMode`, `Monitor`, `NotebookEdit`, `PushNotification`, `RemoteTrigger`, `WebFetch`, `WebSearch`, `AskUserQuestion`). `settingSources: []` + `strictMcpConfig: true` by default. `permissionAllow` wildcards thread into `Options.settings.permissions.allow`.
- Codex side: `approval_policy=never` + `sandbox_mode=danger-full-access` + `model_auto_compact_token_limit=i64::MAX` pinned at every launch. `web_search="disabled"` and `tools.view_image=false` pinned. `codexDisabledFeatures` (settings.json) materializes as `-c features.<key>=false` flags; defaults to `image_generation`, `tool_suggest`, `tool_search`, `multi_agent`, `apps`. Operator can opt fully out with `[]` or override.
- Both backends launched with config overlays (`CLAUDE_CONFIG_DIR=~/.pi/agent/claude-config-overlay/`, `CODEX_HOME=~/.pi/agent/codex-config-overlay/`) — pi-authored config file + symlinks for every other entry, idempotent rebuild on each launch. Operator's exported env wins.

### Compaction policy

- Host: `session_before_compact` returns `{cancel: true}` for every pi compaction trigger (silent overflow recovery, threshold compaction, explicit-error overflow, manual `/compact`). Opt out with `PI_SHELL_ACP_ALLOW_COMPACTION=1`.
- Backend: `DISABLE_AUTO_COMPACT=1` + `DISABLE_COMPACT=1` (Claude), `model_auto_compact_token_limit=i64::MAX` (Codex).

### Entwurf

- Sync + async spawn (`pi-extensions/entwurf.ts`), shared registry + identity preservation (`lib/entwurf-core.ts`), Unix-socket control plane (`entwurf-control.ts`, ingested from Armin Ronacher's `agent-stuff` under Apache 2.0).
- Spawn target allowlist at `pi/entwurf-targets.json`.
- MCP adapter `pi-tools-bridge` exposes `entwurf`, `entwurf_resume`, `entwurf_send`, `entwurf_peers`. Send is fire-and-forget.
- `mcp/session-bridge/` carries Claude Code ↔ pi session messages (`list_sessions`, `send_message`, `receive_messages`, `session_info`).

### Engraving

- Short additive text from `prompts/engraving.md`, delivered via `_meta.systemPrompt.append` (Claude) or first-prompt `ContentBlock` prepend (Codex). `{{backend}}` and `{{mcp_servers}}` substituted at bootstrap. The engraving appends to the backend's native system prompt; it does not replace it.

### Tooling

- `./run.sh` covers install, smoke (Claude / Codex / both), resume verification, MCP bridge check, sentinel, session-messaging.
- `check-backends` (52 assertions) gates launch flag composition, override paths, and `codexDisabledFeatures` empty / partial cases.
- `check-dep-versions` catches version-pin drift between `package.json` and `run.sh`.
- Husky pre-commit hook runs typecheck + check-backends + check-models + check-mcp + check-dep-versions; skipping requires explicit acknowledgement.
- Release flow lives at `.pi/prompts/make-release.md` + `scripts/release.sh`.

### Pinned versions

- `@agentclientprotocol/claude-agent-acp@0.31.0`
- `@zed-industries/codex-acp@0.12.0`
- `@agentclientprotocol/sdk@0.20.0`

## Before 0.2.0 — chronicle of work before the first public release

This section is added retroactively so the repository's release axis carries the full chronicle, not only what shipped after the public surface was named. The two phases below are distinct in authorship and design intent.

- **2026-02-01 ~ 2026-03-21** — original `claude-agent-sdk-pi` era. Before the current maintainer took over. About 30 commits by external contributors (prateekmedia, w-winter, gwynnnplaine) under a bespoke-shim design that called `claude-agent-sdk` directly from pi. Versions 1.0.1 ~ 1.0.16 in that lineage.
- **2026-04-09 ~ 2026-04-27** — maintainer takeover, ACP pivot, repository rename. Eighteen days from the takeover commit (`f31367d`) to the 0.2.0 public release. No public version cuts in this window; all changes go into the 0.2.0 base.

### 2026-02-01 ~ 2026-03-21 — original `claude-agent-sdk-pi` era (not by current maintainer)

Documented for chronological completeness; the design intent and code authority belong to other contributors. The repository was named `claude-agent-sdk-pi` and shipped a bespoke shim that called `claude-agent-sdk` directly from pi. The core unsolved problem of this era — stateless HTTP-shaped sessions that re-sent the full payload every turn, causing accumulated quality degradation as conversations grew — is precisely what the later ACP pivot would address.

External-contributor highlights pinned by commit:

- `149d0cc 2026-02-01 init provider` — first commit. Provider registration shape.
- `2026-02-01 ~ 02-06 — 1.0.x patches` (`f352cc6`, `9efacba`, `d8c4e99`, `9f63241`, `0c9a212`, `224ca00`, `b7285fb`, `395625c`, `fc7c31a`, `011ca8d`, `829e8f4`, `ee39b7f`, `27fcd80`, `8a84df6`, `19e0c3f`, `1883737`, `3e8088c`): caching block ordering, TTL, abort handler, cost updates, demo screenshot, install doc.
- `6ec6c8f 2026-02-03 feat: add strict MCP config + configurable setting sources` (w-winter, merged via PR #1) — first external feature contribution.
- `34038c5 2026-02-06 fix sdk tool-result resume flow` + `94644e2 move pi deps to peer/dev and refine fork pending-tool replay` — early attempts to fix what would later be described as "matching stateful tool execution shape against a stateless transport".
- `c5d5f8e 2026-02-09 feat(claude-agent-sdk-pi): map opus-4-6 high thinking to xhigh budget` (w-winter, PR #2).
- `fbbc066 2026-02-13 fix(claude-agent-sdk-pi): persist tool execution ledger to recover missing tool results` + `b85bffb 2026-02-13 chore: bump patch version to 1.0.16` — the tool execution ledger the current maintainer would later remove during the bespoke→ACP pivot.
- `7d2e167 2026-03-21 fix(provider): pass selected model to SDK query` (gwynnnplaine, PR #4) — last commit of this era.

### 2026-04-09 ~ 2026-04-27 — maintainer takeover and ACP pivot

Eighteen days from takeover to the first cut. No public release in this window; every change goes into the 0.2.0 base.

#### Phase A — takeover and pi-native stabilization (2026-04-09)

`f31367d feat: add harness-first setup workflow` (08:29 +0900) is the takeover. The day's commits establish the new authoring axis: `773c1d8 disable SDK session persistence — pi manages its own sessions`, `c4281f4 pi-native stability — edit args, toolwatch kill, re-registration guard`, `e3c1c5f convert TypeBox schemas to Zod for MCP custom tools (E2 fix)`, `68cc7e7 pin SDK to latest stable — claude-agent-sdk 0.2.97, sdk 0.86.1`, `f68864d direct Anthropic API path — multi-turn parity with pi-mono`. The bespoke-shim design is preserved in this phase; the question of whether to keep it is the next phase's subject.

#### Phase B — ACP pivot, archive, reactivation, rename (2026-04-10 ~ 2026-04-16)

The pivot lands in a single day: `50328a4 pivot provider to claude-agent-acp bridge` (10:00), `835f517 align ACP bridge docs with non-append model`, `afcb55b add ACP tool visibility and session invalidation`, `669e929 add non-append settings surface`, `61d9649 fix: select real prompt after pi hook messages`, `1435afb add benchmark snapshot and rename note`. Same day evening: `c3b3310 archive repository — ben approach wins over ACP bridge` (15:10). The repo is briefly archived because `@benvargas/pi-claude-code-use` (a third-party OAuth-rewrite path) was technically smoother on first comparison.

Five days later, `de7dc47 reactivate ACP bridge status` (2026-04-15 18:38). The recorded reason is policy-shape: even when a workaround is technically better, a path that has to disguise itself to a vendor cannot be carried by this repository. The archive → reactivation pair stays in the git log as the most honest single beat of the entire pre-0.2.0 arc.

The renaming finishes on 2026-04-16:

- `5747fc9 add agent-shell-like ACP session continuity` — `resume > load > new` bootstrap order, which becomes Hard Rule #2 in 0.2.0.
- `6477129 rename provider surface to pi-shell-acp` — this is when the repo name and the provider id become what they are today.
- `02a392d remove legacy ACP naming compatibility`, `b1b6584 rewrite repo guide for pi-shell-acp owner`, `a3ccb1c add ACP reference implementations and local paths`, `7417a7e add ACP verification guide`.

#### Phase C — MCP injection scope and dual-backend (2026-04-17 ~ 2026-04-20)

- `cfec410 feat(mcp): explicit mcpServers pass-through via settings` (2026-04-17). MCP servers are passed through pi-shell-acp settings rather than scanned from ambient `~/.mcp.json`. The decision becomes Hard Rule #4 in 0.2.0.
- `f6f0c3f refactor(mcp): pi-facing injection scope — hash-only sig, fail-fast, check-mcp gate` (2026-04-18). Adds the `check-mcp` gate that catches MCP-injection drift before runtime.
- `1731865 feat: add dual ACP backend support` (2026-04-20) + `8682c90 chore: pin codex-acp runtime version` + `d3dff4f test: add dual-backend smoke gate`. Codex joins Claude as a second backend — the wire-level basis for "siblings from different schools" the bridge's design narrative carries forward.
- `5b9a043 docs: clarify codex MCP visibility checks`, `99df34d feat(bridge): strict bootstrap diagnostics + continuity smoke`, `753ba52 feat: add cancel cleanup diagnostics and smoke gate`, `66d2089 feat: log model switch branches and add smoke gate`, `b99d0d0 test: add delegate-style continuity smoke gate`.

#### Phase D — bridge-vs-harness boundary and entwurf ingestion (2026-04-21 ~ 2026-04-24)

The "what belongs in the bridge vs what belongs in the resident" question gets its first explicit boundary in this phase, and the entwurf surface gets ingested from agent-config.

- `cec3e13 docs: adopt qualified model-id convention + refresh §12.5 Codex boundary` (2026-04-21).
- `67d2369 docs: fix the bridge-vs-harness boundary in product docs` (2026-04-21).
- `c5ea241 docs: retire opt-in env narrative, point at agent-config registry as spawn authority` (2026-04-22).
- `b9f642b chore: bump claude-agent-acp 0.30.0, pi 0.69.0, cap claude ctx to 200K` (2026-04-23) — the dependency 0.6.0 will later bump again to 0.33.1 for issue #16.
- `7acd7f6 feat: project pi-side compaction summary into new claude session` (2026-04-23). The early shape of the compaction handoff 0.5.0 will retire entirely with the "bridge does not implement compaction" declaration.
- `56be590 docs: add transparent step-by-step verify policy`, `4707e97 docs: VERIFY rewrite — intent and pass criteria, delegate orchestration as default`, `8c3da78 docs: VERIFY — wording guide and bridge-vs-semantic continuity split`, `c0aebbb docs: VERIFY §12 — cross-ref agent-config sentinel as integration-side bootstrap-path gate` (2026-04-23). VERIFY.md is built as a parallel document to README/AGENTS — the verifier-side axis.
- `97593a3 docs: carve Entwurf Orchestration mirror for agent-config migration` (2026-04-24). The naming pivot — `delegate` → `entwurf` (기투, projection-of-self) — is decided on the prior day's strategy review and now lands in docs.
- `3c2780b docs: two-axis verification — protocol smoke + agent interview, both required` (2026-04-24). The two-axis verification frame later codified in VERIFY.md.
- `768baf4 feat: ingest entwurf surface from agent-config (step 5 verbatim)` (2026-04-24). Entwurf physically moves from agent-config into pi-shell-acp. The verbatim ingest means agent-config's previous `delegate/` extension and entwurf MCP enter the bridge repo without alteration; refactor follows in 0.2.x patches.
- `da97fa9 chore: align pi runtime deps to 0.70.0 exact + adapt delegate.ts API`, `060c412 fix: curate pi-shell-acp model surface + switch codex metadata source`, `9269771 chore: add gpt-5.5 to delegate target registry (native + explicitOnly ACP)`, `6939e7e docs: record release baseline — pi 0.70.0, curated models, gpt-5.5 at 400K`, `57338a6 fix: make pi-native delegate failures throw under pi 0.70`, `2b1b7e5 docs: remove stale agent-config ownership refs + English pass on VERIFY.md` (2026-04-24).
- `3d6800d chore: ingest sentinel-runner.sh from agent-config (step 5 follow-up)`, `3bf5f8f chore: migrate from npm to pnpm`, `a70500a feat: Phase 5 — Axis 1 interview-prerequisite gates in run.sh`, `3ed8baa chore: trim install footprint + frozen-lockfile`, `4fc99b8 chore: regenerate pnpm-lock.yaml`, `bc79bda docs: Phase 5 evidence — Axis 1 gates green end-to-end on fresh install` (2026-04-24).
- `035254b refactor: flatten MCP, strip-types runtime, narrow tool scope, public-repo env hygiene` (2026-04-24). MCP surface flattened; node `--experimental-strip-types` runtime adopted. Tool scope narrowed for the public repo.
- `9116ea9 docs: align README / AGENTS / VERIFY with the flatten + narrow-scope changes`, `d6e2579 docs: genericize personal paths in README/AGENTS/VERIFY examples`, `9e04b31 feat: install auto-registers bundled mcpServers for in-repo MCP bridges`, `db5b0de docs: document consumer vs developer install paths in VERIFY §1` (2026-04-24).
- `f74dd6a feat: own session-control extension — drop runtime dep on consumer repos` (2026-04-24). The session-control extension earlier consumers depended on through agent-config is now owned in this repo.
- `baa608a fix(session-control): correlate turn_end to caller's send via baseline turnIndex` (2026-04-24).
- `a36ffde docs(delegate): translate remaining Korean comments to English` (2026-04-24). The bridge's code surface is English-only.
- `8e98872 docs(messaging): codify Send-is-throw at tool + AGENTS level` (2026-04-24). The decision that `entwurf_send` is fire-and-forget. 0.4.14 later sharpens this with the `wants_reply` etiquette marker.
- `3a4dedf feat(models): differentiate Claude context defaults — sonnet 200K, opus 1M` (2026-04-24).
- `8b96b4a docs: record pi footer context% upstream issue (cacheRead-inclusive)`, `bcf3252 fix: context-metric overreport on ACP routes — local correction` (2026-04-24). The first round of footer-percentage corrections; the 0.4.x context meter narrative will refine this further.
- `6b5aff8 feat: externalize engraving prompt to prompts/engraving.md` (2026-04-24). The engraving moves from inline code constant to an operator-editable file.

#### Phase E — pre-release polish (2026-04-25 ~ 2026-04-26)

Two more days of incremental fixes (model-switch observability rounding, smoke-delegate-resume continuity gate, context-meter PR-A/B debate that ends with PR-B discarded) culminate in the first public cut on 2026-04-27.

The `[pi-shell-acp:model-switch]` diagnostic and `smoke-delegate-resume` continuity smoke both land in this phase. PR-B (the `PiOccupancy = prefixOverhead + visibleTranscript` sidecar design) is discarded in favor of the simpler "footer follows ACP `usage_update.used/size` directly" shape — which lands in 0.2.0 as "per-turn `usage_update` drives the pi footer context meter; the bridge does not maintain a separate meter".

0.2.0 then ships on 2026-04-27 as the first public release under the `pi-shell-acp` name.
