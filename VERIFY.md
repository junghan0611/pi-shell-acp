# VERIFY.md

Agent-driven verification guide for the current `entwurf` surface. Machine-checkable
invariants live in gates; this file defines evidence strength, release acceptance,
and the manual judgements a gate cannot make.

> **Current surface.** `entwurf-bridge` exposes `entwurf_v2`, `entwurf_peers`,
> `entwurf_fresh_call`, `entwurf_resume_call`, `entwurf_self`, `entwurf_inbox_read`, and `entwurf_register_native`. The ACP
> backends are Claude and Snowflake Cortex Code. Antigravity is a separate shipped
> native-push citizen lane; Codex has delivery-probe evidence but no managed citizen
> lane. Retired v1 verbs and bridge implementations belong only in CHANGELOG/git.

This is a working protocol, not a metrics ledger. Per-run counts, digests, and release
chronology belong in [BASELINE.md](./BASELINE.md), CHANGELOG, and release artifacts.

VERIFY.md is the **agent-driven** surface; [BASELINE.md](./BASELINE.md) is the operator-driven one. One ACP-bridged model runs the checks against another and writes down what it sees — if the bridge is faithful, two replicants looking at the same mirror describe the mirror the same way. This is in-bridge cross-validation, not external evidence: verifier and subject share the same bridge, MCP servers, and overlay, so a uniform corruption of those would not surface here (that gap is what the L3+ rungs close).

## Evidence Levels

Every claim — and every History entry — sits on one of these rungs. Make the rung explicit so neither narrative nor reader overreaches.

> **Namespace note.** These `L0–L5` rungs measure *evidence quality* for bridge verification. Native async delivery has its own capability namespace `D0–D8` in [DELIVERY.md](./DELIVERY.md); operator-driven identity baseline uses `Q-L1..Q-L5` *surface-isolation layers* in [BASELINE.md](./BASELINE.md). Same letters, different axes — do not conflate "high-quality evidence" with "high delivery capability".

| Level | What it is | Closes | Does not close |
|---|---|---|---|
| **L0** | Narrative / self-report | Agent description of the system | Anything depending on actual behaviour |
| **L1** | Transcript cross-check | Two+ bridged identities agree on what they see | Echo-chamber risk (shared prompt/carrier) |
| **L2** | Objective MCP tool call | Real on-disk/on-socket payload through the bridge | Shared-implementation corruption |
| **L3** | On-disk/process/socket corroboration *outside* the bridge | Bridge claim ↔ `ls`/`pgrep`/`lsof`/session JSONL | Time-extended drift (auth, version, cache) |
| **L4** | Human or direct-native side-by-side | A person (or non-bridged direct path) reaches the same answer for matched prompts | Production-shape workload |
| **L5** | Long-haul soak | Bridge stays correct over hours-to-days incl. partial failure | Operational ceiling for now |

When you write a new entry, mark its rung. "L1 only" is honest; "L2 reached" is stronger but does not silently imply L3.

---

## 0A. Execution Policy — Transparent Mode

Verification here is not a benchmark. In production we exchange short turns and stop immediately to isolate a cause before resuming when something looks off. This document records **verification intent (what we look at) and pass criteria (how to judge)**; the execution shape is the agent's choice as long as the criteria are met.

### The canonical floor — two entry points

- **Deterministic floor — two tiers (#70):** `pnpm check` is the everyday CORE — toolchain (lint + typecheck), the vitest lanes, and the pure-unit / behavioral-contract / source-topology gates plus the cheap static coherence checks. It prints its own total wall time; acceptance is ≤60s on the reference host `oracle` (an operator measurement, never a hard wall-clock gate on arbitrary hosts). `pnpm run check:full` is the FULL deterministic floor — the core plus the hermetic-integration and package/install tiers — and is what the frozen-candidate protocol, push CI, release-gate, and `prepublishOnly` run. Exact membership is the named `check:*` group scripts in `package.json` (the executable SSOT — this document records meaning and principles, not the command list); a gate changes tier by semantic-class decision, never by getting faster or slower. The FULL tier carries the qualification HEAD (`check-gate-manifests`, through `check:hermetic`); the everyday core does not, and neither tier carries the separately scheduled mutant-executing body (`check-gate-qualification`).
- **Discriminating power of that floor:** `./run.sh check-gate-qualification` (scheduled, not ambient: standalone when a lane changes a gate/mutant/matrix, in the CI `check` job on a branch push that touched the qualification surface, and as a release-gate MUST step — no longer inside the default check chains; a semver TAG push triggers no CI at all, because the same SHA's branch run already carries every job and is the exact-SHA evidence a release quotes; a push that touched none of the qualification surface skips the body, and `workflow_dispatch -f qualify=true` plus a weekly `schedule` run it unconditionally — the exact-SHA release oracle refuses a SHA whose body step did not conclude success) re-plants committed defect mutants (`scripts/mutants/*.json`, one per closed defect class) in an isolated snapshot repo and requires each to turn its gate red **bounded and at its claimed `[QK:<claim>]` signature** — a wrong-reason red fails, a baseline-red control voids the whole group, and the runner is negative-controlled on every run (zero-match/multi-match/survived/wrong-reason/hang/control-red/impurity). This measures whether the deterministic gates still *block* what they claim to block; it is **not a new evidence level** (L0–L5 are untouched) and never substitutes for LIVE evidence. Per-cut records cite claim IDs + killed mutant IDs — "N checks passed" alone is not evidence. `check-agy-permission-matrix` complements it with the enumerated permission contract space (literal cells + stated exclusion rules, oracle independent of the SUT). The gate's HEAD is separable and IS in the floor: `check-gate-manifests` runs the runner self-test, validates the committed manifest set against the origin index, and asserts the declared lane inventory, while executing zero mutants and never snapshotting the repo — three of the five reds qualification has ever produced in CI died in that head, in under five seconds.
- **Live floor:** `LIVE=1 ./run.sh release-gate <scratch-project-dir> --cut` — `pnpm run check:full` + the v2-native live gates + the ACP plugin acceptance floor. It reports a **two-tier summary**:
  - **MUST tier** (release-blocking — owns the exit code; "green" applies only here): `pnpm run check:full`, `check-gate-qualification`, `smoke-entwurf-v2-matrix-live`, `check-bridge`, `doctor-pi-provider` (#81 — `check-bridge` proves the launcher this checkout SHIPS; this proves the invocation the operator's pi provider actually EXECS, by booting it and requiring the entwurf verb set back, because `command -v` answers yes for a command that exits 127; wired as a step on 2026-08-19 after a relocated pnpm cmd-shim cost a cut sixteen LIVE steps before the same fact surfaced at `smoke-acp-bundled-mcp-live`), the resident-garden-guard zero-token half (record birth / record-keyed socket / attach-on-reopen), the `smoke-acp-*-live` ACP plugin smokes (socket-citizen / raw-turn / overlay / provider / session-reuse / carrier-augment / memory-containment / rgg / mcp / skill / bundled-mcp / v2-send), the axis wired in on 2026-07-31 that the aggregate had simply never listed (`smoke-claude-native-resume-live`), `smoke-entwurf-chain-live` — the cross-harness delivery chain (native Claude Code → pi GPT → pi ACP Sonnet → mailbox terminus) proving sender identity and replyability at every hop plus a real read receipt at the end — the integrated `smoke-mux-lifecycle-live` (its own note below), and the two OMP steps 0.16.0 wired: `smoke-omp-receive-live` (the addressed roundtrip into a live omp citizen; it reads the capability registry and decides its own outcome rather than passing by default) and `smoke-omp-fresh-live` (the clause 7 receipt the release stop now requires). (`smoke-session-id-name` is gone — #50 C3: its `--session-id`/`--name` substrate has no entwurf consumer anymore.)
  - **BEHAVIOR tier** (advisory, non-blocking): the resident-garden-guard positive (a model-in-loop `entwurf_self` turn). A BEHAVIOR FAIL is surfaced with its artifact path but **never blocks the cut**. The lane holds what the model *chooses*, never what our wiring fails to deliver — a gate that TELLS the model which tool to call stays MUST, because its failure is ours — measured 2026-07-24, when the tool turned out to be absent from the session schema in both observed failures (the bundled-MCP readiness gap recorded in `scripts/smoke-acp-v2-send-live.ts`).
  - **Every MUST step is invoked and reports its own outcome.** Prerequisite-bearing LIVE MUST steps ride the P1 STEP OUTCOME protocol (`scripts/lib/step-outcome.sh`): exit 0 = PASS, exit 97 = SKIP (a prerequisite the step does not have, printed as an `[entwurf:skip]` line), anything else = FAIL. The two non-skippable static steps (`pnpm run check:full`, `check-gate-qualification`) are inline: 0 = PASS, nonzero = FAIL, no SKIP arm — they have no prerequisite to decline. A skip is never counted as a pass — that hole is what let a cortex-less host read as cortex acceptance. Without `--cut` this is the unattended diagnostic: SKIPs are reported and the run still exits 0. **`--cut` makes it acceptance and any MUST SKIP is red**, which is how "a real cut needs `LIVE=1` with `SKIP=0`" stopped being prose. A green MUST gate is **necessary, not sufficient** — GLG authorizes the cut.
  - **When cost-bearing MUST gates run (fixed 2026-07-23, the F6/F7 lesson):** a commit that touches a rail a MUST-tier live gate covers runs that gate **before cross-review is requested** — never parked behind "run it at approval time". Deferring a wired gate to a human decision is what let F6/F7 ship reviewed-and-approved; the wiring exists so the verdict never depends on who pressed enter. "배선이 없어 못 한 것은 OK, 배선이 있는데 안 돌린 것은 우리가 남긴 구멍이다." Model-in-loop cost is spent via the subscription-backed `entwurf` provider where the gate allows it, a free-tier native model otherwise; cost is a reason to pick the cheap target, not to skip the gate.

> **Cortex is an on-demand axis, not an aggregate one.** Its rail needs an external Snowflake connection and login that the host owns, not the repo — so wiring it into the aggregate would block every cut taken on a host without that account. **The release aggregate does not re-certify Cortex**; `LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> ./run.sh smoke-acp-cortex-live` stays a required direct call whenever a cut changes Cortex rail code or an operator elects to certify that host. Its honest-skip behaviour is unchanged: run it without the connection and it reports protocol SKIP, never a pass. **Operator-host limit (2026-08-20, measured):** the source-owning host has no Snowflake subscription, and Cortex Code offers no free tier that a live turn can reach — a direct attempt confirmed it. So on this host `smoke-acp-cortex-live` can only ever report protocol SKIP, and no LIVE Cortex evidence can be produced here until Snowflake supplies a free-usable route or the account is subscribed. Record that SKIP as an absent axis; never soften it into a pass, and never substitute a different backend as Cortex evidence.
>
> A cut that touches the prompt-lifecycle contract (no wall clock on a running turn) owes one long-turn acceptance the aggregate floor is too short to carry: `LIVE=1 ./run.sh smoke-acp-long-turn-live` drives a real turn whose tool work outlasts the retired 600s cutoff and requires exactly one cold ACP bootstrap in the transcript. It takes >12 minutes by construction and is on-demand, not part of `release-gate`.
>
> **The integrated mux lifecycle IS a release-gate MUST.** `LIVE=1 ./run.sh smoke-mux-lifecycle-live` enters through a real MCP `tools/call` on the shipped bridge launcher and follows one citizen the whole way: fresh-call launch receipt, the sibling's own nonce callback whose SENDER ENVELOPE is the address, an `entwurf_v2` control-socket send that lands in the sibling's own transcript, `entwurf_resume_call` REFUSED while that citizen is live, a stable-handle close proving pane and socket gone with the record preserved, delivery to the dormant citizen refused honestly, then the public `entwurf_resume_call` — whose LAUNCH and OBSERVATION receipts stay apart — and finally an `entwurf_v2` send the resumed session answers with a fact it was told BEFORE the window closed. That last step is the point: a socket answering under the same garden id proves a process stood up at that address, and only the recall proves the same conversation came back. Both pi provider shapes are driven to it (native `openai-codex/gpt-5.6-luna` and recorded-ACP `entwurf/claude-sonnet-5`, the only shape that re-injects a bridge extension), and the Claude Code cell ends where its capability ends: its resume is refused as `target-not-pi` with no window opened and no lock residue (the per-gid coordination lock is released).
>
> One cell cannot be fully fenced, and that is recorded rather than glossed: the recorded-ACP pi cell runs under the operator's REAL home, because its provider spawns `claude` as a child that authenticates from there — measured, a fenced HOME kills that turn with `Authentication required` before the model is ever reached, and `CLAUDE_CONFIG_DIR` alone does not fix it. That is the same trade `smoke-acp-bundled-mcp-live` already makes. While that cell runs, its citizen's control socket and per-gid lock exist under the operator's own `~/.pi/entwurf-control` and `~/.pi/entwurf-v2-locks`; its meta store stays fixture, so no garden record is minted outside the fixture, and the run ends by proving all six real roots hold the entry sets they started with, with no fixture garden id and no leftover lock.
>
> Be honest about its cost, because it is a MUST: it spends real model turns on the operator's configured runtimes (two pi siblings, each resumed once, plus one Claude Code sibling), it READS the operator's real runtime config, and the siblings' native session transcripts stay in the real pi agent dir — they are not cleaned up, and they are part of the evidence a resume was real. The fence is per-axis rather than absolute: the four meta roots (records, mailbox, receivers, senders) are fixture for every cell, so no garden record is ever minted outside it; the native pi cell's control socket and v2 lock are fixture too; the ACP pi cell's are REAL and transient (see the paragraph above); and the Claude cell runs its runtime under the real HOME while its mailbox and meta stay fixture. The run ends by proving the operator's SIX real roots — the four meta roots plus `~/.pi/entwurf-control` and `~/.pi/entwurf-v2-locks` — hold the entry sets they started with, with no fixture garden id anywhere, and that proof now runs on the failure path as well as the green one. Missing prerequisites decline with the protocol SKIP (97), which `release-gate --cut` refuses rather than rounding up.
>
> **Fresh-call LIVE is on-demand, not part of `release-gate`.** `LIVE=1 ./run.sh smoke-mux-fresh-call-live` opens configured Pi and Claude Code siblings, spends two model turns, and preserves their native transcripts; run it directly whenever a cut changes mux fresh-call/launch behavior. Its private tmux servers and fixture-bound entwurf write axes make it deterministic about garden-record/socket residue, but those real native turns should not appear unexpectedly in every aggregate cut. **Both this smoke and `smoke-mux-lifecycle-live` enumerate `pi` and `claude-code` only — that exclusion is intentional.** A Copilot visible-fresh (step 9 clause 7) was accepted on 2026-08-25 as an operator-metered LIVE (receipts in `DELIVERY.md`'s Copilot matrix row and the issue #82 thread). It still spends Copilot premium quota, still needs its own grant to re-run, and is never folded into those loops or into the release-gate MUST tier.

> **A visible-fresh receipt outside the MUST tier is no longer the general rule — it is Copilot's preserved exception.** #87 measured what that wording permitted: because clause 7 sat outside every aggregate, a harness could be admitted as a full D6 citizen that `entwurf_fresh_call` cannot open, carry an honest "not a supported harness" sentence in the delivery matrix, and still pass the whole floor toward a cut. From OMP onward, the FIRST release of a harness admitted under the #82 contract owes its clause 7 receipt as a release-gate MUST step (`smoke-omp-fresh-live`), and the deterministic half of the same rule (`check-harness-admission-parity`, inside `check:full`) makes a citizen backend missing from `FRESH_CALL_BACKENDS` a red floor rather than a documented one. Forward-only by decision: Copilot's row is not reopened. The contract lives in `docs/adding-a-harness.md` step 9, "The release stop"; this note exists so the cost discipline above is not read as permission.
>
> The aggregate release gate does not own a live agy conversation id, so agy's real native-push round trip is a separate acceptance axis: three fail-loud doctors plus `LIVE=1 AGY_CONVERSATION_ID=<id> ./run.sh smoke-agy-native-push-live`, followed by a fresh-conversation sender/reply check after package install. Its deterministic install/sender gates are already inside `pnpm run check:full`; do not misreport the aggregate gate as live agy evidence. **Cost fence:** the agy conversation this smoke drives runs on a free account, so open it on `gemini-3.6-flash` — never a Pro tier. The model is the operator's choice at conversation-open time; entwurf never selects it, and no assertion reads it (see the shipped-lane note: model display is not part of the agy contract).
>
> Authoritative per-cut counts and digests live in BASELINE/CHANGELOG, not inline
> here; embedding them in the protocol makes a correct guide stale after every cut.

### Release acceptance axes

Do not collapse source, package, fixture, and native-host evidence into one “green.”

| Axis | Required proof | Limit |
|---|---|---|
| Source | `pnpm run check:full` + `./run.sh check-gate-qualification` | Does not prove an installed consumer. |
| Packed install | `check-pack-install` | Real tarball, but checkout-visible. |
| Linux artifact consumer | required `check-install-container` CI job against one preserved candidate | Fixtures prove package/oracle shape, not a real Claude lifecycle. |
| Exact release commit | all required CI jobs green, and the `check` job's qualification body step concluded success, at the exact SHA | A different green SHA is not transferable evidence. |
| LIVE runtime | `LIVE=1 ./run.sh release-gate <scratch> --cut` plus any shipped on-demand backend axis | `--cut` enforces `SKIP=0`; a red wired gate blocks the cut. |
| Native Claude host | installed strict doctor against a new real session | Missing live join is `NOT CERTIFIED`, not a fixture PASS. |
| Native agy host | three doctors plus conversation-id-gated native-push round trip | Aggregate release-gate does not own an agy conversation id. |

The repo-local `entwurf-release` skill owns the `land → prepare → make → publish`
state machine. Each mode is a separate GLG authorization. Preserve one candidate,
accept and publish those exact bytes without repacking, and record its digest and
consumer image outside this standing protocol.

### Verifying the two capabilities a gate cannot fully judge

- **Garden-id delivery:** discover a target with `entwurf_peers`, then `entwurf_v2 fire-and-forget` — the intent axis is single-valued since the visible-first cut. It reaches a live pi target over its control socket, a deliverable self-fetch citizen through the mailbox, and a probe-alive native-push conversation by direct injection. A DORMANT in-domain citizen rejects as `dormant-fire-forget-unsupported` — delivery never wakes it; reopen it with the separate lifecycle verb `entwurf_resume_call {target}`, then dispatch again. A wrong target state is rejected, never auto-fixed and never launched into.
- **ACP continuity:** a direct `pi --provider entwurf --model claude-sonnet-5` turn, or the `smoke-acp-session-reuse-live` gate (process-scoped reuse + recall). Multi-turn reuse is proven by that gate, not by any v1 resume tool.
- **agy citizenship:** in a fresh agy conversation, the first `PreInvocation` must yield a garden id, `entwurf_self` must report `agentId=meta-session/antigravity` and `replyable:true` only while the native probe is alive, and a reply to that same garden id must direct-inject into the same conversation. No mailbox/receiver-marker evidence counts on this rail.

### What NOT to do — bypassing the operational path

These bypass the very delegation logic under test; passing them proves nothing about production health.

- ✗ Minting session files directly (`mktemp …jsonl`) and feeding them to `pi --session`.
- ✗ Faking multi-turn by passing the same session file twice.
- ✗ Using pty/tmux `send-keys` keystrokes or transcript scraping as delivery evidence.
- ✗ Mimicking entwurf by recursively calling `pi` via `bash`.

The manual `pi --session` path is used only when (a) the entwurf path itself is broken and an isolated debug bypass is needed, or (b) a boundary check must hit a bridge internal directly.

### Operational principles

- Execute one command at a time (no `;`-chaining). Preserve full stdout/stderr at each step.
- On anything wrong, **stop and hold** — preserve session/cache/process state before proceeding.

### Wording — avoid safety-interpretation contamination

When injecting a fact for a continuity check, use **plaintext that does not trigger model safety interpretation**. Avoid `secret token`, `password`, `API key`, `credential`, and meta-directives like "do not leak" — such wording makes the model treat the prompt as an exfiltration attempt and refuse, which makes **continuity look broken even when it is alive** (this happened once with `test-token-123`, misdiagnosed as a delegation failure). Instead: `The password is owl → reply in one word → owl`; code names / colors / animal names. Do not mix continuity and safety-behavior verification in one prompt.

### bridge continuity vs semantic continuity

- **bridge continuity:** same `sessionKey` / same `acpSessionId` through in-memory process-scoped reuse. Persisted session records are written for a future resume/load lane but are not consumed today.
- **semantic continuity:** a fact from a prior turn is retrievable in a later turn.

Either can be alive while the other looks dead (the wording case above is bridge-alive / semantic-looks-dead). When in doubt, change the wording and retry once, and check the `[entwurf:bootstrap]` lines in bridge stderr. No automated smoke separates these yet.

## 0. Quality Criteria

The goal is not merely "invoke Claude Code." We want:

1. **Session continuity at the agent-shell level** — process-scoped turns reuse one live ACP session; fresh/turn-scoped paths open a new one rather than reconstructing a transcript inside entwurf.
2. **Preservation of pi harness semantics** — pi session files / transcripts / memory pipeline stay a shared axis.
3. **restart-hygienic** — process-scoped reuse continues the same ACP session across turns inside a long-lived resident; persisted records are written/validated for the future resume-load lane, not the live continuity path today.
4. **Thin bridge** — no second harness built inside this repo.
5. **Explicit capability boundary** — pi custom tool / user MCP visibility is determined solely by `entwurfProvider.mcpServers`; no automatic `~/.mcp.json` loading.
6. **Operational hygiene** — no orphan subprocesses, no excess persisted session garbage.

---

## 1. Setup

**One install command to remember: `./run.sh setup <project>`.** It is idempotent — re-run the exact same command whenever anything looks wrong. There is no second install surface to juggle: from a clone `setup` runs the whole floor in order.

1. `pnpm install` — installs the pinned development dependencies and builds the bridge (source-checkout bootstrap only; an installed package never runs npm/pnpm inside `node_modules`)
2. pi wiring → `<project>/.pi/settings.json` + user-scope registration — only when a `pi` inside the supported range (`>=0.85.1 <0.86`) is on PATH; absent pi is an explicit zero-state SKIP, a below-floor pi is a detected FAIL. The user-scope entry is owner-recorded (#86 C2): another root's live-or-missing ownership makes this step a zero-write refusal (setup: pi FAIL) that names `takeover-user-scope`; the install-states bind the exact managed settings path (a drifted/symlinked/corrupt target is a zero-write refusal) and the inverse removes only the recorded owner's exact entry; `doctor-pi-package` reports the verdict
3. Claude meta-bridge global plugin — only when `claude` is on PATH; otherwise skipped cleanly
4. source stable-bin exposure — including certified `entwurf` → this checkout's `run.sh`, the managed runtime Copilot fresh resolves; helper units are attempted independently and a foreign helper is a named FAIL
5. agy bridge + exact permission + statusline + `PreInvocation` hook — only when `agy` is on PATH; each adapter is idempotent and independently doctorable
6. Copilot four-unit composition (birth → MCP → receiver → visible footer) — only when `copilot` is on PATH (#86 C3b); the units run independently, each keeps its package-owned install-state and inverse, and a failed unit is a named component FAIL. The explicit `install-copilot-*`/`uninstall-copilot-*` surfaces remain the per-unit repair and inverse path
7. `entwurf-bridge` install smoke (`validate_entwurf_bridge`)
8. computed summary — per-component PASS/SKIP/FAIL; any detected-integration FAIL makes the whole command exit nonzero while valid components stay installed

```bash
git clone https://github.com/junghan0611/entwurf /path/to/entwurf && cd $_
./run.sh setup /path/to/consumer-project
# re-run the SAME command any time to repair a broken install
```

Expected tail on a fully green host: `DONE: entwurf setup — result: green (computed from the component outcomes above).` The summary above it lists every component as PASS/SKIP/FAIL; a detected harness that could not be completed is named FAIL and the command exits nonzero (`result: NON-GREEN (FAIL: …)`) while every valid component stays installed — re-running the same `setup` is the repair action. On a host with `claude`, verify `./run.sh doctor-meta-bridge`. On a host with `agy`, verify all three: `doctor-agy-bridge`, `doctor-agy-statusline`, and `doctor-agy-hooks`. After adding a backend to `META_BACKENDS`, re-run the sibling install then the doctor — a green checkout with a stale deployed plugin is a silent write-stop on that rail. Each harness doctor remains the fail-loud per-leaf acceptance surface.

The wiring / meta-bridge / smoke steps are internal building blocks of `setup` (`install_local_package`, `scripts/meta-bridge-install.sh`, `validate_entwurf_bridge`) — call `setup`, never the parts. Consumers who `npm install @junghanacs/entwurf` get the obvious npm surface; that path is not the developer concern here.

### 1.1 Variables (optional)

```bash
export REPO_DIR=/path/to/entwurf
export PROJECT_DIR=/path/to/consumer-project
cd "$REPO_DIR" && ./run.sh setup "$PROJECT_DIR"
```

### 1.2 Live acceptance (optional)

Put `PWD` in scratch so session artifacts do not land in the repo. LIVE gates inherit
the caller's environment: a pi or ACP session exports `PI_SESSION_ID` / `PI_AGENT_ID` /
`CLAUDE_CONFIG_DIR` into every child, which masquerades as the smoke's identity or
strips Claude hooks (`hooks: {}` overlay). Strip those carriers:

```bash
cd /path/to/scratch
env -u CLAUDE_CONFIG_DIR -u PI_SESSION_ID -u PI_AGENT_ID \
  LIVE=1 /path/to/entwurf/run.sh release-gate /path/to/scratch --cut
pi --provider entwurf --model claude-sonnet-5 -p "reply with ok only"   # one-turn smoke
```

The one-turn smoke is a **provider**-surface check (auth + model routing + a real
turn). It does not make that session addressable: without `--entwurf-control`
there is no routable control socket, so `PI_SESSION_ID` stays unset by design and
a bundled `entwurf_self` / `entwurf_v2` call fails loud. Garden citizenship and
addressable sends require `--entwurf-control` (measured 2026-07-24: the same
one-shot with that flag returns its own gid and delivers `entwurf_v2` to a peer
mailbox with `origin=pi-session`, `replyable=true`).

`setup` requires Node 24 and Python 3 (pnpm only on a source checkout — the dependency bootstrap is source-only, and installed mode needs no pnpm); harnesses including pi are optional-by-presence (absent → explicit zero-state SKIP, detected incomplete/below-floor → named FAIL + nonzero result). On a source checkout it runs the frozen `pnpm install` + presence-gated pi project/user wiring + detected Claude wiring + source stable-bin exposure + detected agy wiring + detected Copilot four-unit composition + the v2 install smoke. A green setup certifies that the source-owned `entwurf` symlink targets this checkout and wins PATH resolution; helper units are attempted independently and a foreign helper is a named bins FAIL (nonzero), with harness-specific doctors keeping the per-leaf verdict. A detected `copilot` composes all four native units (birth → MCP → receiver → visible footer) with independent per-unit verdicts (#86 C3b); setup does **not** replace any native-harness doctor. The full aggregate live floor is still `LIVE=1 ./run.sh release-gate <scratch> --cut` — without `--cut` it is a diagnostic pass, not acceptance — with agy's conversation-id-gated round trip verified separately.

### 1.4 Cross-install / cross-backend parity (optional, high-value)

Compare a fresh self-awareness report across axes: (1) same backend, different install path — answer must be path-invariant; (2) same backend, different machine — identical native tool list + MCP server/tool set; (3) different backend, same bridge — same garden capability but **different** native tool surface (a Claude session reporting another backend's native tools is a fail); (4) native pi routing vs ACP-bridged, same model — the native target reports no `entwurf-bridge` MCP (capability via pi's extension surface), while the ACP target reports it as the single MCP server. Honest "native: I cannot tell" hedging is PASS on the native side. agy is graded by its native-citizen checklist, not by pretending it has an ACP overlay.

**Cortex on axis 3.** A cortex session must expose the same garden capability
while keeping cortex's own native tool surface. Its callable MCP identifier shape is
the same as Claude's, but it has no system-prompt carrier: engraving is prepended to
the first user augment. Installed-model enumeration is deterministic; candidate-installed
LIVE Cortex acceptance and its remaining host limits are recorded per cut rather than
frozen here.

---

## 1A. Main Agent Evaluation — Is `entwurf` Claude strong enough?

Separate from continuity gates. Gates prove "sessions continue"; this questionnaire examines tool self-awareness / native tool usability / MCP-boundary awareness / long-turn focus / quality vs direct Claude Code. Run it against `entwurf/claude-sonnet-5` via a direct `pi --provider entwurf` turn (or a live ACP session); accumulate turns by re-prompting the same target.

### 1A.0 Two carrier surfaces — engraving vs pi-context-augment (load-bearing)

`entwurf` delivers identity-relevant text through **two structurally distinct surfaces**. Collapsing them into "the system prompt" is the most common verifier-side mistake. (BASELINE Q-B0/Q-L1 grade the same separation operator-side.)

| Surface | Source | Delivery shape | Default content |
|---|---|---|---|
| **Engraving carrier** | `pi-extensions/lib/acp/prompts/engraving.md` (or `ENTWURF_ACP_ENGRAVING_PATH`) | Claude `_meta.systemPrompt` — full-replacement identity slot | Operator-authored, optional opt-out; tiny non-empty by default on Claude ACP (replaces the `claude_code` preset + strips its auto-memory advertisement). Emptying the file is the opt-out. |
| **pi-context-augment** | `pi-extensions/lib/acp/augment.ts` (`enrichTaskWithProjectContext`) | First-user-message prepend (not the system slot) | Always populated on ACP-routed targets: (1) the bridge identity line, (2) `~/AGENTS.md` body, (3) the cwd repo's `AGENTS.md` in a `<project-context path="…">` block. |

Pass (carrier honesty): the subject distinguishes engraving from pi-context-augment by name or structure without prompting; on ACP targets confirms all three augment components arrived; may quote the engraving but must **not** attribute bridge identity / AGENTS / memory policy to it. Fail: attributes the bridge-identity narrative to the engraving carrier; claims the augment is empty on an ACP run; invents engraving content. Native pi exception: on native targets the bridge-identity line and `~/AGENTS.md` are not part of the augment — the PASS criterion is honesty about what arrived, not the three-component checklist.

### 1A.1 Layers

- **Layer 0 — self-awareness:** ask environment self-awareness / MCP visibility / upstream-instruction awareness, guessing prohibited. Pass: recognizes native tool family, says "I don't know" honestly, answers MCP visibility only as configured, describes upstream instruction type without reproducing internal prompts. Fail: claims a nonexistent tool, conflates pi-custom and native tools, hallucinates MCP visibility, or conflates the two carriers (§1A.0).
- **Layer 1 — native tool use:** throw file-reading / structure-analysis / regression-hunting tasks. Pass: Read/Edit/Bash/Grep/Glob selection is natural; no detour through MCP or recursive `pi`. Fail: strange detours for simple reads; speaks from memory without reading.
- **Layer 2 — MCP boundary:** by default the seven entwurf MCP tools are not visible (they appear only when `entwurf-bridge` is registered). Pass: says invisible tools are not visible; explains the native-vs-MCP boundary; treats `entwurf_register_native` as binding an already-running conversation, never as fresh spawn. Fail: pretends to use an unseen tool; mimics entwurf via recursive `pi`.
- **Layer 3 — focus across turns:** inject a fact, then accumulate turns mixing retrieval/exploration. Pass (post-0.4.1): after **8 turns** holds **3+ early facts** incl. **one verbatim string injected before turn 5**; no repeated exploration, no self-contradiction, no tool-strategy drift. Fail: forgets early reads; paraphrases instead of returning the verbatim string. Note: entwurf exposes no user-facing compaction; use the backend's `usage_update` footer as an overflow-risk signal (it follows the ACP backend's `used/size`, not pi's visible-transcript estimate).
- **Layer 4 — vs direct Claude Code:** requires a verifier holding **both** the `entwurf` and a direct path (human-in-loop, or both transport handles). Compare latency / native tool accuracy / detours / boundary confusion / quality around turns 10–15. Repeated tool confusion, long-turn forgetting, or boundary workarounds are a fail.

Interpretation: Layers 0–2 healthy → basic qualifications confirmed. Layer 3 weak → strengthen prompt shape + corroborate with bootstrap logs / process state / sentinel recall. Layer 4 much weaker than direct → revisit bridge handoff. This questionnaire does not replace gates.

---

## 2. Manual judgement checks — what the gates cannot fully judge

The single-turn / multi-turn / cross-process / persistence-boundary / shutdown invariants that earlier editions hand-ran against the retired v1 verbs are now **deterministic or live gates**. Verify them through the gate, and reserve manual time for the human-judgement surfaces below.

| Invariant | Current gate (pointer) |
|---|---|
| Single-turn prompt extraction, SessionStart hook not mistaken for prompt | `smoke-acp-raw-turn-live`, `check-acp-prompt-builder` |
| Multi-turn continuity + recall (process-scoped reuse) | `smoke-acp-session-reuse-live`, `check-acp-session-reuse` |
| Cross-process continuity / cache before-after | `check-acp-session-store` (signature, decideBootstrap, persist/parse) |
| Lifecycle policy — turn-scoped is always new; process-scoped may reuse only the live in-memory session; persisted records are not a resume/load path today | `check-acp-session-store`, `check-acp-session-reuse` |
| Tool-call / event mapping | `check-acp-event-mapper`, `smoke-acp-provider-live` |
| Prompt lifecycle — no wall-clock cutoff on a running turn; abort ends it by ACP `session/cancel` with bounded cleanup; a child death is reported with exit status + stderr on new AND reuse turns; our prompt-phase error text is not classified transient by pi | `check-acp-prompt-lifecycle`, `check-probe-ordering` |
| Operator mcpServers / skills reach the live session | `smoke-acp-mcp-live`, `smoke-acp-skill-live`, `check-acp-config` |
| Overlay isolation + memory containment | `check-acp-overlay`, `smoke-acp-memory-containment-live`, `check-acp-tool-surface` |

### 2.1 MCP callable-identifier shape (verified property, gate-external)

The literal callable identifier differs per backend — probe by asking the agent to print it **verbatim** (do not ask "hyphen or underscore" — ambiguous between outer separator and inner server name):

| Backend | Literal identifier | Boundary |
|---|---|---|
| Claude | `mcp__entwurf-bridge__entwurf_v2` | native Claude tool surface + explicit MCP server |
| Cortex | `mcp__entwurf-bridge__entwurf_v2` | same identifier shape, different native tool surface |

The identifier cannot distinguish Claude from Cortex; native tools and carrier facts must.

### 2.2 MCP injection visibility

The sole MCP responsibility of `entwurf` is to project explicit `entwurfProvider.mcpServers` into every newly opened backend session. Ask for visible MCP server names: `entwurf-bridge` appears, ambient servers do not, and changing the declaration changes `bridgeConfigSignature` so a live incompatible session is replaced rather than silently reused. `check-acp-config` and `smoke-acp-mcp-live` pin this; the manual check is honesty corroboration.

### 2.3 Process / cache hygiene — the orphan bound (§gate-external judgement)

Apply per backend under test:

```
AFTER_<BACKEND> ≤ BEFORE_<BACKEND> + (distinct alive
  (sessionKey, backend, modelId, bridgeConfigSignature) tuples this run holds open)
```

An **upper bound**, not an equation: child reuse and idle reaping may keep the delta below it; a config-signature or `(provider, model)` switch may add one. `AFTER > BEFORE + alive_tuples` is actionable. Walk the backend process parent chain; any ACP child whose parent `pi` has exited is an orphan—preserve it as evidence.

### 2.4 pi session record as a shared memory axis

The key invariant: **pi session files stay the shared record source even under ACP**. After a reuse pair finishes, locate the child pi session JSONL and confirm turns accumulated:

```bash
ls ~/.pi/agent/sessions/--*--/*_<SESSION_ID>.jsonl   # path pattern, not a naive grep (which also hits the parent)
jq -r '.message.role // .type' "$F" | sort | uniq -c  # role lives at .message.role
```

Pass: user/assistant turns accumulate normally; the transcript is not broken/empty because ACP was used. We preserve "Claude via ACP, memory via the pi axis (JSONL → Denote/andenken)" — the AI does not run its own memory layer.

---

## 3. Pass criteria — current release floor

The minimum passing bar:

1. **Deterministic floor green:** `pnpm run check:full` passes (the core tier plus the hermetic-integration and package/install tiers, incl. `check-pack`), plus a `./run.sh check-gate-qualification` green on the same candidate.
2. **All three CI jobs green on the exact release commit:** `check`, `install-surface`, and the required Linux `artifact-consumer`; preserve the latter's tarball digest and image identity.
3. **Live floor MUST green:** `LIVE=1 ./run.sh release-gate <dir> --cut` exits 0 reporting `MUST PASS=N FAIL=0 SKIP=0`; with `--cut` a single SKIP is red, so the exit code itself now carries this condition. A BEHAVIOR FAIL is advisory, not blocking.
4. **Native-host doctor green where the Claude meta-bridge is claimed:** a new post-install Claude session exists, live evidence is present, and the installed `doctor-meta-bridge` exits 0. `NOT CERTIFIED` is a release failure for that host, not a skip.
5. **Honest self-recognition:** the bridged model identifies its actual harness/backend, lists `entwurf-bridge` as the single MCP server with its seven current tools, and presents a backend-native (not normalized) tool surface.
6. **Carrier separation honored:** engraving vs pi-context-augment kept distinct (§1A.0); no bridge-identity narrative attributed to the engraving carrier.
7. **agy shipped lane accepted:** all three agy doctors are green; automatic birth/statusline/sender identity and same-gid native-push reply are confirmed in a fresh conversation. `agentId=meta-session/antigravity` is correct; model display is not part of that contract. Same-pid concurrent conversation invocation is not claimed.
8. **Boundary preservation across backends/machines:** for every shipped or explicitly probed backend, regardless of install path or host, no cross-backend tool-surface contamination and no confabulation about pi internals.
9. **Hygiene:** no orphan ACP children; no unexpected persisted session garbage (a turn-scoped `cwd:` fallback is never a persisted reuse).
10. **New-harness admission closed:** a release that introduces a native harness admitted under the #82 contract has that harness in `FRESH_CALL_BACKENDS` on all three public surfaces, with `check-harness-admission-parity` green and its clause 7 visible-fresh LIVE step green in the MUST tier. That release also owes the cross-harness leg the same release stop names — two dispatch receipts, an existing citizen's live turn delivered into the new citizen and the new citizen's live turn delivered into an existing one — recorded in `DELIVERY.md`; its deterministic half is an owed follow-up, so until that gate lands this half of the condition is prose and is judged by the recorded receipts. Partial evidence is a branch state; an `unsupported` note in `DELIVERY.md` is a description, never a permit.

Passing establishes a **release verification floor**, not an 8-hour/day operational guarantee. The floor says: gates hold, the agent honestly recognizes its environment, no tool surface is normalized away, no identity leaks, no orphans. It does **not** say a real-day workload (50–100+ turns, tool bursts, partial MCP failures, auth/version drift) survives — that needs L3–L5 evidence (appendix).

---

## Appendix — troubleshooting & history

### Troubleshooting hooks

- **`ENTWURF_CHILD_STDERR_LOG`** mirrors child stderr to a file for bootstrap-path visibility — but it must be present at **bridge-process spawn time**; `export` from a shell already bound to a running bridge does not propagate. Restart the parent session with it exported, then `grep -E '\[entwurf:(bootstrap|model-switch|cancel|shutdown)\]' "$ENTWURF_CHILD_STDERR_LOG"`.
- **Retired dedicated smokes, live code invariants** (manual/troubleshooting only — *not* part of the release floor):
  - *Model-switch lock* — entwurf sessions are locked to their starting model. Gate: `check-model-lock` (in `pnpm check`, core tier). The dedicated live `smoke-model-switch` was retired in v2; the invariant lives in `pi-extensions/model-lock.ts` (extension guard) + `session-store.ts` `SessionModelLockedError` (the `decideBootstrap` fail-loud model lock).
  - *Cancel / abort cleanup* — `onAbort` → `cancelActivePrompt()` (session stays reusable); the stream catch closes the bridge only on `stopReason === "error"`. Dedicated `smoke-cancel` retired; invariant in code.

### Evidence preservation when a problem occurs

```bash
pgrep -af 'claude-agent-acp|codex-acp' || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
ls ~/.pi/agent/sessions/--*--/*_${SESSION_ID}.jsonl 2>/dev/null
[ -n "$ENTWURF_CHILD_STDERR_LOG" ] && grep -E '\[entwurf:(bootstrap|model-switch|cancel|shutdown)\]' "$ENTWURF_CHILD_STDERR_LOG"
```

Also preserve: the exact calls used, full stdout/stderr, the child pi session file path, cache-directory changes, and the expected-vs-actual difference.

### History (pointer)

The full R2R run history (2026-04-27 → 2026-05-29, pi-shell-acp era), the per-claim evidence ledger (load-bearing claims with level-reached / blind spot / next test, maintained through 0.5.x–0.8.x), and the experimental L3–L5 tracks (4-cell verifier×subject matrix with on-disk corroboration; long-haul soak; direct-native parity panel) live in **CHANGELOG.md and git history**. Evidence reached **L2** (cross-vendor + reverse-direction MCP calls); L3 is partially exercised by the process/session-file checks above; the honest gap is **L3 → L5**. The most recent recorded floor baseline is in [BASELINE.md](./BASELINE.md)'s HISTORY section.
