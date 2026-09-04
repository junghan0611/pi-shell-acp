#!/usr/bin/env bash
#
# Model id convention (see AGENTS.md Hard Rule #1):
#   - User-facing examples use the qualified form `entwurf/<backend-model>`
#     (e.g. `entwurf/claude-sonnet-5`); the prefix routes to this provider
#     so `--provider` is redundant and is dropped in docs.
#   - Smoke helpers that feed `ensureBridgeSession({modelId})` directly (cancel,
#     model-switch) pass BARE backend ids (`claude-sonnet-5`, `gpt-5.4`)
#     because the bridge library contract is bare. Smoke helpers that invoke pi
#     via the CLI still pin `--provider entwurf` and can accept either
#     bare or qualified model, but we keep bare here to match the bridge-level
#     dispatch tables.
#
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
  TARGET="$(readlink "$SOURCE")"
  case "$TARGET" in
    /*) SOURCE="$TARGET" ;;
    *) SOURCE="$DIR/$TARGET" ;;
  esac
done
REPO_DIR=$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)
PROJECT_DIR_DEFAULT=$(pwd)
TARGET_PROJECT_DIR=${2:-$PROJECT_DIR_DEFAULT}
# npm publish identity. Scoped 2026-05-18 — bare `entwurf` was not on npm
# and we adopted the same `@junghanacs` scope as the OpenClaw plugin sibling
# (`@junghanacs/openclaw-entwurf`) for source-of-origin parity. This
# variable documents intent; check-pack-install hardcodes the tarball name
# and install path against the same scope for traceability.
PACKAGE_NAME="@junghanacs/entwurf"
# Runtime provider id — DO NOT change. Embedded in model strings
# (`entwurf/claude-sonnet-5`), settings keys (`entwurfProvider`),
# log prefixes (`[entwurf:bootstrap]`), and the `--provider entwurf`
# CLI surface. Renaming this would break every consumer transcript and every
# saved session anchor.
PROVIDER_ID="entwurf"

# THE strip-types fence, in one place. Node REFUSES `--experimental-strip-types`
# for any .ts below node_modules (ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING), so
# an installed package MUST run the prepack-emitted JS twin — the same boundary
# start.sh (0.12.1), the store-doctor (0.12.4), the plugin hook (0.12.5), and the
# agy imprint (0.12.7) each cross. Every .ts entrypoint routes through here so a
# NEW one cannot silently reintroduce the class: it was hand-written per surface
# before, and three operator commands (doctor-pi-provider / new-session-id /
# meta-bridge-prune) shipped dead under node_modules because of exactly that.
#
# A dev-only gate has no emitted twin by design (check-*/smoke-* are not shipped
# surfaces). Under an installed package it REFUSES rather than falling back to raw
# .ts — a fallback would just re-raise the fence error with a worse message.
# check-install-surface pins both halves statically.
# Release-gate STEP OUTCOME protocol (P1) — loaded LAZILY, never at top level.
#
# Only two surfaces need it: `release_gate`, which classifies each step's exit
# code, and the LIVE smoke wrappers, which return `$ENTWURF_STEP_SKIP_EXIT` when
# a prerequisite is missing. Both are dev-only. Sourcing it unconditionally at
# the top made EVERY subcommand depend on `scripts/lib/` being present, and
# check-fresh-cut-gate I9c caught the consequence immediately: on an installed
# tree assembled without that path, run.sh died with a bash "No such file"
# instead of printing the refusal it is supposed to print. An operator verb must
# never fail on a dev-only dependency, so the load happens where it is used.
entwurf_require_step_outcome() {
  [ -n "${ENTWURF_STEP_SKIP_EXIT:-}" ] && return 0
  # shellcheck source=scripts/lib/step-outcome.sh
  . "$REPO_DIR/scripts/lib/step-outcome.sh"
}

run_ts() {
  local rel="$1"; shift
  case "$REPO_DIR" in
    */node_modules/*)
      local dist="$REPO_DIR/mcp/entwurf-bridge/dist/${rel%.ts}.js"
      if [ ! -f "$dist" ]; then
        echo "entwurf: '$rel' is a dev-clone-only surface — the installed package ships no compiled twin." >&2
        echo "         (Node cannot strip types below node_modules; run this from a checkout.)" >&2
        return 1
      fi
      (cd "$REPO_DIR" && node "$dist" "$@")
      ;;
    *)
      (cd "$REPO_DIR" && node --experimental-strip-types "$rel" "$@")
      ;;
  esac
}

# Vitest-backed gate lanes (issue #62). Same authority boundary as run_ts's dev-clone
# refusal: vitest is a devDependency, so an installed package has no runner and the
# gate refuses legibly instead of silently passing or crashing on a missing binary.
run_vitest() {
  case "$REPO_DIR" in
    */node_modules/*)
      echo "entwurf: this gate is a dev-clone-only surface — vitest is a devDependency the installed package does not ship." >&2
      echo "         (Run it from a checkout after 'pnpm install'.)" >&2
      return 1
      ;;
  esac
  local bin="$REPO_DIR/node_modules/.bin/vitest"
  if [ ! -x "$bin" ]; then
    echo "entwurf: vitest is not installed — run 'pnpm install' in the checkout first." >&2
    return 1
  fi
  if [ -n "${ENTWURF_MUTATION_VITEST_REPORT:-}" ]; then
    # Qualification asked for structured attribution: a kill is attributed from the
    # failed TEST TITLES in this report, never from Vitest's code frame (which quotes
    # the source lines around the assertion — including an adjacent PASSING test's
    # [QK:…] title). The marker declares the lane structured; the report goes to a
    # FILE because the runner merges stdout+stderr and one warning line ahead of the
    # JSON would break the parse. Human output still rides stdout.
    echo "__ENTWURF_VITEST_JSON__"
    (cd "$REPO_DIR" && "$bin" run --reporter=default --reporter=json \
      --outputFile.json="$ENTWURF_MUTATION_VITEST_REPORT" "$@")
    return
  fi
  (cd "$REPO_DIR" && "$bin" run "$@")
}

usage() {
  cat <<'EOF'
Usage:
  ./run.sh setup [project-dir]        # ONE presence-driven composition (#86): mode-first (source bootstrap only on a checkout), then per-component PASS/SKIP/FAIL for pi (presence+floor)/claude/agy/copilot (all four units: birth→MCP→receiver→footer, independently)/omp (four units: birth→MCP→tools.xdev setting→receiver, independently) + stable dev bins + v2 install smoke; absent harness = zero-state SKIP, detected-incomplete = named FAIL + nonzero exit. Never installs a harness or touches credentials
  ./run.sh release-gate [project-dir] [--cut] [--allow-skip-gemini]  # SINGLE release gate: full static (pnpm run check:full) + the v2-native live gates (v2 matrix-live, check-bridge, doctor-pi-provider, RGG) + the ACP plugin acceptance floor (12 LIVE smokes: socket-citizen/raw-turn/overlay/provider/session-reuse/carrier-augment/memory-containment/rgg/mcp/skill/bundled-mcp/v2-send) + the one surviving axis the aggregate used to omit silently (claude-native-resume; Cortex stays a documented on-demand direct call) + the cross-harness delivery chain (smoke-entwurf-chain-live). TWO-TIER summary: MUST (release-blocking, owns the exit code — "green" applies here) + BEHAVIOR (advisory, non-blocking: RGG positives model-in-loop turn). STEP OUTCOME protocol: every step is INVOKED and reports its own PASS / SKIP (exit 97, a prerequisite it does not have) / FAIL — a skip is never counted as a pass. Without --cut this is the unattended diagnostic (SKIPs reported, exit 0). WITH --cut it is read as release acceptance and ANY MUST SKIP is red, which is what makes "a CUT needs LIVE=1, SKIP=0" executable instead of prose. --allow-skip-gemini accepted-but-ignored (back-compat). final cut authorization is GLG's.
  ./run.sh check-bridge               # entwurf-bridge direct MCP smoke + protocol/negative-path test.sh (live substrate = v2 live smokes)
  ./run.sh check-entwurf-bridge-boot # deterministic gate (5d-5-pre, G1a/G1b/G1e/G1f, IN pnpm run check:full): boot start.sh under strip-types + assert v2 fence graph loads + entwurf_v2 and entwurf_resume_call registered/schema + the tools/list surface is EXACTLY the seven shipped garden verbs; tools/list only, no auth/side-effect
  ./run.sh check-entwurf-bridge-pi-free # deterministic gate (0.12.1 A, IN pnpm check): static — bridge index eager value-import closure must carry no @earendil-works/pi-* (type-only + dynamic import excluded); proves the meta-bridge boots pi-free
  ./run.sh check-model-lock           # deterministic unit test for pi-extensions/model-lock.ts (4-quadrant + edge cases, no API)
  ./run.sh check-shell-quote          # POSIX-safety gate for shellQuote (remote SSH arg quoting in entwurf paths) — source parity + behavior matrix, no SSH
  ./run.sh check-entwurf-session-identity # deterministic gate for record-era session identity (garden-id grammar + readSessionIdentity: first-model_change authority, name-blind — #50 C3), no API
  ./run.sh check-meta-session          # deterministic gate (#30 step 2, V3-only): fs store — idempotent decideUpsert/upsertMetaSession + mailbox enqueue/read + receipt state, no API
  ./run.sh check-meta-v3-record        # deterministic gate: the ONE live record schema (v3) — canonical serialize/round-trip/mint, foreign-generation rejections name fresh-cut with the actual version value, strict keyset, no API
  ./run.sh check-mailbox-receipt-state # deterministic gate (0.11 Stage 0 step 3B): mailbox receipt state schema + store (stamp→persist→read-back) in a temp mailbox, strict keyset, no API
  ./run.sh check-copilot-birth-hook   # #82 gate: drives the real Copilot assembler into a temp dir, fires the baked launcher with NO ARGV (the way Copilot's `exec`-string schema forces), and requires a backend:"copilot" v3 record + attach + peer row + a SENDER marker the resolver joins back to that record, and still zero mailbox/receiver marker (who-sent needs a shared parent; a receiver needs a doorbell this backend has not got). Hermetic; no Copilot, no model turn
  ./run.sh check-omp-birth-hook       # #87 gate: drives the real OMP assembler into a temp dir, imports the ASSEMBLED index.ts into a MOCK omp host and fires session_start/session_switch. tui mints one backend:"omp" record + a sender marker keyed to the host's OWN pid (the one-process join) + the garden id on the status line; print/rpc/json mint NOTHING (hasUI is true on the rpc rows, as in the vendor); switch attaches on the same native id and mints the replacement on a new one; the CERTIFIED receiver reader still finds no marker. Also the four-root joint binding: extension and omp-labeled bridge child resolve the same sessions/mailbox/senders/receivers bundle against test-built literals (never the production resolver as its own oracle), under a poisoned PI_CODING_AGENT_DIR and under four distinct ENTWURF_META_* overrides; the override grammar is absolute-or-~ and both halves plus the doctor refuse anything else by name; and a drifted provenance label selects no root policy at all. Hermetic; no omp, no model turn
  ./run.sh check-copilot-receive-arm  # #82 RAIL 5 gate: the REAL receiver installer + the REAL extension.mjs forked with a stubbed SDK. Arms only after birth, marker owned by the WATCHER pid, self-fetch dispatch answer, doorbell carries the garden id and NOT the body, id-drift/foreign-parent refusals. Hermetic; no Copilot, no model turn
  ./run.sh check-copilot-launch       # #82 RAIL 7 gate: the MANAGED launch `entwurf copilot`, driven through its public address against a FAKE VENDOR on a sandbox PATH. Receiver precondition refusals, EXTENSIONS token + operator token preservation, injected defaults before the `--` terminator, byte-identical argv, the 11 explicit permission/surface policy overrides that suppress `--yolo`, exec (not fork) pid identity, exit passthrough, recursion refusal. Hermetic; no Copilot, no model turn
  ./run.sh check-copilot-statusline   # #82 Copilot custom-footer renderer. session_id → ready/?/gid + rail `cop`; exit 0. IN pnpm check. No Copilot, no model turn
  ./run.sh check-entwurf-capabilities  # deterministic gate (0.11 Stage 0 step 3C): backend capability registry (pi/entwurf-capabilities.json) — coverage==META_CITIZEN_BACKENDS + agrees with live META_BACKEND_DESCRIPTORS + strict keyset, no API
  ./run.sh check-omp-fresh-preflight   # #87 C: the OMP fresh preflight reproduces omp_agent_dir and the tools.xdev read in TS (it runs from two emit depths and cannot call a sibling script). This drives the SHIPPED shell/python leaves over the same inputs — refusals included — and requires the TS half to agree, so the reproduction cannot silently drift from the installer's own oracle
  ./run.sh check-harness-admission-parity  # #87 C: the EDGE the two closed parity loops never had. Every citizen backend is fresh-openable or a declared pre-#82 legacy admission whose exception a reader finds in DELIVERY.md — so a post-contract harness that mints records but cannot be opened by entwurf_fresh_call blocks the release package instead of only carrying an `unsupported` note (docs/adding-a-harness.md step 9)
  ./run.sh check-capability-bundle-reach # deterministic gate (IN pnpm check): re-ask EVERY shipped copy of meta-session (source + bridge bundle emit) whether metaCapabilitiesFilePath() reaches the registry — the artifact-depth check the source-path gates cannot make; needs a built dist, missing dist FAILS
  ./run.sh smoke-pi-attach            # deterministic gate (#50 C2 checkpoint + C3 ACP tail): a pi session attaches as a V3 meta-record citizen (backend:"pi"), the gardenId is the RECORD's not pi's session id, the control socket is keyed on it, a re-open ATTACHES to the same address (never a second mint), the BUILT DIST ENTRY driven over MCP stdio lists the citizen + delivers entwurf_v2 to that socket with an RPC ack, and the ACP identity chain lands a send AS the host record (enrichMcpServersWithEnvelope env → bridge sender = host gardenId). mkdtemp-isolated; the live store is never read
  ./run.sh check-bridge-delivery      # deterministic gate (IN pnpm run check:full): demo scene 3 recovered — seed strict meta-sender + armed receiver citizens in an isolated temp world, scrub ambient pi/sender carriers, drive the BUILT DIST ENTRY over MCP stdio through a real tools/call entwurf_v2, assert the .msg landed under the seeded sender + doorbell poked. DELIVERS through the artifact, not from source. ENTWURF_DELIVERY_SUBJECT=<launcher> replays the same scene against another consumer artifact (check-pack-install passes the npm-installed bin). No model/network/cost; stale or missing dist FAILS
  ./run.sh check-meta-mailbox-state-write # deterministic gate (0.11 Stage 0 step 3D-4 commit2): post-cut receipt is state-only — meta-record file byte-identical across enqueue/read, state carries lastEnqueuedAt/lastReadAt (field isolation), empty inbox no-op on record+state, drift surfaces; no API
  ./run.sh check-meta-receiver-marker # deterministic gate (SE-2): receiver marker round-trip/start-key/provenance, UserPromptSubmit cannot mint presence, reader does not gate on record existence — marker SEMANTICS only; launch topology moved to check-hook-launch-topology
  ./run.sh check-hook-launch-topology # #51 gate 1: shipped hooks.json is exec form through hook-launch.sh, launcher is loud on an empty argv (older Claude's silent args drop), exec preserves the pid so the hook's parent is Claude, and a space/$/backtick plugin path survives as one argv element
  ./run.sh check-meta-hook-session-switch # #101 gate: ONE Claude pid, TWO SessionStarts (resume picker placeholder -> resumed id). The hook retires the marker of the garden it stopped serving (records untouched, same-garden re-registration retires nothing), the reader stays fail-closed on a re-planted stale marker (watchArmed measured against the owner's sender marker, never copied), production dispatch refuses the retired garden and NAMES the failing axis, and exactly one of the two gardens is deliverable. Sandboxed roots, no API
  ./run.sh check-meta-identity-consumers # deterministic gate: V3-only consumer seam — per-entry targeted read + addressable read snapshot uniqueness, non-regular rivals never read, drift/unparseable rivals unreachable, unreadable regular rivals fail loud; strict upsert refuses an unreadable store before any write, no API
  ./run.sh check-meta-capability-source # deterministic gate (0.11 Stage 0 step 3D-3): capability-source cut-over — mint/parse read wakeMode/deliveryLevel from the registry (metaCapabilityFor, registry-driven via injection), not META_BACKEND_DESCRIPTORS; behaviour-preserving (registry ≡ const); the record.delivery slot 3D-3 preserved was deleted by 3D-4, no API
  ./run.sh check-socket-probe          # deterministic gate (0.11 Stage 0, F3): three-valued control-socket liveness (alive|dead|indeterminate) — GC reclaims dead only, indeterminate survives; pure classify + 2-socket integration, no API
  ./run.sh check-project-trust-handler # deterministic gate (0.11 Stage 0, Trust 2층): project_trust handler — decideProjectTrust matrix (escape=inherited-false+interactive+trust-here→{yes,remember:true}; non-interactive→undecided; never undefined) + adapter single-writer, fake prompt, no UI
  ./run.sh check-entwurf-v2-contract   # deterministic gate (0.11 Stage 0 step 4-pre, 동결결정 10 + Fable R1-R5): FROZEN entwurf_v2 contract — R1 control-socket domain (currently pi; claude/codex/agy=unsupported, not folded), 3-cell intent×liveness table (single verdict, 1 allow/2 reject after the visible-first cut), N1 indeterminate-no-spawn, R3 table↔receipt round-trip, R5 taxonomy, schema↔types drift; pure, no API
  ./run.sh check-entwurf-v2-lock       # deterministic gate (0.11 Stage 0 step 5a, 버킷 B F2): per-gid dispatch LOCK primitive — openSync wx atomic acquire, second-acquire=target-locked conflict (holder JSON for human cleanup), nonce-owned release (successor survives late release), stale reclaim same-host+ESRCH-only (EPERM/remote/alive/unknown fail-closed), empty/corrupt=conflict not auto-deleted, F2-P1 malformed gid throws; real temp dir, deps injected
  ./run.sh check-entwurf-v2-decider    # deterministic gate (0.11 Stage 0 step 5b): PURE dispatch decider decideDispatch — frozen 7-step order over injected fakes, lock acquire+release tracked so reject⇒no-plan-no-lock proven; pre-probe rejects observedLiveness=null, send/resume execute keep lock + mailbox no-lock (？7), resume plan no mode/provider/model, invalid gid throws (F2-P1); pure, no IO
  ./run.sh check-entwurf-v2-matrix     # deterministic gate (0.11 Stage 0 step 5d-5 a): REACHABILITY + LOCK SSOT table — drives REAL decideDispatch over fakes, fixes every (target kind → transport → lock class) cell as one table (control-socket/meta-mailbox/native-push + bad-target/conflict/locked/undeliverable/dormant/indeterminate rejects), coverage pass fails on a dropped cell; thin coverage not a decider re-impl; pure, no IO
  ./run.sh check-entwurf-v2-release    # deterministic gate (0.11 Stage 0 step 5c-1): PURE release-policy reducer (decideReleasePolicy + reduceRelease) — the spawn-observation policy and its four release events went with the transport in the visible-first cut, so the shipped machine is meta-mailbox=never release (no lock) + control-socket=release once on send-final; decideReleasePolicy still enforces the lock-nullness invariant; pure, no IO
  ./run.sh check-entwurf-v2-send       # deterministic gate (0.11 Stage 0 step 5c-2a): control-socket SEND hand (executeControlSocketSend) wiring transport IO onto the 5c-1 reducer — ack→sent, in-band reject→rejected (no fallback), dead→same-lock one-shot re-resolve (control retry / mailbox enqueue), indeterminate→failed+rethrow with NO fallback (no double-delivery); release exactly once, releaseLock throw never masks the send error; IO-via-dep
  ./run.sh check-entwurf-v2-send-fallback # deterministic gate (0.11 Stage 0 step 5c-2b): same-lock re-resolve RESOLVER (resolveDeadControlSendFallback) — fire-and-forget re-resolve: alive→control retry, dead→reject (nothing is ever launched), indeterminate→reject, unsupported+deliverable→mailbox plan, undeliverable/bad-target/conflict→reject; resolver never releases, mis-wire fails loud, inspect/probe throws propagate; no IO (fakes)
  ./run.sh check-entwurf-v2-runner     # deterministic gate (0.11 Stage 0 step 5d-1): execute-router (executeDispatch) routing an already-decided DispatchDecision to its 5c transport hand → one outcome-rich EntwurfV2RunResult. reject→rejected (no hand) / control/mailbox→matching hand with decision.lock verbatim / N3 rejectReason carried / N1 SendDeliveredReleaseFailedError→execution-failed{finalizedOutcome,releaseFailed,retrySafe:false}; fake hands, no IO
  ./run.sh check-entwurf-v2-mailbox    # deterministic gate (0.11 Stage 0 step 5c-4, LAST 5c transport slice): ENQUEUE-ONLY meta-mailbox SEND body (executeMetaMailboxSend) + production sendViaMailbox adapter — sender→formatMetaMailboxBody with plan.wantsReply threaded (divergence from legacy hard false), sender absent→raw plan.message, enqueue opts EXACTLY {gardenId,body,sessionsDir,mailboxDir}, enqueue throw PROPAGATES (no success:false fold — mailbox has no in-band refuse); adapter NEVER touches lock (release is the hand's job); source guard: no release/routing seam
  ./run.sh check-entwurf-resume-args   # deterministic gate: resume-argv SSOT (buildResumePiArgs) for the S1 VISIBLE resume. The headless shape was measured wrong for a window before the consumer was written (`-p` is pi's own non-interactive mode), so the one shipped posture is `--entwurf-control` FIRST + ext args exactly once + `--session <abs file>` + optional `--provider` + `--model <m>` — and the gate pins the ABSENCES as hard as the presences: no --mode, no -p, no positional prompt (a resume runs no turn), no --no-extensions, never --session-id (which MINTS a session instead of resuming one)
  ./run.sh check-mux-resume-call       # deterministic gate: S1 resume PLACEMENT composition (mux-resume-call.ts). No fake tmux. cwd rules are MEASURED tmux 3.6a behaviours, each a way a resume looks successful while being wrong: a nonexistent `-c` exits 0 and lands the child in $HOME (so it is refused HERE), `-c` is FORMAT-EXPANDED so `#{…}` silently rewrites the path and `#(…)` was observed running a command (so `#` is refused), and whitespace measured SAFE (so no escaping layer is owed). Also pins `-c` reaching tmux, runtime after `--`, carrier-free argv, zero identity in this module, and the surface seam that keeps the v2 composition from importing mux
  ./run.sh check-mux-parent-artifact  # deterministic gate for the tracked scrubbed parent-transcript fixture — a version-pinned sample of the PARENT-SIDE shape (fresh_call toolResult + the later callback custom_message) so downstream never opens a private transcript. Pins event order, the toolCallId join on the RESULT (pi writes no separate toolCall row), the launch nonce reappearing verbatim in the callback body, the <sender_info> envelope field names, and the absence of operator paths / real garden ids / real uuids. NOT placement evidence
  ./run.sh check-mux-launcher-fence   # deterministic gate for the shared operator-launcher fence (issue #67): scripts/lib/claude-launcher-fence.ts + its wiring into BOTH mux LIVE smokes. Replants the observed install-destruction shape (real HOME + fixture XDG_DATA_HOME → self-update retargets the real `claude` launcher into the fixture tree, teardown deletes it) wholly inside disposable mkdtemp roots — the real launcher is never inspected. Pins fail-closed preflight, retarget/content-change detection before cleanup, removal BLOCKED on fixture reference / unproven safety / surviving tracked panes, exact operator-parity XDG restore (absent = DELETED, not canonical defaults), the lifecycle cell-branch topology, and one shared helper consumed by both smokes
  ./run.sh check-entwurf-v2-visible-resume # deterministic gate: S1 visible-resume COMPOSITION (entwurf-v2-visible-resume.ts) with every seam injected — the whole state machine incl. the timeout branch runs with no tmux/lock/socket/clock. Pins lock BEFORE liveness, identity under the lock and before any window (no-transcript citizen fails loud, opens nothing), live/indeterminate/address-conflict refused unlaunched, observation as a BOUNDED WAIT (measured: socket answers ~2–4s after launch, so one immediate probe would call a successful resume unobserved), exactly ONE launch on every path, timeout → lock released + window left open + nothing retried/killed, failed release throws, and the two receipts staying separate in type and text
  ./run.sh check-resume-launch-identity # deterministic gate for resume-launch-identity.ts, the record-authoritative launch-identity leaf preserved through the visible-first cut (spawn-bg and all its callers are gone; this leaf answers "which being is this, and which conversation is theirs"). Temp meta-store fixture: gardenId→record.transcriptPath happy path with header cwd/provider/model; C3 integrity (header id ≠ record.nativeSessionId → refused, never resumed); #52 ADDRESSABLE read (a gid that no longer holds its nativeSessionId alone is refused from EITHER side — the plain targeted read would resume one transcript twice under two locks); cause fidelity per impossible resume incl. the F7 pin (recorded-but-deleted transcript → MISSING, not "no recorded model"); header↔gate SSOT. No spawn/socket/timer
  ./run.sh smoke-entwurf-v2-matrix-live # LIVE sentinel (0.11 Stage 0 step 5d-5, D4-b) — OUT of pnpm check, needs LIVE=1. Drives REAL production runEntwurfV2 deps over REAL OS objects, 4 cells: C1 control-socket (real pi --entwurf-control resident → RPC send → lock acquire→release ×1), C1b record-less socket (#50 C4: live record-less pi → EVERY intent rejected pre-probe record-less-socket, no lock, rendered hint names record authority + fresh-cut), C2 meta-mailbox deliverable (armed self-fetch citizen → real .msg enqueue, lock-free), C3 meta-mailbox guard (no armed receiver → reject, no garbage). Model-in-loop OUT (transport/lock/enqueue gate, GPT Q2); negative/timeout stay deterministic. Model: ENTWURF_LIVE_TARGET=<provider>/<model> (default openai-codex/gpt-5.6-luna). LIVE=1 ./run.sh smoke-entwurf-v2-matrix-live
  ./run.sh smoke-agy-native-push-live  # 봉인 8 LIVE acceptance for the native-push (agy) rail — OUT of pnpm check, needs LIVE=1 + AGY_CONVERSATION_ID (a live agy conversation). Drives the REAL antigravity adapter + register core + runEntwurfV2 (production deps): doctor-static preflight (dangling→FAIL, the ③ gate), probe route, register create/attach idempotency, fire→native-push delivered, post-send re-probe (D7 partial), bogus-conv→native-push-probe-indeterminate. Meta-store isolated to a temp dir (only the agy round-trip is real; no real-store residue). COST FENCE: open that agy conversation on gemini-3.6-flash (free account) — never a Pro tier; entwurf never selects the agy model and no assertion reads it. LIVE=1 AGY_CONVERSATION_ID=<convId> ./run.sh smoke-agy-native-push-live
  ./run.sh smoke-mux-lifecycle-live  # RELEASE MUST integrated LIVE lifecycle acceptance for mux, through the REAL MCP surface — OUT of pnpm check, needs LIVE=1 and spends model turns (two pi siblings: native + recorded-ACP provider, each resumed once; one Claude Code sibling). tools/call fresh_call -> nonce callback sender envelope -> v2 control send landing in the sibling's own transcript -> resume_call REFUSED while live (window count unchanged) -> stable-handle close (pane gone, socket dead, record kept) -> dormant delivery refused honestly -> public entwurf_resume_call with LAUNCH and OBSERVATION receipts kept apart, same-gid socket alive, zero new citizens, zero lock residue, resumed pane_start_path == RECORD cwd (separate tmux query), transcript byte-identical across the resume -> v2 recall of the pre-close fact. claude-code resume refused target-not-pi, no window opened and no lock residue. LIVE=1 ./run.sh smoke-mux-lifecycle-live
  ./run.sh check-entwurf-facts         # deterministic gate (0.11 Stage 0 step 4, fact-provider slice 1+2): PURE PeerFact core + resolveFactList union — R1 out-of-domain→unsupported, R3b socket-domain 4-value, facts-only keyset; union: PeerFact + RecordLessSocketFact by gardenId (#50 C4: record-less socket = diagnostic subject, gid+liveness only), dormant→dead, F3 indeterminate preserved, out-of-socket-domain+socket fail-loud; pure, no IO
  ./run.sh check-socket-discovery      # deterministic gate (0.11 Stage 0 step 4, fact-provider slice 3): SOCKET-axis scanSocketProbes — probes (dir sockets) ∪ (in-domain citizen canonical paths) 3-valued; dormant citizen no-file → dead (resumable, not unprobed), stall → indeterminate (F3), dir hygiene/dedup/missing-dir + e2e → resolveFactList; readdir/probe injected, no IO
  ./run.sh check-meta-facts            # deterministic gate for the meta-facts projection (#65): drives the REAL CLI — full-record join, parse-before-uniqueness, no-winner duplicates, drift/symlink/invalid-UTF-8 defects in-band, deterministic bytes, exit contract 0/2/3, dispatch+emit reachability
  ./run.sh check-meta-listing          # deterministic gate: META-STORE facts axis — kind-carrying entries; non-regular records are never read, parse/drift become diagnostics, duplicate nativeSessionId quarantines every rival but not unrelated citizens; strict throws / collect partial; pure injected IO
  ./run.sh check-entwurf-fact-provider # deterministic gate (0.11 Stage 0 step 4, fact-provider slice 4b): ASSEMBLY listEntwurfFacts — listAllMetaIdentities→scanSocketProbes→pre-quarantine out-of-socket-domain/socket conflicts→resolveFactList(clean)→{facts,diagnostics}; C-원칙: expected corruption (parse/collision)→diagnostics (listing survives), impossible invariant (dup/unprobed)→throw; collision quarantines BOTH PeerFact+socket; deps injected, no IO
  ./run.sh check-entwurf-peers-surface # deterministic gate (0.11 Stage 0 step 4, fact-provider slice 4c): MCP entwurf_peers RENDER renderEntwurfPeers (#50 C4) — payload keyset exactly {peers, diagnostics}; FORBIDDEN keys sessions/socketOnly/controlDir/socketPath/count + no .sock in text (socket is transport, never identity); record-less socket = aggregated record-less-socket diagnostic (F8, liveness-keyed message, alive names fresh-cut); NO verb-routing key (JSON deep scan) NOR word (text), diagnostics both surfaces, empty→(none), unsupported shown; WIRING guard: both surfaces call provider+render, getLiveSessions + /entwurf-sessions gone; facts fabricated, no IO
  ./run.sh check-entwurf-self-address # deterministic gate (SE-1/SE-2 slice 1): self-addressability honesty predicate computeSelfAddressability — pi replyable ⟺ live socket; meta splits by RAIL: self-fetch ⟺ recordBacked ∧ ownerAlive ∧ watchArmed (regression-proof record-present rows), native-push ⟺ recordBacked ∧ probeAlive (separate axis — no mailbox fact may rescue or sink it), unsupplied rail fail-closed; SOURCE GUARD buildStrictPiSenderEnvelope drops hardcoded replyable:true + existsSync-probes socket, entwurf_self renders alive vs expected AND renders the meta rail per-rail (mailbox only inside the self-fetch branch; native-push denies an inbox and gates injection on the probe)
  ./run.sh check-entwurf-deliverability # deterministic gate (SE-1/SE-2 slice 2c): conversational-mailbox deliverability predicate — computeMetaReceiverActive (recordBacked ∧ ownerAlive ∧ watchArmed) + mailboxConversationalDeliverable (self-fetch AND active); direct-inject pi refused (SE-1), self-fetch dead/unarmed refused (SE-2); self-address shares the same atom
  ./run.sh check-native-push-adapter # deterministic gate (봉인 3/8): native-push adapter leaf (antigravity) via a FAKE runner — FULL pid scan (not head -1), dead vs indeterminate, VOLATILE route re-discovery (no cache), send argv+ANTIGRAVITY_LS_ADDRESS env, non-zero exit throws, NO adapter-level retry (executor-owned), resolveNativePushAdapter fail-fast
  ./run.sh check-native-push-register # deterministic gate (봉인 5): registerNativeConversation (entwurf_register_native core) via fake adapter + isolated mkdtemp store — live probe→CREATE, re-register→ATTACH (same gid, cwd refreshed, no dup), not-live probe→REFUSE (throws, no record), receiver-marker abstinence (보정① source guard)
  ./run.sh check-agy-sender-identity # deterministic gate (#46 sender lane): WHO is calling the bridge — real agy hook as a child process writes an antigravity sender marker keyed by its PARENT pid (never on upsert failure), and resolveTrustedMetaSenderIdentity over isolated stores yields 0→null / 1→identity on EITHER backend / two distinct live identities on one owner pid→THROW (never guess, never downgrade to anonymous). This is what turns an agy send from external-mcp/unknown-host into a replyable garden citizen
  ./run.sh check-package-source-routing # deterministic gate (#29): package-source -> install-root mapping + fail-fast routing (local/git/npm/missing/project/no-source × local+remote, self-root, resume), no backend
  ./run.sh new-session-id             # print one fresh garden id from the generateSessionId SSOT (#50 C2: no launcher injection — the record layer is the consumer; pi mints its own session id)
  ./run.sh smoke-resident-garden-guard # live resident --entwurf-control garden guard (negative 0-token; SMOKE_RGG_POSITIVE=1 for positive)
  ./run.sh smoke-meta-async-drift     # 1.0.0 meta-bridge step 1: drift sentinel — version pins + Claude binary undocumented-behavior markers (LIVE=1 adds plugin watch-arm probe)
  ./run.sh smoke-meta-honesty         # 1.0.0 meta-bridge: honesty regression gate (#30 blockers) — doorbell counts ALL msgs honestly + hook logs failures as ERROR (best-effort, no scream). Offline/deterministic (deps: bash+node+python3)
  ./run.sh smoke-meta-install-state   # 1.0.0 meta-bridge Phase 2: stateful install/uninstall + store-doctor regression gate. Offline/deterministic (deps: bash+node+python3)
  ./run.sh check-meta-doctor-oracle   # 0.12.8 (#51): detection power of the release ORACLE — healthy fixture must reach `doctor: PASS`, then 21 planted defects (retired shell form, partial hand-patch, launcher bypass/repoint/provenance loss, malformed exec args, owner type drift, extra leaf/group, doorbell asyncRewake/path/timeout, no live bridge, stale receiver, ambiguous/missing cache, missing hook log/writer, failing CLI probes) must each turn it FAIL naming their own cause, plus a positive case pinning that a long-writing CLI is NOT a false negative. Offline/deterministic (deps: bash+node+python3)
  ./run.sh smoke-agy-install-state    # agy MCP + exact permission ownership regression: isolated HOME+XDG, adopt/state/inverse, symlink refuse, truthful setup outcomes. Offline/deterministic
  ./run.sh smoke-setup-verdict        # #86 C1+C3b aggregate setup verdict fixture: all-absent SKIP/green, pi presence+floor, detected-FAIL nonzero, copilot four-unit composition (present=independent PASS/FAIL rows, absent=zero-state SKIP), installed-mode named branch, credential store untouched. Offline/deterministic
  ./run.sh check-agy-permission-matrix # AGY permission CONTRACT SPACE as a literal table (55 cells): parser-state × operation × settings × ownership × precedence with stated exclusion rules; expectations are hand-written literals, never read from the SUT. Offline/deterministic (deps: python3)
  ./run.sh smoke-omp-fresh-live        # #87 bundle C acceptance, RELEASE MUST: omp opened as ONE visible fresh sibling through the PUBLIC entwurf_fresh_call surface (never raw tmux), exact nonce callback -> garden id from the SENDER ENVELOPE -> record/backend identity -> addressed receive -> lastReadAt -> the drain visible in that same native session's own transcript. Needs LIVE=1 and spends real model turns. Self-deciding: omp outside FRESH_CALL_BACKENDS or without a mailbox rail is a protocol SKIP, which --cut reads as RED
  ./run.sh smoke-omp-receive-live      # #87 bundle B acceptance: another harness wakes an ALREADY-OPEN omp citizen, which reads its inbox and answers in the same session. Decides its own outcome from the capability registry — omp without a drainable mailbox is a protocol SKIP (no receiver unit exists to arm), which an unattended release-gate reports and `--cut` reads as RED; a registry that claims a receive rail with no acceptance body here is a FAIL
  ./run.sh smoke-entwurf-chain-live    # LIVE cross-harness delivery chain: native Claude Code -> pi GPT -> pi ACP Sonnet -> mailbox terminus, proving sender identity/replyable at every hop and a real read receipt at the end. Prerequisites (claude on PATH, pi credentials per backend) report protocol SKIP, never a pass
  ./run.sh check-release-gate-outcomes  # release-gate STEP OUTCOME protocol (P1): one skip exit code shared by the shell + TS halves, classifier never rounds a skip up to a pass, `--cut` refuses a MUST SKIP while a bare diagnostic stays exit 0, no LIVE smoke keeps the old exit-0 skip shape, and both real skip surfaces are INVOKED and observed to propagate the code
  ./run.sh check-gate-manifests         # the HEAD of that qualification, on its own: runner self-test + the committed manifests validated against the origin index + the declared lane inventory. Executes ZERO mutants and never snapshots this repo (~8s), which is why it lives in check:hermetic while the body stays on CI/release-gate — three of the five reds qualification ever produced in CI died right here, before a mutant gate ran (#99 B-3)
  ./run.sh check-gate-qualification    # kill-proof qualification (the gate-of-gates): runner self-test (classifier truth table + synthetic negatives incl. wrong-reason/hang/control-red/impurity) + committed mutant manifests (scripts/mutants/*.json) run in an isolated snapshot repo under control→mutant→restore→control; the real checkout is never written. Evidence = claim IDs + killed mutant IDs, never assertion counts
  ./run.sh check-probe-ordering        # §11-7 ordering-probe deterministic gate: raw-client SAMENESS pinned to backend.ts (sequence/args/timeouts/permission policy — the probe may never measure a lookalike), phase attribution incl. set-model, probe-mode fixture wire markers (delay honored, probeRunId REQUIRED, smoke-acp-mcp-live legacy compat), event-log door integrity (reserved keys refused at write; unknown marker name, broken sort axis, or a payload the classifier cannot judge on is MALFORMED, never a quiet event), and the §11-7 paired-verdict truth table (P0/I0 outside the space, phase-qualified D, B promotion ladder, C, A two-delay rule). Offline/deterministic; one product claim (no production prompt cutoff) is replant-qualified via scripts/mutants/probe-ordering.json, while the other assertions are direct [CHECK:*] contracts
  ./run.sh check-probe-cli-shim        # §11-7-c B-name-snapshot PRODUCER gate: the CLI shim driven as a REAL process against fake CLIs (no API, no cost). Proves what a defect would buy — FABRICATED evidence (a malformed init is never reported as an empty name set; the boot report carries the true target path+sha256 the classifier verifies against the roster), a DESTROYED turn (byte transparency across mid-UTF8/CRLF/oversized/unterminated framing, exit-code fidelity, signal re-raise, inbound signal forwarding, stderr passthrough, stdout backpressure), and LEAKED operator state (exact-allowlist env scrub, no argv/env/prompt body in the log). Offline/deterministic; 20 direct [CHECK:*] contracts, deliberately no longer replant-qualified after #70 subtraction
  ./run.sh smoke-agy-statusline-state # agy ambient garden-id statusLine install/doctor/inverse regression. Offline/deterministic
  ./run.sh smoke-copilot-statusline-state # Copilot custom-footer install/doctor/inverse regression. Offline/deterministic
  ./run.sh smoke-copilot-mcp-state       # Copilot MCP install/doctor/inverse regression. Offline/deterministic
  ./run.sh smoke-omp-bridge-state        # OMP birth-extension install/doctor/inverse regression: placement, stale-writer detection, honest inverse, no-state refusal (structurally VALID as well as foreign), symlink refusal, ambiguous-agent-dir refusal (ledger M6), and a poisoned PI_CODING_AGENT_DIR that attracts no artifact. Fully sandboxed HOME/PI/XDG. Offline/deterministic
  ./run.sh smoke-agy-hooks-state      # agy PreInvocation birth/sender hook install/doctor/inverse + direct stdin→meta-record regression. Offline/deterministic
  ./run.sh smoke-user-scope-citizen   # 0.12.6 install-boundary: pi packages[] registration SSOT (register-pi-package.py) — idempotent + preserves unrelated + remove symmetry + fails loud, and the #86 C2 explicit ownership cells (project scope still normalizes ITS OWN stale entries; user scope refuses other owners and only takeover-user-scope moves the shared entry). Offline/hermetic (deps: bash+python3)
  ./run.sh smoke-meta-prune           # 1.0.0 meta-bridge Phase 4: listing-only store janitor regression gate — classify keep/orphan/stale/ambiguous, delete nothing. Offline/deterministic (deps: bash+node)
  ./run.sh smoke-meta-keyset-guard    # 0.10.0 meta-bridge: keyset-owner guard regression — check-keyset-overlap + managed-keys SSOT (disjoint passes, collisions fail). Offline/hermetic (deps: bash+python3)
  ./run.sh check-meta-manifest-schema # 0.12.2 meta-bridge: CLI-version-INDEPENDENT static guard — plugin manifests pinned to the minimal keyset that validates on the lowest supported Claude (closed-schema regression that broke 0.12.1 install on floor) + desired_mcp installed-vs-clone dual-mode. Offline (deps: python3)
  ./run.sh smoke-claude-native-resume-live # LIVE-only: Claude Code native fresh→--resume continuity + meta-record uniqueness; proves meta-bridge records identity without touching the backend resume path

  ./run.sh install-meta-bridge        # INTERNAL part of `setup` (native-harness plugin) + doctor recovery path — prefer `setup`; stateful GLOBAL install (plugin + USER MCP + settings keyset, honest uninstall state)
  ./run.sh uninstall-meta-bridge      # 1.0.0 meta-bridge Phase 2: stateful GLOBAL uninstall (restore only keys/items captured in install-state)
  ./run.sh doctor-meta-bridge         # THE RELEASE ORACLE (#51, Linux-certified repair axis). exit 0 = every required layer was MEASURED on this Linux host: toolchain + state + plugin/MCP + resolved-artifact launch-form classification (all 3 owner hooks + doorbell static contract) + synthetic owner join + store scan + hook errors + SessionStart evidence + REQUIRED live MCP↔marker join + writer-version parity. Missing live evidence is NOT CERTIFIED (open a Claude session and re-run), never a pass; Darwin is not yet verified/certified and stays nonzero for this cut (future validation may reopen it). Detection power is held by check-meta-doctor-oracle
  ./run.sh copilot [args...]          # #82 RAIL 7: the MANAGED Copilot launch. exec()s the vendor CLI in THIS terminal (cwd/pid/exit preserved) with COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS set for that one invocation — entwurf owns no part of your shell and writes nothing to it, but it owns the process it is about to become. Without that flag Copilot skips the extension scan SILENTLY. Refuses to launch unless the receiver unit is actually installed. Injects `--model auto` when no --model was given and `--yolo` when no explicit permission/surface policy flag was given, both BEFORE any `--`; every argument you pass is forwarded byte-identical. RUNNING THIS IS YOUR CONSENT to that profile — use plain `copilot` for stock vendor behaviour. Not tmux, not fresh-call, mints no citizen (birth is still the first prompt)
  ./run.sh install-copilot-bridge     # #82: GLOBAL install of the Copilot BIRTH plugin (own marketplace root; node+entry baked into the no-argv exec string). MCP wiring and the RECEIVER extension are separate install surfaces (install-copilot-mcp, install-copilot-receive). Also retires the stale Claude unit (--keep-stale-claude-unit opts out)
  ./run.sh uninstall-copilot-bridge   # #86 C3a: honest inverse of install-copilot-bridge from the package-owned install-state (exact qualified id + exact marketplace name/path + recorded assembly only; state deleted LAST; a failing vendor list is UNKNOWN and refuses; never --force, never the stale Claude unit)
  ./run.sh doctor-copilot-bridge      # #82/#86: fail-loud surface for that unit — runtime axis (red = a hook that RAN and failed, or a broken/unbaked artifact; "installed with zero records" is NOT red and is reported as NOT-YET: a Copilot session is born on its FIRST PROMPT, not when the window opens, measured) + ownership axis (install-state shape/binding, marketplace path drift, UNKNOWN vendor lists; legacy no-state install = named non-green, repair = install-copilot-bridge adoption). Either axis red = red
  ./run.sh install-copilot-statusline # own Copilot statusLine + footer.showCustom with an install-state preimage
  ./run.sh uninstall-copilot-statusline # honest inverse of install-copilot-statusline
  ./run.sh doctor-copilot-statusline  # static ownership/config/bin doctor; never claims a render receipt
  ./run.sh install-copilot-mcp        # #82 RAIL 5: register ONE entwurf-bridge server in ~/.copilot/mcp-config.json (adopt / create / REFUSE symlink), type:local, install-state under $XDG_DATA_HOME/entwurf/copilot-mcp/
  ./run.sh uninstall-copilot-mcp      # honest inverse of install-copilot-mcp from install-state
  ./run.sh doctor-copilot-mcp         # static ownership/config/boot doctor; RED only when install-state exists
  ./run.sh install-omp-config         # #87 follow-on: write the ONE operator setting omp's tool hand requires — `tools.xdev: false` in <omp agent dir>/config.yml. Owns exactly the line(s) it adds (recorded in install-state), refuses a symlinked config, refuses a config it cannot parse, and refuses an EXPLICIT operator `xdev: true` by name rather than overwriting a decision. Without it the vendor default wraps every MCP tool behind `xd://` and the doorbell announces a tool the model cannot call
  ./run.sh uninstall-omp-config       # honest inverse from install-state: takes back exactly the recorded line(s), removes the file only when entwurf created it, REFUSES when the config changed since install
  ./run.sh install-omp-bridge         # #87: install the OMP BIRTH extension into <omp agent dir>/extensions/entwurf-meta-omp (index.ts|js + lib + capability registry). No launcher and no bake — an omp hook is an in-process extension. Refuses when an inherited PI_CODING_AGENT_DIR/PI_CONFIG_DIR/PI_PROFILE makes the target agent dir ambiguous (ledger M6), and refuses ANY pre-existing artifact at the unit path that entwurf holds no ownership state for — a shape is not a proof of ownership
  ./run.sh uninstall-omp-bridge       # honest inverse from install-state (exact unit dir + recorded entry; no-state host REFUSES; state deleted LAST). Records already minted are preserved
  ./run.sh doctor-omp-bridge          # #87: runtime axis (importable unit, writer/registry parity, mint vs sender-marker errors on SEPARATE axes, scope-fence receipts, a root-grammar preflight that goes RED on a relative ENTWURF_META_* override instead of reporting on some other directory, CERTIFIED omp record count via meta-facts under the omp root policy — never a text grep, live omp processes carrying inherited PI_SESSION_ID/PI_AGENT_ID) + ownership axis. PI_CODING_AGENT_DIR is the vendor's own agent dir here and is reported as ignored, never as contamination. Zero records = NOT-YET, never red
  ./run.sh install-omp-receive        # #87 bundle B: install the OMP RECEIVER extension into <omp agent dir>/extensions/entwurf-receive-omp. Own unit, own install-state, own doctor, own inverse. It joins the citizen BIRTH minted in the same process (sender marker for this pid + V3 record + the vendor's current session id, all three or refuse), holds an fs.watch on that citizen's mailbox signal, and rings an ANNOUNCE-ONLY doorbell via pi.sendUserMessage. It never assumes it loads after birth: extension handlers run in directory-name order and a before-sorting unit was MEASURED to see no marker, so the arm retries on a bounded ctx.setInterval cancelled with ctx.clearTimer (the vendor exposes no clearInterval)
  ./run.sh uninstall-omp-receive      # honest inverse from install-state; records and sender identity untouched. A session that ALREADY armed keeps its marker until its process exits
  ./run.sh doctor-omp-receive         # runtime axis (importable unit, writer parity, arm failures and doorbell failures on SEPARATE axes, who is armed RIGHT NOW through the production marker reader) + ownership axis. Zero armed receivers = NOT-YET, never red. Reports a marker for exactly what a marker proves — a live owner reached the arm emit — and never upgrades that into "a wake will happen"
  ./run.sh omp-receive-facts          # read-only JSON projection of the omp receive rail: every receiver marker through readMetaReceiverMarker in BOTH readings (live / as-written) plus mailbox counts. The shared oracle so no consumer answers "is a doorbell held?" from a filename
  ./run.sh install-omp-mcp            # #87 step 5: write ONE omp-native entwurf-bridge server into <omp agent dir>/mcp.json with env ENTWURF_BRIDGE_EXTERNAL_AGENT_ID=external-mcp/omp. The server key is a PINNED LITERAL, byte-identical to the Claude import's — same-key first-wins at native=100 > claude=80 is what SHADOWS the import (never disabledServers, which kills both). Adopt / create / REFUSE symlink, preimage recorded
  ./run.sh uninstall-omp-mcp          # honest inverse from install-state (restores the preimage, or removes a file we created); the Claude import becomes effective again
  ./run.sh doctor-omp-mcp             # ownership + config + boot doctor, plus the EFFECTIVE-source read (native-wins / native-invalid / import-wins / both-suppressed) — a configuration read, never a runtime receipt. Runtime validity and ownership are SEPARATE axes: foreign provenance, a disabledServers denylist, and a malformed entry under our key are each RED even with no install-state. tools.xdev is a RUNTIME cell: absent file/key applies the vendor default (true, no inline allowlist) and is RED while the native hand is the effective source; xdev false is ok; a covering xdevInlineDevices glob is ok-with-note
  ./run.sh smoke-omp-mcp-state        # OMP MCP install/doctor/inverse regression incl. shadowing, the denylist refusal, target confinement + retarget refusal, and a malformed entry going RED with zero install-state. Fully sandboxed HOME/PI/XDG. Offline/deterministic
  ./run.sh install-copilot-receive    # #82 RAIL 5: install the RECEIVER extension (user scope ~/.copilot/extensions/entwurf-receive). Owns the artifact and CHECKS the launch flag; it never sets one (a launch does — see `./run.sh copilot`). Arms per session after birth
  ./run.sh uninstall-copilot-receive  # honest inverse from install-state; never removes a unit it did not install
  ./run.sh doctor-copilot-receive     # artifact + digest, COPILOT_CLI_ENABLED_FEATURE_FLAGS on the LIVE copilot processes (the silent failure), live receiver markers via the production reader, receiver log. RED only when install-state exists
  ./run.sh install-agy-bridge         # 봉인 7: agy MCP install adapter — register ONE entwurf-bridge server in the agy mcp_config (adopt file / create / REFUSE symlink), stable bin command, install-state under $XDG_DATA_HOME/entwurf/agy-bridge/
  ./run.sh uninstall-agy-bridge       # 봉인 7: honest inverse of install-agy-bridge from install-state (restore preimage / remove key; refuse if config became a symlink)
  ./run.sh probe-bridge-command <cmd> [args...]  # #81: BOOT the given bridge invocation and require the entwurf MCP tool surface back. `--invocation-json '{"command":"…","args":[],"env":{}}'` preserves a harness config exactly. It waits for a valid initialize response, then sends initialized + tools/list only (no tools/call, lock, record, or delivery). exit 0 = it serves the bridge; 1 = it does not. The pi/agy doctors use this leaf.
  ./run.sh doctor-agy-bridge          # fail-loud doctor: MCP config + exact permission rule + state + live probe label
  ./run.sh install-agy-statusline     # own the agy statusLine subtree with bare entwurf-agy-statusline; preserve unrelated settings
  ./run.sh uninstall-agy-statusline   # honest inverse from statusline install-state
  ./run.sh doctor-agy-statusline      # fail-loud statusLine config/bin/state doctor + honest live SKIP
  ./run.sh install-agy-hooks          # #46 agy birth imprint hook — named PreInvocation hook running bare entwurf-agy-imprint, preserving other hooks
  ./run.sh uninstall-agy-hooks        # honest inverse of install-agy-hooks from install-state
  ./run.sh doctor-agy-hooks           # fail-loud doctor for agy hooks.json imprint wiring
  ./run.sh meta-bridge-prune          # 1.0.0 meta-bridge Phase 4: LISTING-ONLY store hygiene — classify orphan/stale/ambiguous/keep, print manual rm commands, delete NOTHING ([dir] [--ttl-days N])
  ./run.sh meta-bridge-fresh-cut      # the ONE generation verb (the verb every v3-only rejection names): quiesce-check live sockets/markers/native-push conversations (refusing any surface it cannot inspect), archive meta-sessions/ + meta-mailbox/ to `<dir>.archive-<ts>`, clear dead transport residue, open an empty v3 generation. No migration, no restore — the archive is forensic only. EXIT CONTRACT (#54, `--help` prints it): 0 complete / 1 NOTHING MOVED (re-run, do not setup) / 2 usage / 3 cut transition incomplete (inspect) / 4 cut complete but residue cleanup failed (`setup` may run; re-run only before new citizen birth, otherwise remove residue manually)
  ./run.sh meta-facts                 # #65 owner-normalized READ-ONLY store projection: deterministic JSON {schemaVersion:1, storeDir, citizens: full v3 records sorted by gardenId, defects: {filename,message}} — THE listing contract emitted by the owner so consumers stop copying the certification. No liveness/sockets/transcript contents. EXIT: 0 readable (defects in-band; missing store = empty), 2 usage, 3 unreadable ([dir])
  ./run.sh meta-bridge-managed-keys   # 0.10.0 meta-bridge: print the SSOT of settings keys entwurf OWNS (consumers read this to stay disjoint — keyset-owner invariant)
  ./run.sh check-keyset-overlap <fragment.json...>  # 0.10.0 meta-bridge: PREVENTIVE keyset guard — fail if a consumer fragment collides with any pi-owned key (cross-repo; not in pnpm check)
  ./run.sh check-dep-versions         # local deterministic check that the pi pin agrees across package.json (devDeps + peer range), run.sh (peer-install pins), and the baseline docs (AGENTS/README/ROADMAP/setup-clean-host/demo)
  ./run.sh check-node-floor-coherence # binds the Node floor (24+, single axis) across engines.node, run.sh setup preflight, meta-bridge install/doctor judgment logic, clean-host docs, the bridge launcher header, and the CI runner node-version — engines.node is the SSOT, everything else is derived; sweeps tracked contract text for an unregistered declaration
  ./run.sh check-pack                 # publish gate (dry-run): npm pack --dry-run + tarball invariants (runtime-critical present, dev residue absent)
  ./run.sh check-pack-pin-matcher     # pure self-test of check-pack-install's pin-leak matcher against synthetic .pnpm lookalikes (version boundary: @0.84.40 must leak, @0.84.4 bare/peer-hash must pass); snapshot-safe qualification oracle, also run first inside check-pack-install
  ./run.sh check-fresh-cut-gate       # SOURCE cell of the generation-boundary proof (IN pnpm run check:full): drives real install/setup/fresh-cut in a sandbox; certification refusal is pre-write, quiescence is fail-closed, archives preserve bytes, and the #54 exit matrix distinguishes complete / no-move / usage / incomplete transition / complete-with-cleanup-residue. No model/network/cost
  ./run.sh check-pack-install         # heavy publish gate (prepublishOnly): actual npm pack + tar -tf + fresh-temp install smoke with the pinned pi peers (pins derived from the package.json devDep; check-dep-versions binds them) + the npm-installed bridge BOOTS (tools/list) and DELIVERS (tools/call entwurf_v2 → .msg lands) + the installed all-absent and copilot-present (four-unit fake-vendor) `entwurf setup` rows + the INSTALLED generation lifecycle on a seeded previous-generation host (REFUSE before activation writes / zero Claude invocations → installed fresh-cut archives + opens empty → install-meta-bridge PASSES) + the INSTALLED-PACKAGE branch of the Copilot and OMP birth installers actually RUN (compiled entry selected, no raw .ts, and a real birth edge mints a citizen — the half a required-artifact list can never stand in for)
  ./run.sh check-install-container    # 0.12.8 (#51 C): Linux artifact-CONSUMER gate — one candidate .tgz handed read-only to a checkout-invisible node:<engines-major>-bookworm cell. Default packs once to temp; ENTWURF_CANDIDATE_TGZ=/absolute/preserved.tgz consumes those exact bytes with no re-pack and prints canonical path+sha256 for release. Non-root global PATH install, frozen package, MCP tools/list, fake-Claude install-meta-bridge, path+sha256 fence, strict doctor, and the GENERATION host-state matrix (clean / v3-only store bytes unchanged / previous-generation REFUSE→fresh-cut→retry PASS) seeded inline. Docker missing = honest SKIP; ENTWURF_REQUIRE_DOCKER=1 makes that RED (required CI)
  ./run.sh install [project-dir]      # INTERNAL part of `setup` (project .pi/settings.json wiring) + npm-consumer entry — prefer `setup`, don't call directly for dev
  ./run.sh remove [project-dir]       # remove entwurf entries from project .pi/settings.json (project scope only; global user-scope citizen left intact)
  ./run.sh remove-user-scope          # explicit GLOBAL inverse of install's user-scope citizen: drop entwurf from ~/.pi/agent/settings.json packages[] (affects ALL cwds — shared entry, not per-project). #86 C2: same-owner-only — a LIVE foreign owner refuses; a MISSING owner is removed only when package entry + package state + provider installerRoot all align (reported orphan cleanup)
  ./run.sh takeover-user-scope        # #86 C2: operator-EXPLICIT ownership move of the shared user-scope registration to THIS root (old→new reported, packages[] entry + provider installerRoot together). The only writer over another owner — normal install/setup/remove refuse instead. No --force exists
  ./run.sh doctor-pi-package          # #86 C2: package-side user-scope ownership verdict — unregistered / owned / owned-by-other(live) / legacy-no-state / mismatch / missing-owner (nonzero on defect verdicts). Provider runtime verdicts stay with doctor-pi-provider

Notes:
  - project-dir defaults to current directory
  - Claude Code login should already exist (e.g. ~/.claude.json)
  - setup's runtime verification is the v2 install smoke (entwurf-bridge); the v2 dispatch substrate is proven live by release-gate
  - API key is optional; this bridge is intended to work with Claude Code auth
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

log()  { echo "  $*"; }
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠ $*"; }
fail() { echo "  ❌ $*"; }
section() { echo ""; echo "=== $* ==="; }

normalize_project_dir() {
  python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

# The old `sync_auth` credential mutation is GONE (#86 A5): setup composes what
# the operator already installed and NEVER reads, copies, aliases or backs up a
# harness credential store — the `entwurf` alias it wrote had no in-repo reader
# (the ACP provider passes pi's auth check with the no-auth sentinel), and the
# `auth.json.bak` it left is documented manual-operator-cleanup ONLY. Do not
# reintroduce credential copying as a convenience helper in any install path.

# Repo dependency integrity is a HARD requirement for install — NOT gated on
# backend (Claude/ACP) auth. A cloned-but-not-installed or a moved/renamed repo
# has missing or path-stale node_modules; `install` would otherwise happily wire
# settings.json and the failure only surfaces minutes later as a dead MCP bridge
# / pi-extension resolve error (the 2026-06-23 relocation failure: entwurf-bridge
# ✘ Failed to connect + check-entwurf-v2-surface ERR_MODULE_NOT_FOUND). Catch it
# HERE, before any settings file is written (no silent-red), with a package
# manifest access that follows the pnpm symlink to each dep — NOT a real module
# import (per-package "exports" maps forbid that uniformly) and NOT a bare
# `test -d node_modules`, which a dir-move breaks at the symlink-store level
# while the top-level dir still looks present.
# The store gate, in one place (fresh-cut generation policy). Every activation
# surface this repo owns wires up V3-ONLY readers (parse, birth, peers, self,
# v2, inbox, store-doctor). On a host whose meta-record store holds records the
# live schema cannot read — a previous generation, foreign bytes, corruption —
# activating them produces a host that installs clean, validates clean, and then
# rejects at RUNTIME. The active store carries NO cross-generation continuity
# (sessions flow; memory lives in the native transcript + andenken embedding
# axes, never in the bridge), so there is exactly ONE prescription and no
# diagnosis matrix: quiesce → `meta-bridge-fresh-cut` (archive the whole
# generation, open an empty one) → re-run.
#
# READ-ONLY by construction: it asks the store-doctor (fail-loud full scan) and
# reports. It never cuts — archiving a generation is the operator's conscious
# act, never an install side effect.
#
# The verdict is delegated rather than re-derived: store resolution (env +
# default) and the per-record causes live in the store-doctor, and a second
# implementation here would be a second truth that drifts. An absent store and
# a clean v3 store both exit 0, so a clean host needs no special case.
#
# WHAT THIS DOES NOT CLAIM: it is a preflight, not a lock. A session that writes
# a record between this check and the writes that follow is not prevented — the
# contract this proves is the ordering on a QUIESCED host. The rollout procedure
# for a host whose settings point straight at a checkout (quiesce sessions →
# pull → fresh-cut → setup) is the operational half, and it lives in the README.
preflight_v3_store() {
  local surface="$1" verdict
  # A tree carrying run.sh but not the doctor is a broken checkout/package, not a
  # host with a bad store. Say so, rather than letting node's MODULE_NOT_FOUND
  # stack stand in for a verdict this gate never reached.
  #
  # Guard the entry `run_ts` will ACTUALLY run — dev clone .ts, installed package
  # the dist .js twin — the way meta-bridge-install.sh already guards its own
  # DOCTOR_ENTRY. Checking the source .ts in both modes was a guard over the wrong
  # file: an installed package ships scripts/ (so the .ts is present) while a
  # broken prepack can leave the compiled twin missing, and there `run_ts` returns
  # its OWN 1 — indistinguishable from the doctor's exit 1 "certification defects",
  # so the rc branch below prescribed the destructive cut from an artifact failure
  # (2026-07-25 closure round; install.sh was already immune).
  local doctor_entry
  case "$REPO_DIR" in
    */node_modules/*) doctor_entry="$REPO_DIR/mcp/entwurf-bridge/dist/scripts/meta-bridge-store-doctor.js" ;;
    *) doctor_entry="$REPO_DIR/scripts/meta-bridge-store-doctor.ts" ;;
  esac
  if [ ! -f "$doctor_entry" ]; then
    fail "[$surface] cannot certify the meta-record store: the store-doctor entry this mode runs is missing ($doctor_entry)."
    echo "       This is a doctor/ARTIFACT failure, not a store verdict — no cut can help and none is prescribed." >&2
    echo "       Reinstall @junghanacs/entwurf (the package ships the compiled twin via prepack build-bridge), or run 'pnpm run build-bridge' in a dev clone, then re-run this step." >&2
    exit 1
  fi
  # The doctor's EXIT CODE is the verdict (see its header): 1 = certification defects,
  # 3 = the store could not be READ. Those take OPPOSITE prescriptions, and this function
  # prints the last line the operator (or an agent) acts on — so it must branch on the
  # code rather than end every refusal with "archive the generation".
  local rc=0
  verdict="$(run_ts scripts/meta-bridge-store-doctor.ts 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "[$surface] meta-record store certifies clean v3 ($(printf '%s\n' "$verdict" | tail -1))"
    return 0
  fi
  if [ "$rc" -eq 3 ]; then
    printf '%s\n' "$verdict" | head -8 >&2
    fail "[$surface] refused BEFORE any write: this host's meta-record store could not be READ (details above)."
    echo "       Nothing was written. This is an ACCESS problem, not a generation problem — a fresh-cut CANNOT fix it and is not what to run here." >&2
    echo "       Repair the store path's ownership/permissions, or point ENTWURF_META_SESSIONS_DIR at the intended store, then re-run this step." >&2
    exit 1
  fi
  # Only exit 1 IS a defect list (the doctor's EXIT CONTRACT). Anything else —
  # 2 (usage), a node crash (9/134/139), a killed process — means the DOCTOR never
  # delivered a store verdict, and prescribing a destructive cut from a crash
  # would send the operator at an archive command over a store nobody examined.
  if [ "$rc" -ne 1 ]; then
    printf '%s\n' "$verdict" | head -8 >&2
    fail "[$surface] cannot certify the meta-record store: the store-doctor itself FAILED (exit $rc — neither a defect list nor an access verdict)."
    echo "       This is a doctor/runtime failure, not a store verdict. Nothing was written. Diagnose the output above (broken checkout/package, bad node runtime), then re-run this step." >&2
    exit 1
  fi
  # Aggregate, never a wall: a large previous-generation store fails every
  # record with the same cause, so show the first few + a count (F8 lesson).
  printf '%s\n' "$verdict" | head -8 >&2
  local nfail
  nfail="$(printf '%s\n' "$verdict" | grep -c '^FAIL' || true)"
  if [ -n "$nfail" ] && [ "$nfail" -gt 8 ] 2>/dev/null; then
    echo "       … and $((nfail - 8)) more record(s) with causes (full scan: the store-doctor)" >&2
  fi
  fail "[$surface] refused BEFORE any write: this host's meta-record store holds entry/entries the live generation cannot certify (details above)."
  echo "       Every surface this step activates is V3-only, and the store carries no cross-generation continuity — sessions flow; memory lives in the transcript and embedding axes." >&2
  echo "       Nothing was written. Quiesce this host's sessions, archive the generation with \`./run.sh meta-bridge-fresh-cut\` (from an installed package: \`entwurf meta-bridge-fresh-cut\`), then re-run this step." >&2
  exit 1
}

preflight_dep_integrity() {
  command -v node >/dev/null 2>&1 || { fail "node not on PATH — cannot verify repo dependency integrity"; exit 1; }
  # Each wired pi-extension / MCP bridge / ACP backend root-imports its bundled
  # runtime deps at load/spawn time. Assert they actually resolve from the
  # package's location BEFORE writing settings, so a broken install fails loud
  # here instead of surfacing later as a dead MCP bridge (entwurf-bridge ✘) or an
  # ERR_MODULE_NOT_FOUND at runtime.
  #
  # Resolution must follow Node's OWN algorithm, because the package lives in two
  # layouts: a pnpm clone (deps in $REPO_DIR/node_modules) OR a pi-managed
  # `pi install npm:@junghanacs/entwurf` (deps HOISTED to an ancestor node_modules,
  # e.g. ~/.pi/agent/npm/node_modules, with NO package-local node_modules). A
  # cwd-relative `node_modules/<dep>` probe only sees the clone layout and wrongly
  # rejects every pi-managed npm install. So walk Node's real module-resolution
  # paths (Module._nodeModulePaths) and accessSync each candidate package.json:
  # exports-immune (no bare-root / ./package.json import) and hoist-aware, while
  # still catching a pnpm dir-move that left the symlink store dangling
  # (accessSync follows the link).
  #
  # Probe set = the BUNDLED runtime `dependencies` only. The `@earendil-works/pi-*`
  # peer trio is intentionally EXCLUDED, and the reason depends on the lane — the old
  # blanket claim ("the pi loader provides that runtime itself") was true for only one
  # of them and is corrected here:
  #   pi-managed install — pi omits peers (--legacy-peer-deps) and its own loader
  #     supplies the runtime, so the trio is legitimately absent.
  #   neutral npm/pnpm install — nothing supplies it. The optional peer is simply
  #     unresolved (entwurf-preflight.ts:51), and the project-trust lane that needs it
  #     is dead on that host. Excluding the trio from this probe is still right (a hard
  #     require would reject every consumer install), but it is a KNOWN GAP, not proof
  #     that the runtime is present by another route.
  # pi runtime presence/version is covered by check-pi-runtime-version /
  # check-pi-import-surface, neither of which runs on a consumer host.
  local probe=(
    "@modelcontextprotocol/sdk" "@agentclientprotocol/sdk" "@agentclientprotocol/claude-agent-acp"
    "@anthropic-ai/sdk" "zod"
  )
  local missing=() dep
  for dep in "${probe[@]}"; do
    if ! (cd "$REPO_DIR" && node -e '
      const M = require("module"), fs = require("fs"), path = require("path");
      const dep = process.argv[1];
      for (const nm of M._nodeModulePaths(process.cwd())) {
        try { fs.accessSync(path.join(nm, dep, "package.json")); process.exit(0); } catch {}
      }
      process.exit(1);
    ' "$dep") >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    fail "repo dependency integrity check failed — cannot resolve: ${missing[*]}"
    echo "       node_modules is missing or path-stale (common right after a clone," >&2
    echo "       or a repo move/rename — pnpm's symlink store points at the old path)." >&2
    echo "       Fix: (cd \"$REPO_DIR\" && pnpm install)" >&2
    echo "       Then re-run ./run.sh install . — settings.json was NOT written." >&2
    exit 1
  fi
}

preflight_pi_settings_shapes() {
  local project_settings="$1"
  local user_settings="$2"
  python3 - "$project_settings" "$user_settings" <<'PY'
import json, sys
from pathlib import Path

project = Path(sys.argv[1])
user = Path(sys.argv[2])

def load_object(path: Path, label: str):
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise SystemExit(f"{label} settings is not a JSON object: {path}")
    return data

def check_packages(data, path: Path, label: str):
    if data is None:
        return
    packages = data.get("packages")
    if packages is not None and not isinstance(packages, list):
        raise SystemExit(f"{label} settings packages is not a JSON array: {path}")

def check_project_provider(data, path: Path):
    if data is None:
        return
    provider = data.get("entwurfProvider")
    if provider is None:
        return
    if not isinstance(provider, dict):
        raise SystemExit(f"project settings entwurfProvider is not an object: {path}")
    servers = provider.get("mcpServers")
    if servers is not None and not isinstance(servers, dict):
        raise SystemExit(f"project settings entwurfProvider.mcpServers is not an object: {path}")

project_data = load_object(project, "project")
user_data = load_object(user, "user")
check_packages(project_data, project, "project")
check_packages(user_data, user, "user")
check_project_provider(project_data, project)
PY
}

install_local_package() {
  # Named interpreter prerequisite BEFORE any preflight/write (#86 E5): the
  # packages[]/provider writers below are python3-backed and `entwurf install`
  # dispatches here directly, so a python3-less host gets this verdict instead
  # of an accidental mid-write failure.
  command -v python3 >/dev/null 2>&1 || {
    echo "[install] entwurf install requires python3 on PATH (settings writers are python3-backed); nothing was written." >&2
    exit 1
  }
  local project_dir agent_dir
  project_dir=$(normalize_project_dir "$1")
  agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  preflight_dep_integrity
  # Pre-cut store gate — repeated here on purpose. `setup` already gated, but
  # `run.sh install` reaches this function directly, and this is the step that
  # registers entwurf in project + USER scope packages[] (= the V3-only
  # extensions load from any cwd). A gate only at the setup entrypoint would be
  # bypassed by the documented direct call.
  #
  # It sits AFTER dependency integrity because both are read-only and a broken
  # checkout has to fail as a broken checkout: this gate runs a script out of
  # scripts/, so on a tree that has run.sh and nothing else it would otherwise
  # preempt the dep verdict with a less true one. Still ahead of every write.
  preflight_v3_store install
  # Fail BEFORE any settings write if either target config already has a corrupt
  # shape. The packages[] SSOT and provider writer run in two separate steps, so
  # without this preflight a bad entwurfProvider could leave a half-installed
  # packages[] entry behind (2026-07-03 install-boundary hardening).
  preflight_pi_settings_shapes "$project_dir/.pi/settings.json" "$agent_dir/settings.json"
  mkdir -p "$project_dir/.pi"
  # packages[] registration via the shared SSOT — same is_entwurf_source
  # predicate + idempotency as user-scope and remove (not a substring match).
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$project_dir/.pi/settings.json" "$REPO_DIR"
  # entwurfProvider.mcpServers.entwurf-bridge (project scope — checkout-local, NO state; #46
  # Task 2) via the shared register-pi-provider SSOT: normalize the command to the bare stable
  # bin `entwurf-bridge` (ownership-classified: absent/managed-current/managed-legacy adopt, a
  # true user-override is left untouched) + prune legacy bundles. project remove is the inverse.
  python3 "$REPO_DIR/scripts/register-pi-provider.py" install "$project_dir/.pi/settings.json" "$REPO_DIR" --scope project
  register_user_scope_citizen
}

# Register entwurf as a pi USER-SCOPE citizen so its extensions
# (entwurf-control.ts → --entwurf-control / --emacs-agent-socket) load from ANY
# cwd, not only inside the entwurf checkout. project-scope `.pi/settings.json`
# only applies when pi runs inside the repo; the `pit`/`pia`/`pihome` global
# launchers and the npm consumer's "installs → just works" both need the entry
# in ~/.pi/agent/settings.json's packages[]. This is the wiring that dropped when
# `pi install` was removed from setup (2026-07-03: `--entwurf-control` unknown in
# a foreign cwd). Idempotent for THIS root: absent → append + owner state, present
# same-root → no-op. #86 C2 retires the silent normalization of other roots'
# entries: a different owner (live or missing) is a zero-write refusal that names
# takeover-user-scope. Every other package and key is preserved untouched.
_pi_package_state() { echo "${XDG_DATA_HOME:-$HOME/.local/share}/entwurf/pi-package/install-state.json"; }
_pi_provider_state() { echo "${XDG_DATA_HOME:-$HOME/.local/share}/entwurf/pi-provider/install-state.json"; }

register_user_scope_citizen() {
  local agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  # Shared idempotent implementation (also driven by smoke-user-scope-citizen).
  # #86 C2: user scope carries a recorded OWNER (packageRoot in the pi-package
  # install-state). Another owner — live or missing — makes this a zero-write
  # ownership refusal (exit 6) that propagates: install fails, setup records the
  # pi component FAIL. The only writer over another owner is takeover-user-scope.
  #
  # ATOMIC (#86 C2 amendment): BOTH ownership halves are decided READ-ONLY before
  # either writer runs — a provider-side refusal must leave the package side
  # byte-identical (and vice versa), never a half-installed user scope.
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_package_state)" --preflight >/dev/null
  python3 "$REPO_DIR/scripts/register-pi-provider.py" install "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_provider_state)" --preflight >/dev/null
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_package_state)"
  # #46 Task 2: own entwurfProvider.mcpServers.entwurf-bridge as the bare stable bin at USER scope
  # (GLOBAL/durable →파급s to every cwd), so its inverse needs an install-state honest inverse
  # under $XDG_DATA_HOME/entwurf/pi-provider/ (Task 0/1 discipline). project scope is checkout-
  # local and covered by `run.sh remove` (no state) — deliberate, reasoned asymmetry.
  # #86 C2: the provider state records installerRoot, so the same foreign-owner refusal
  # holds here — and the package refusal above fires FIRST, before any provider write.
  python3 "$REPO_DIR/scripts/register-pi-provider.py" install "$agent_dir/settings.json" "$REPO_DIR" --scope user --state "$(_pi_provider_state)"
}

# takeover-user-scope — the operator-explicit ownership move (#86 C2). The ONLY
# writer that replaces another root's user-scope registration: normal install/
# setup/remove refuse instead. Reports old→new for both the packages[] entry
# (packageRoot) and the provider key (installerRoot). No --force variant exists.
takeover_user_scope() {
  local agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" pp_out
  command -v python3 >/dev/null 2>&1 || { echo "[takeover] requires python3 on PATH; nothing was written." >&2; exit 1; }
  section "takeover-user-scope: move the shared user-scope registration to this root"
  # ATOMIC (#86 C2 amendment): both halves decided READ-ONLY first — an exact-entry
  # mismatch on the package side or a refusal on the provider side leaves the other
  # half byte-identical.
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_package_state)" --takeover --preflight >/dev/null
  python3 "$REPO_DIR/scripts/register-pi-provider.py" install "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_provider_state)" --takeover --preflight >/dev/null
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_package_state)" --takeover
  pp_out=$(python3 "$REPO_DIR/scripts/register-pi-provider.py" install "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_provider_state)" --takeover)
  printf '%s\n' "$pp_out"
  # Split verdict (#86 C2 amendment): a user-override provider key is preserved and
  # stays UNOWNED — say exactly which half moved instead of a false "both owned".
  if printf '%s' "$pp_out" | grep -q 'provider override preserved'; then
    ok "takeover-user-scope: package owner moved to this root ($REPO_DIR); provider key preserved as the operator's override (unowned — doctor-pi-provider reports it as such)"
  else
    ok "takeover-user-scope: this root now owns the user-scope registration ($REPO_DIR)"
  fi
}

# doctor-pi-package — package-side ownership verdict only (#86 C2): unregistered /
# owned / owned-by-other(live) / legacy-no-state / mismatch / missing-owner.
# Deliberately NOT mixed into doctor-pi-provider (provider runtime verdicts stay there).
doctor_pi_package() {
  local agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  command -v python3 >/dev/null 2>&1 || { echo "[doctor-pi-package] requires python3 on PATH." >&2; exit 1; }
  # #86 C2 amendment: the provider state rides along for the OWNERSHIP coupling
  # verdict only (installerRoot vs packageRoot mismatch = FAIL); provider RUNTIME
  # verdicts stay with doctor-pi-provider.
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$(_pi_package_state)" --provider-state "$(_pi_provider_state)" --doctor
}

# The honest inverse of register_user_scope_citizen: drop entwurf from the GLOBAL
# ~/.pi/agent/settings.json packages[]. Deliberately NOT folded into `run.sh remove`
# (project scope): the user-scope citizen is a single GLOBAL entry keyed on this
# checkout and SHARED by every project + every foreign cwd, so tearing it down as a
# side effect of one project's remove would break `--entwurf-control` everywhere else
# (the exact "install → just works from any cwd" invariant register_user_scope_citizen
# exists to hold). Same explicit-global-lifecycle shape as install/uninstall-meta-bridge.
# Uses the same is_entwurf_source SSOT + --remove, so it never over-deletes a look-alike
# (entwurf-notes, openclaw-entwurf) and preserves every other package/key. Idempotent:
# no entwurf entry → no-op. A settings-relative entry naming this repo is preserved and
# reported rather than deleted — install never writes that form (#53 B).
remove_user_scope_citizen() {
  local agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  local pkg_state pp_state orphan_args=()
  pkg_state="$(_pi_package_state)"; pp_state="$(_pi_provider_state)"
  # #86 C2 aligned orphan path: --orphan-cleanup is passed ONLY when the package
  # entry, the package state's packageRoot and the provider state's installerRoot
  # all name the SAME root and that root is MISSING on disk. Any live foreign
  # owner, or any mismatch between the three, refuses inside the SSOTs instead.
  if python3 - "$agent_dir/settings.json" "$pkg_state" "$pp_state" <<'PY'
import json, os, sys
settings_path, pkg_state_path, pp_state_path = sys.argv[1:4]
def load(p):
    try:
        with open(p) as fh: return json.load(fh)
    except (OSError, json.JSONDecodeError): return None
pkg = load(pkg_state_path)
if not isinstance(pkg, dict) or not isinstance(pkg.get("packageRoot"), str): sys.exit(1)
owner = pkg["packageRoot"]
if os.path.isdir(owner): sys.exit(1)                      # live owner: never orphan
# Alignment REQUIRES the provider state to exist AND to be bound to the same
# missing root (#86 C2 amendment): an absent, legacy (no installerRoot) or
# elsewhere-bound provider state is NOT alignment — both sides refuse instead.
pp = load(pp_state_path)
if not isinstance(pp, dict): sys.exit(1)
if pp.get("installerRoot") != owner: sys.exit(1)
settings = load(settings_path)
pkgs = settings.get("packages") if isinstance(settings, dict) else None
if not isinstance(pkgs, list): sys.exit(1)
def src(x): return x.get("source") if isinstance(x, dict) else x
if not any(isinstance(src(x), str) and src(x).rstrip("/") == owner for x in pkgs): sys.exit(1)
sys.exit(0)
PY
  then
    orphan_args=(--orphan-cleanup)
    log "remove-user-scope: package entry + package state + provider installerRoot align on a MISSING owner — reported orphan cleanup"
  fi
  # ATOMIC (#86 C2 amendment): both removal halves are decided READ-ONLY first, so
  # a provider-side refusal (live-other, legacy, mismatch) leaves the package
  # entry/state byte-identical instead of a half-removed user scope.
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$pkg_state" --remove ${orphan_args[@]+"${orphan_args[@]}"} --preflight >/dev/null
  python3 "$REPO_DIR/scripts/register-pi-provider.py" remove "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$pp_state" ${orphan_args[@]+"${orphan_args[@]}"} --preflight >/dev/null
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$pkg_state" --remove ${orphan_args[@]+"${orphan_args[@]}"}
  # #46 Task 2: honest inverse of the user-scope entwurfProvider ownership — the install-state
  # drives it (absent/managed-* → remove OUR key; a user-override we never owned is untouched).
  # #86 C2: installerRoot makes this same-owner-only; the aligned orphan flag rides along.
  python3 "$REPO_DIR/scripts/register-pi-provider.py" remove "$agent_dir/settings.json" "$REPO_DIR" \
    --scope user --state "$pp_state" ${orphan_args[@]+"${orphan_args[@]}"}
}

# The ~/.pi/agent/entwurf-targets.json symlink machinery (ensure_agent_dir_symlinks
# + the `setup:links` command) is GONE (#50 C3): the target registry it linked has
# no reader anymore — v2 addresses record-backed citizens and never resolves a spawn
# model from a file. An operator's existing link/copy is inert; nothing reads it.

remove_local_package() {
  local project_dir
  project_dir=$(normalize_project_dir "$1")
  # Same fail-before-write rule as install: remove has two writers too
  # (packages[] SSOT, then entwurfProvider cleanup), so a malformed provider must
  # not leave a half-removed packages[] entry behind.
  preflight_pi_settings_shapes "$project_dir/.pi/settings.json" "$(mktemp -u)"
  # packages[] cleanup via the shared SSOT — same is_entwurf_source predicate as
  # install, so remove never over-deletes a look-alike repo (entwurf-notes, …)
  # that install would never have registered. Same rule, one shape further (#53 B):
  # register only ever WRITES the absolute path, so a settings-RELATIVE entry naming
  # this repo (the committed `".."` in <repo>/.pi/settings.json) is source, not
  # install state — remove leaves it and says so instead of editing tracked bytes.
  python3 "$REPO_DIR/scripts/register-pi-package.py" "$project_dir/.pi/settings.json" "$REPO_DIR" --remove
  # entwurfProvider.mcpServers.entwurf-bridge cleanup (project scope) via the shared SSOT: strip
  # our-managed shapes (the bare stable bin AND the legacy repo start.sh path — a true user
  # override is left in place) + prune legacy bundles. Mirrors install's ownership predicate so it
  # never over-deletes a look-alike, and now also catches the bare bin the Task-2 install writes.
  python3 "$REPO_DIR/scripts/register-pi-provider.py" remove "$project_dir/.pi/settings.json" "$REPO_DIR" --scope project
  # `remove` is project-scope only. The GLOBAL user-scope citizen in
  # ~/.pi/agent/settings.json (written by install's register_user_scope_citizen)
  # is shared across every project + foreign cwd, so it is left intact here to
  # avoid breaking `--entwurf-control` elsewhere. Point the operator at the
  # explicit global inverse so the install↔remove asymmetry is never silent.
  local agent_settings="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/settings.json"
  if python3 "$REPO_DIR/scripts/register-pi-package.py" "$agent_settings" "$REPO_DIR" --remove --dry-run 2>/dev/null | grep -q 'would remove'; then
    log "note: global user-scope citizen still registered in $agent_settings"
    log "      run './run.sh remove-user-scope' to remove it (affects ALL cwds)"
  fi
}

check_model_lock() {
  # Deterministic policy unit test for pi-extensions/model-lock.ts.
  # No pi process, no network, no API cost. Mocks ExtensionAPI/Context and
  # drives the model_select handler through every quadrant + edge case
  # (see scripts/check-model-lock.ts header for the full matrix).
  run_ts scripts/check-model-lock.ts
}

check_shell_quote() {
  # POSIX-safety gate for the shellQuote helper used in remote SSH command
  # builders (entwurf.ts + entwurf-core.ts). Verifies source-string parity
  # across the two duplication sites AND behavioral correctness on the
  # payload classes that caused the 2026-05-18 remote entwurf incident
  # (backtick / $(...) / $VAR / korean tokens). No process spawn, no SSH.
  run_ts scripts/check-shell-quote.ts
}

check_entwurf_session_identity() {
  # Deterministic gate for the record-era session identity contract: garden-id
  # grammar (validator/generator — the RECORD's gardenId shape), readSessionIdentity
  # (first model_change authority, drift fail-fast, name-blind — #50 C3), and the
  # 🪛 status label. Isolates the sessions base to a temp dir. No backend, no API,
  # no spawn.
  run_ts scripts/check-entwurf-session-identity.ts
}

check_meta_session() {
  # Deterministic gate for the meta-bridge STORE authority (#30 step 2, V3-only
  # since the #50 cut — the pure record contract moved to check-meta-v3-record,
  # the scan/read seam to check-meta-identity-consumers): idempotent
  # existence-keyed decideUpsert + identity-drift
  # refusal, and the pre-drilled read-receipt mutators. Pure functions; no
  # backend, no hook, no API.
  run_ts scripts/check-meta-session.ts
}

check_meta_v3_record() {
  # Deterministic gate for the ONE live record schema (v3). Canonical serialize
  # + round-trip, v3 mint, the reader rejecting any foreign generation naming
  # the fresh-cut command (with the actual version value), and the strict
  # keyset (retired/unknown fields are stray, never coerced). Pure functions;
  # no backend, no hook, no API.
  run_ts scripts/check-meta-v3-record.ts
}

check_mailbox_receipt_state() {
  # Deterministic gate for 0.11 Stage 0 step 3B: the mailbox receipt state
  # schema + store — the SOLE home of the read-receipt since 3D-4 deleted
  # record.delivery with the rest of delivery{} (#50 is V3-only, and v3 never
  # had the field). Pure schema round-trip + strict keyset, then the fs store
  # (stamp → persist → read-back) in a temp mailbox dir. Schema/store only —
  # the live enqueue/read path landed in 3D-4 and is gated by
  # check-meta-mailbox-state-write. No backend, no hook, no API.
  run_ts scripts/check-mailbox-receipt-state.ts
}

check_entwurf_capabilities() {
  # Deterministic gate for 0.11 Stage 0 step 3C: the backend capability source
  # (pi/entwurf-capabilities.json) — the SOLE home of wakeMode/deliveryLevel/
  # nativeIdLabel since 3D-4 dropped delivery{} from the record (frozen decision
  # 1; v3 never carried it). Asserts coverage == META_CITIZEN_BACKENDS (pi included),
  # agreement with META_BACKEND_DESCRIPTORS for the three existing backends —
  # which since the 3D-3 cut-over survives ONLY as that drift-guard reference —
  # and strict keyset/coverage/field crashes. Parser/gate only — the consumer
  # seam it feeds is gated by check-meta-capability-source. No backend, no API.
  run_ts scripts/check-entwurf-capabilities.ts
}

smoke_omp_fresh_live() {
  # #87 Bundle C acceptance, RELEASE MUST. Opens omp as ONE visible fresh sibling through
  # the PUBLIC entwurf_fresh_call surface in a private tmux server, correlates the exact
  # nonce callback to a garden id from the SENDER ENVELOPE, then delivers an addressed
  # message the sibling drains in that same native session. Decides its own outcome: omp
  # absent from FRESH_CALL_BACKENDS or without a mailbox rail is a protocol SKIP, LIVE!=1
  # is a protocol SKIP, and once the composition offers the backend every missing
  # prerequisite is a FAIL. Writes into the REAL meta roots — the extensions run inside the
  # launched omp process and no env carrier on the fresh argv could fence them.
  run_ts scripts/smoke-omp-fresh-live.ts
}

check_omp_fresh_preflight() {
  # #87 Bundle C. The OMP fresh preflight REPRODUCES two resolvers that already exist
  # in this repo in another language — omp_agent_dir (scripts/omp-bridge-oracle.sh) and
  # the tools.xdev half of scripts/omp-tool-surface.py — because the preflight runs from
  # two different emit depths and cannot resolve a sibling script by relative path. A
  # reproduction nothing compares is a divergence with a date on it, so this drives the
  # SHIPPED shell and python leaves and requires the TS half to agree, refusals included.
  # Never asks the resolver under test to confirm itself. Fixtures only; never reads ~/.omp.
  run_ts scripts/check-omp-fresh-preflight.ts
}

check_harness_admission_parity() {
  # #87 Bundle C. The EDGE between two parity loops that were each closed and had
  # nothing between them: check-entwurf-capabilities held registry ==
  # META_CITIZEN_BACKENDS, the fresh-call surfaces contract held surfaces ==
  # FRESH_CALL_BACKENDS, and no file read both constants. So a harness could be a
  # full D6 citizen that entwurf_fresh_call cannot open, with every gate green and
  # only prose saying it was not supported — which is how an `unsupported` label
  # started reading as a partial-release permit. Asserts every citizen backend is
  # either fresh-openable or a DECLARED pre-#82 legacy admission whose exception a
  # reader can find in DELIVERY.md, both directions, no third state. Pure parse.
  run_ts scripts/check-harness-admission-parity.ts
}

check_capability_bundle_reach() {
  # The gate check-entwurf-capabilities structurally cannot be. That gate imports
  # metaCapabilitiesFilePath() from ../pi-extensions/lib/ — the one location where
  # its relative path arithmetic is correct — so "the registry resolves" is a
  # tautology there. This one DISCOVERS every shipped copy of the module and
  # re-asks each from where it actually lives, including the bridge bundle emit at
  # mcp/entwurf-bridge/dist/pi-extensions/lib/ that answers the real entwurf_v2.
  # Requires a built bridge; a missing dist FAILS (never skips).
  run_ts scripts/check-capability-bundle-reach.ts
}

check_bridge_delivery() {
  # demo/demo.sh scene 3, recovered as a deterministic gate. demo drove two real pi
  # panes so it proved DELIVERY through the installed binary (at model cost); what
  # replaced it split in half — matrix-live C2 delivers but from repo source
  # in-process, while bridge-boot/pack-install/install-container run the artifact but
  # only tools/list. entwurf_v2 through the shipped bundle was never executed once,
  # and it shipped dead through 0.12.8-repair.0. This seeds an armed self-fetch
  # citizen (C2 recipe) into an env-isolated temp world, then drives the BUILT DIST
  # ENTRY as its own process over MCP stdio through a real tools/call entwurf_v2 and
  # asserts the .msg physically landed + the doorbell was poked. Seeder is source,
  # subject is the artifact, separate processes. No model, no network, no cost.
  run_ts scripts/check-bridge-delivery.ts
}

smoke_pi_attach() {
  # The #50 C2 checkpoint gate: pi attaches as a meta-record citizen and the BUILT
  # ARTIFACT routes that garden id to its control socket. Two halves, deliberately
  # different in kind: the record+address half drives `birthPiCitizen` (the exact seam
  # entwurf-control's session_start calls) so the gate is deterministic and lives in
  # `pnpm run check:full`; the delivery half spawns the dist entry as its own process and speaks
  # MCP stdio (check-bridge-delivery's driver, socket-rail fixture). P4 is the one with
  # teeth — re-opening the same pi session must ATTACH to the same gardenId, never mint
  # a second address under peers that already hold it. P8 (#50 C3 tail) gates goal 3:
  # the REAL ACP env enrichment carries the host record's gardenId into the bridge
  # child, and a send from that child lands AS the host record identity. That a REAL
  # pi process runs the seam is the LIVE axis (smoke-resident-garden-guard), not this one.
  run_ts scripts/smoke-pi-attach.ts
}

check_meta_mailbox_state_write() {
  # Deterministic gate for 0.11 Stage 0 step 3D-4 commit2 (the cut). Renamed from
  # check-meta-mailbox-dualwrite: after the cut the receipt is no longer dual-written
  # (there is no record.delivery on the identity record) — it lives SOLELY in the mailbox
  # state store. Asserts the meta-record FILE is byte-identical before/after enqueue
  # AND read (enqueue/read no longer touch the record — invariant ⑤), the state
  # carries lastEnqueuedAt/lastReadAt with field isolation, lastDeliveredAt is never
  # invented, an empty inbox is a no-op on BOTH record and state (⑥), and a state
  # drift surfaces fail-loud. v2 citizen seeded via upsertMetaSession. No API.
  run_ts scripts/check-meta-mailbox-state-write.ts
}

check_meta_receiver_marker() {
  # Deterministic gate for the meta-receiver presence marker (SE-2 slice 2b). The
  # active-receiver signal a self-fetch backend (Claude Code) needs: a meta-record
  # proves a session once existed; this marker proves a live watch owner is still
  # there to be woken, so a terminated session's lingering record does not read as a
  # ghost active receiver (mailbox garbage). Asserts: write→read round-trip keyed by
  # GARDEN id, atomic 0600; dead-owner/pid-reuse start-key guard reads null (distinct
  # from "no marker"); armProvenance constrained to the arm-capable events so
  # UserPromptSubmit cannot mint presence; reader does NOT gate on record existence
  # (recordBacked is the deliverability predicate's fact). Real tmpdir, no API.
  run_ts scripts/check-meta-receiver-marker.ts
}

check_meta_hook_session_switch() {
  # #101 gate: a Claude Code SESSION SWITCH — one native process that stops serving one
  # garden and starts serving another. The resume picker (and `/clear`) fire SessionStart
  # twice inside one pid: once for the TUI's placeholder id, once for the id the operator
  # picked. Before this gate nothing asked "one owner pid, two gardens", so a placeholder
  # citizen stayed registered with an armed-looking doorbell and real mail rotted in it.
  # Plays Claude the way check-hook-launch-topology does (spawn the SHIPPED launcher with
  # the manifest's argv, so the hook's parent is this process = one fake owner pid) with
  # every meta root sandboxed. Asserts: both records survive (marker retired, never the
  # record); the retired garden's marker is gone; a same-garden re-registration retires
  # NOTHING; a re-planted stale marker is still undeliverable (the sender-marker join,
  # fail-closed at the reader); production dispatch refuses it and carries the predicate's
  # reason to the rendered surface; exactly one garden is deliverable and it is the served
  # one. Real tmpdir, no API.
  run_ts scripts/check-meta-hook-session-switch.ts
}

check_copilot_birth_hook() {
  # #82 gate: the Copilot BIRTH path, proven without Copilot. Drives the REAL
  # assembler (--assemble-only, into a temp dir), then fires the baked launcher the
  # way Copilot fires it — NO ARGV, envelope on stdin — and requires a v3 record with
  # backend "copilot", an attach on the second event of the same prompt, no
  # mailbox/marker of any kind, and a peer row with liveness `unsupported`. Refusals
  # (disagreeing ids, missing cwd, no id, malformed) must refuse rather than guess.
  # It proves the MECHANISM, never the admission: §6 acceptance is a record minted by
  # a real Copilot session, which costs a model turn.
  run_ts scripts/check-copilot-birth-hook.ts
}

check_copilot_statusline() {
  # #82 Copilot custom-footer renderer. Drives scripts/copilot-statusline.sh with
  # session_id on stdin in an isolated store. ready / ? / exact gid; exit 0.
  run_ts scripts/check-copilot-statusline.ts
}

check_copilot_launch() {
  # #82 RAIL 7. The subject is a process REPLACEMENT, so the oracle is a fake vendor
  # executable on a sandboxed PATH that reports the argv/env/pid/cwd it was handed —
  # never a reading of the launcher's source. HOME/XDG/PATH are all redirected, so the
  # install-state, the extensions root and the resolved binary are the fixture's.
  run_ts scripts/check-copilot-launch.ts
}

check_copilot_receive_arm() {
  # #82 RAIL 5 gate: drives the REAL receiver installer into a temp extensions dir, then
  # forks the REAL extension.mjs with the SDK specifier resolved by a loader hook (the
  # vendor's own mechanism). Binds arm-after-birth, watcher-owned marker, the self-fetch
  # dispatch answer, a doorbell that carries the id and not the body, and every refusal.
  # Needs the compiled bridge closure; hermetic otherwise (no Copilot, no model turn).
  run_ts scripts/check-copilot-receive-arm.ts
}

check_hook_launch_topology() {
  # #51 gate 1, deliberately built only AFTER the B/B2 verdict. Binds the SHIPPED
  # hooks.json to real child topology: every leaf is exec form through the shipped
  # hook-launch.sh, the launcher refuses an empty argv (the only visible symptom of an
  # older Claude silently dropping `args`), and `exec` preserves the pid so the hook's
  # parent is the process that stood in for Claude. Includes a plugin path containing
  # space/$/backtick/;& — under exec form that is one opaque argv element, which is
  # exactly what the retired shell form could not promise. No API, no live session.
  run_ts scripts/check-hook-launch-topology.ts
}

check_meta_identity_consumers() {
  # Deterministic gate for the V3-only identity consumer seam (#50 hard cut).
  # readMetaIdentityByGardenId reads v3 to identity (drift fail-fast, a
  # foreign-generation record names fresh-cut), and certifyActiveStore holds the
  # ONE active-store contract the doctor and every writer share: regular files,
  # live schema, no body/filename drift, globally unique nativeSessionId (THE G1
  # invariant). Each rule is proven on its own store, and a writer refuses even a
  # defect that involves neither of its own ids. Temp dir, no API.
  run_ts scripts/check-meta-identity-consumers.ts
}

check_meta_capability_source() {
  # Deterministic gate for 0.11 Stage 0 step 3D-3: the capability-source cut-over.
  # mint/parse now read backend honesty metadata (wakeMode/deliveryLevel) from the
  # capability registry (3C) via metaCapabilityFor, NOT META_BACKEND_DESCRIPTORS.
  # Proves the seam is registry-DRIVEN (a doctored registry injection is followed),
  # mint sources delivery metadata through it, the parse drift guard is now
  # registry-sourced, and the cut-over preserves behaviour (registry ≡ const for the
  # 3 backends). At 3D-3 only the SOURCE moved and the record.delivery.wakeMode SLOT
  # still existed; 3D-4 then deleted that slot with the rest of delivery{}, so today
  # the registry is the sole home. check-entwurf-capabilities still owns the registry ≡ const drift
  # guard. Pure — no fs writes, no backend, no hook, no API.
  run_ts scripts/check-meta-capability-source.ts
}

check_socket_probe() {
  # Deterministic gate for 0.11 Stage 0 (F3 fix): three-valued control-socket
  # liveness. classifyConnectError is a pure boundary (ECONNREFUSED/ENOENT →
  # dead; timeout/EACCES/unknown → indeterminate). GC reclaims dead only;
  # indeterminate (a load-stalled live socket) survives the sweep — the F3
  # invariant. Listing lists alive only. Pure classify + GC/listing policy +
  # a two-socket integration (live listener → alive survives; nonexistent →
  # dead GC-eligible). No wire timeout fixture, no backend, no API.
  run_ts scripts/check-socket-probe.ts
}

check_project_trust_handler() {
  # Deterministic gate for 0.11 Stage 0 (Trust 2층 active-prompt escape): the
  # project_trust handler. Pure decideProjectTrust over real preflight outcomes —
  # approve/trusted-no-arg→{yes,remember:false}; direct distrust→{no}; inherited
  # distrust + interactive + "trust-here"→{yes,remember:true} (THE escape, beats
  # the ancestor false); non-interactive (pi -p / rpc)→{undecided}, never prompts;
  # never undefined. Plus the thin adapter: fake ctx.ui.select, single-writer
  # (handler never calls store.set — pi persists on remember:true), F5a evidence
  # in the prompt title. No real UI, no backend, no API.
  run_ts scripts/check-project-trust-handler.ts
}

check_entwurf_v2_contract() {
  # Deterministic gate for 0.11 Stage 0 step 4-pre: the FROZEN entwurf_v2
  # contract (동결결정 10 + 버킷 B F1/F4/F6 + Fable R1-R5). The intent×liveness
  # decision table is a constant; the "table cell ↔ dispatch receipt" round-trip
  # is asserted exhaustively — THE executable proof F6 demands ("산문 금지").
  # R1 control-socket capability domain (currently pi; claude-code/codex/antigravity =
  # unsupported, never folded into dead/indeterminate). 3-cell table since the
  # visible-first cut, single verdict per cell, 1 allow / 2 reject. N1
  # indeterminate never dispatches, and nothing on any cell starts a process.
  # R5 taxonomy covers table reasons + pre-claims bad-target/target-locked. Plus
  # a schema↔types drift guard on the TypeBox input/receipt. Pure, no API.
  run_ts scripts/check-entwurf-v2-contract.ts
}

check_entwurf_v2_lock() {
  # Deterministic gate for 0.11 Stage 0 step 5a (버킷 B F2): the per-gid dispatch
  # LOCK primitive — what serializes concurrent in-domain dispatch at one
  # target (pi self-guards CREATE but not RESUME, 검증원장 F2). acquire =
  # openSync(lockPath,"wx") atomic; a second acquire without release =
  # target-locked conflict carrying the holder JSON (F2-P2 human cleanup). release
  # = unlink ONLY when the on-disk nonce is still ours (a successor's re-acquire
  # survives a late release). Stale reclaim ONLY for same host + ESRCH; EPERM
  # (other user's live pid) / different host / alive pid / unknown error all
  # fail-closed to conflict. Empty/corrupt lockfile = conflict, never
  # auto-deleted. F2-P1: a malformed gid throws before any path is built. Real
  # temp dir (wx atomicity under test); clock/nonce/pid/host/kill injected.
  run_ts scripts/check-entwurf-v2-lock.ts
}

check_entwurf_v2_decider() {
  # Deterministic gate for 0.11 Stage 0 step 5b: the PURE dispatch decider
  # decideDispatch. Drives the frozen 7-step order over INJECTED fakes (target
  # lookup / lock / socket inspect+probe / preflight / capability), tracking lock
  # acquire+release so "reject ⇒ no plan AND no lock retained" is PROVEN. Covers:
  # bad-target/target-locked/target-address-conflict carry observedLiveness=null
  # (pre-probe), every other reject carries a measured value; a control-socket send
  # executes KEEPING the lock, meta-mailbox send takes NO lock (？7); an invalid gid throws before
  # any lookup (F2-P1). Pure, no IO, no API.
  run_ts scripts/check-entwurf-v2-decider.ts
}

check_entwurf_v2_matrix() {
  # Deterministic gate for 0.11 Stage 0 step 5d-5 (a): the REACHABILITY + LOCK SSOT
  # TABLE. Drives the REAL decideDispatch over minimal injected fakes and fixes, as
  # one readable table, every (target kind → transport → lock class) cell the 5d-5
  # claim covers: bad-target/address-conflict/target-locked rejects, unsupported
  # meta-mailbox (deliverable) vs mailbox-undeliverable (inactive) reject,
  # in-domain control-socket (live) / released rejects
  # (ff-dormant, indeterminate, under-lock conflict). A coverage pass
  # FAILS if any transport / lock class / pre-probe reject is missing — a dropped
  # decider cell cannot pass silently. Thin coverage, NOT a decider re-impl; surface
  # parity stays in check-entwurf-v2-surface. Pure, no IO, no API.
  run_ts scripts/check-entwurf-v2-matrix.ts
}

check_entwurf_v2_release() {
  # Deterministic gate for 0.11 Stage 0 step 5c-1: the PURE release-policy reducer
  # (decideReleasePolicy + reduceRelease) for the 5c transport hand. Proves the
  # Fable-3 "release-after-observation" timing as a pure state machine BEFORE any
  # send IO: meta-mailbox=never release (no lock), control-socket=release once
  # on send-final. The spawn-observation policy and its four release events went with
  # the transport in the visible-first cut; decideReleasePolicy still enforces the
  # lock-nullness invariant (？7). Pure, no IO.
  run_ts scripts/check-entwurf-v2-release.ts
}

check_entwurf_v2_send() {
  # Deterministic gate for 0.11 Stage 0 step 5c-2a: the control-socket SEND hand
  # (executeControlSocketSend) that WIRES real transport IO onto the 5c-1 release
  # reducer. Proves the send->outcome->release ordering over injected fakes (no socket):
  # ack->sent / in-band reject->rejected (no fallback) / dead->same-lock one-shot
  # re-resolve (control retry or mailbox enqueue)->fallback-sent|rejected|failed /
  # indeterminate->failed+rethrow with deadFallback+mailbox NEVER called (no
  # double-delivery on an alive-but-stalled socket). Release fires exactly once per
  # send-final; a releaseLock throw never masks the send failure (5b). IO-via-dep.
  run_ts scripts/check-entwurf-v2-send.ts
}

check_entwurf_v2_send_fallback() {
  # Deterministic gate for 0.11 Stage 0 step 5c-2b: the same-lock re-resolve RESOLVER
  # (resolveDeadControlSendFallback) the 5c-2a hand calls on a dead connect. Proves the
  # fire-and-forget re-resolve routing over injected fakes (no filesystem): alive->
  # control-socket retry (inspected socketPath) / dead(absent)->reject (dormant-fire-
  # forget-unsupported, and nothing is launched) / indeterminate->reject / unsupported+deliverable
  # ->meta-mailbox plan (mini-table, no inspect/probe) / unsupported+undeliverable->reject
  # / bad-target + address-conflict->reject pre-probe. Mis-wire (plan/lock gid) fails loud
  # before IO; inspect/probe throws PROPAGATE (the hand owns failed+release); the resolver
  # has NO release seam; every execute plan keeps the held gid.
  run_ts scripts/check-entwurf-v2-send-fallback.ts
}

check_entwurf_v2_mailbox() {
  # Deterministic gate for 0.11 Stage 0 step 5c-4 (the LAST 5c transport slice): the
  # ENQUEUE-ONLY meta-mailbox SEND body (executeMetaMailboxSend) + its production
  # sendViaMailbox adapter (makeProductionSendViaMailbox). Proves the wiring over an
  # injected fake enqueue (no filesystem): sender present -> formatMetaMailboxBody with
  # plan.wantsReply threaded (yes/no in body, the deliberate divergence from legacy's
  # hard-coded false) / sender absent -> raw plan.message / enqueue opts EXACTLY
  # {gardenId: plan.targetGardenId, body, sessionsDir, mailboxDir} (no re-derivation) /
  # enqueue throw PROPAGATES (never folded into success:false — a mailbox has no in-band
  # refuse) / success -> {success:true}. Production adapter resolves {success:true},
  # consults senderProvider once, and NEVER touches the lock (a poison LockClaim whose
  # every access throws still resolves). Source guard: the lib code has NO release seam
  # and NO routing seam (no releaseLock / inspect / probe / resolve) — a lock leak or
  # re-route is structurally impossible.
  run_ts scripts/check-entwurf-v2-mailbox.ts
}

check_entwurf_v2_native_push() {
  # Deterministic gate for 봉인 3/4: the native-push SEND hand (deliverViaNativePush +
  # makeNativePushSend), the executor half of the native-push rail — where the 1-shot retry
  # lives (moved out of the adapter leaf). Proves over a fake adapter (no agy/socket): success
  # first try -> {retried:false}, ONE send over the planted route, ZERO re-probe; fail ->
  # re-probe alive -> re-send success -> {retried:true}, TWO sends, the 2nd over the RE-
  # DISCOVERED route; re-send FAIL -> throws (no 3rd attempt); re-probe dead/indeterminate ->
  # throws (not retried), NO second send. makeNativePushSend resolves the adapter from
  # plan.backend and IGNORES the lock (lock-free rail).
  run_ts scripts/check-entwurf-v2-native-push.ts
}

check_entwurf_v2_runner() {
  # Deterministic gate for 0.11 Stage 0 step 5d-1: the execute-router (executeDispatch) that
  # routes an already-decided DispatchDecision to its 5c transport hand and maps the outcome
  # to one outcome-rich EntwurfV2RunResult. Proves over injected fake hands (no socket/spawn/
  # timer): reject -> rejected (receipt+diagnostic carried, NO hand called) / control-socket ->
  # sendControl(plan, lock) / meta-mailbox -> sendMailbox(plan, NULL
  # lock, ？7). Carry-overs: N3 control `rejected` carries rejectReason verbatim; N1
  # SendDeliveredReleaseFailedError -> execution-failed{finalizedOutcome, releaseFailed,
  # retrySafe:false}; a plain hand throw -> execution-failed{retrySafe:false} with no
  # finalizedOutcome. Exactly one hand runs per execute.
  run_ts scripts/check-entwurf-v2-runner.ts
}

check_entwurf_v2_surface() {
  # Deterministic gate for 0.11 Stage 0 step 5d-3a: the ctx-free surface adapter
  # (entwurf-v2-surface.ts) + the entwurf-control.ts wiring contract. Proves the pure parts:
  # toDispatchInput (wants_reply→wantsReply, absent mode/wants_reply undefined) / renderEntwurfV2Result
  # per result kind ({text,isError} surfacing reject diagnostic, control N3 rejectReason,
  # N1 delivered-but-dirty) + the dormant/indeterminate reject HINTS an operator meets after the
  # visible-first cut / surface ctx-free source guard / entwurf-control
  # registers entwurf_v2 + reaches the fence via a NON-LITERAL dynamic import (no static fence
  # import → TS5097 stays closed) + decorates sender origin:pi-session/replyable:true.
  run_ts scripts/check-entwurf-v2-surface.ts
}

check_entwurf_bridge_boot() {
  # Deterministic gate for 0.11 step 5d-5-pre (G1a/G1b): boots the entwurf-bridge MCP server
  # as it ships (start.sh → node --experimental-strip-types, no build) and asserts what the
  # source-shape gate check-entwurf-v2-surface cannot — that the whole v2 fence graph LOADS at
  # boot under strip-types (G1a: a parseable tools/list proves it) and that entwurf_v2 is
  # registered on the runtime surface with its schema (G1b). tools/list only → no tools/call,
  # no lock/fs side effect, no auth → safe in pnpm run check:full. Broad protocol/negative suite stays
  # in check-bridge/test.sh (D1=A안).
  run_ts scripts/check-entwurf-bridge-boot.ts
}

check_entwurf_bridge_pi_free() {
  # 0.12.1 A-gate (static half): the entwurf-bridge MCP server must boot WITHOUT any
  # pi package. entwurf is a harness-neutral npm package; pi is one optional adapter
  # lane, not a boot dependency. Walks the EAGER static value-import closure of
  # mcp/entwurf-bridge/src/index.ts and fails if any reachable module statically
  # value-imports @earendil-works/pi-*. Type-only imports and dynamic `await import()`
  # (the intended lazy preflight boundary) are excluded — the runtime boot smoke is the
  # final authority that peers/self/list/mailbox-deliver come up pi-free.
  run_ts scripts/check-entwurf-bridge-pi-free.ts
}

check_entwurf_v2_production() {
  # Deterministic gate for 0.11 Stage 0 step 5d-2b: makeProductionEntwurfV2Deps — the ctx-free
  # PRODUCTION assembly of runEntwurfV2's deps. Proves the wiring over fake leaf-IO spies (no
  # real socket/lock/meta-record): decide wraps decideDispatch and acquires under the
  # wired lockDir / control sendOverSocket builds the RpcSendCommand + maps + releases under
  # lockDir / the mailbox hand enqueues onto the wired dirs / a dead control send
  # re-resolves to the SAME sendViaMailbox instance on the SAME dirs (Q3+Q5 no drift).
  run_ts scripts/check-entwurf-v2-production.ts
}

check_entwurf_control_rpc() {
  # Gate for 0.11 Stage 0 step 5d-2 (RPC-helper extraction micro-slice): the --entwurf-control
  # socket protocol (wire types + the newline-JSON client sendRpcCommand) moved to the ctx-free
  # SSOT lib/entwurf-control-rpc.ts behaviour-preservingly. Proves: lib is ctx-free (no
  # ExtensionContext/ExtensionAPI/@earendil-works/pi-ai) / entwurf-control.ts imports
  # sendRpcCommand from the lib and no longer defines its own / real short unix-socket round-trip
  # (write command -> matched {type:response,command,success:true} -> resolve) / close-before-
  # response rejects 'connection closed before response'. net.Server only, no model/pi process.
  run_ts scripts/check-entwurf-control-rpc.ts
}

check_entwurf_resume_args() {
  # Deterministic gate for the resume-argv SSOT (buildResumePiArgs). S1 replaced the headless
  # shape with the VISIBLE one, measured against the runtime before the consumer was written:
  # `-p` is pi's own non-interactive mode, so the old `--mode json -p … <prompt>` prefix would
  # put a JSON stream in the operator's window instead of a session they can use. Pins the one
  # shipped posture — `--entwurf-control` FIRST (the resumed session stands its socket up), no
  # --mode/-p/positional prompt (a resume runs no turn), explicitExtensionArgs exactly once
  # between the control flag and --session (#29 provider-resolution footgun), --session <abs
  # file> never --session-id (which MINTS), and a null provider emitting no --provider.
  run_ts scripts/check-entwurf-resume-args.ts
}

check_mux_launcher_fence() {
  # Deterministic gate for the shared operator-launcher fence (issue #67):
  # scripts/lib/claude-launcher-fence.ts plus its wiring into BOTH mux LIVE smokes. Replants the
  # observed install-destruction shape (real HOME + fixture XDG_DATA_HOME → self-update retargets
  # the real `claude` launcher into the fixture tree, teardown deletes it) entirely inside
  # disposable mkdtemp roots — the operator's real launcher is never inspected or touched. Pins:
  # fail-closed preflight (launcher and resolved target present, regular, executable, OUTSIDE the
  # fixture cleanup root), retarget/content-change detection before cleanup, removal BLOCKED when
  # the launcher references the fixture OR safety cannot be proven OR tracked panes are not gone
  # (known reference and unproven state each named as itself), exact operator-parity XDG restore
  # (absent means DELETED, never canonical defaults; RUNTIME_DIR stays fixture by design), the
  # lifecycle pi/claude cell-branch topology, and both smokes consuming the one shared helper.
  run_ts scripts/check-mux-launcher-fence.ts
}

check_mux_parent_artifact() {
  # Deterministic gate for the tracked scrubbed parent-transcript fixture
  # (scripts/fixtures/mux-parent-transcript.scrubbed.jsonl). The fixture is a version-pinned
  # SAMPLE OF THE PARENT-SIDE SHAPE — what an entwurf_fresh_call and the sibling's nonce callback
  # look like in the transcript of the citizen that made the call — so a downstream parser never
  # has to open a private transcript to learn it. Structure came from a fixture-only real Pi
  # parent retake and was then scrubbed. Pins: event order (fresh_call toolResult, then the later
  # callback custom_message), the toolCallId join on the RESULT (measured: pi writes no separate
  # toolCall row), the launch nonce reappearing verbatim in the callback body, the <sender_info>
  # envelope field names, and the absence of any operator path / real garden id / real uuid.
  # It is NOT placement evidence and the gate says so.
  run_ts scripts/check-mux-parent-artifact.ts
}

check_mux_resume_call() {
  # Deterministic gate for the S1 resume placement composition (mux-resume-call.ts). Same scope
  # as check-mux-launch/check-mux-fresh-call: no fake tmux, only what is decidable without one.
  # The cwd rules are MEASURED tmux 3.6a behaviours, each a way a resume looks successful while
  # being wrong — a nonexistent `-c` exits 0 and lands the child in $HOME, and `-c` is
  # FORMAT-EXPANDED so `#{…}` rewrites the path and `#(…)` was observed running a command.
  # Whitespace measured SAFE, so the refusal set stays at two rules with no escaping layer.
  # Also pins: `-c` reaches tmux, runtime after `--`, carrier-free argv, no identity in this
  # module, and the surface seam that keeps the v2 composition from importing mux.
  run_ts scripts/check-mux-resume-call.ts
}

check_entwurf_v2_visible_resume() {
  # Deterministic gate for the S1 visible-resume composition (entwurf-v2-visible-resume.ts).
  # Every seam is injected, so the whole state machine — including the timeout branch — runs
  # without tmux, a lock file, a socket or a clock. Pins: lock BEFORE liveness, identity under
  # the lock and before any window (a citizen with no transcript fails loud and opens nothing),
  # live/indeterminate/address-conflict refused unlaunched, the observation as a BOUNDED WAIT
  # (measured: the socket answers ~2–4s after launch, so one immediate probe would report a
  # successful resume as unobserved), exactly one launch on every path, timeout releasing the
  # lock and leaving the window open, a failed release throwing, and the two receipts staying
  # separate in both the type and the rendered text.
  run_ts scripts/check-entwurf-v2-visible-resume.ts
}

check_resume_launch_identity() {
  # Deterministic gate for resume-launch-identity.ts, the record-authoritative launch-identity
  # leaf preserved when the visible-first cut deleted spawn-bg and every caller it had. Identity
  # authority is fail-closed risk, so the preserved leaf does not ship on its header comment:
  # a temp meta-store fixture drives gardenId → record.transcriptPath → header-id integrity
  # (a foreign/stale transcript is refused, never resumed), the #52 ADDRESSABLE read (a garden id
  # that no longer holds its nativeSessionId alone is refused from either side), and cause
  # fidelity for every impossible resume — including the F7 pin that a recorded-but-deleted
  # transcript is reported as MISSING rather than as "no recorded model". No spawn, socket, or
  # timer: the launch this identity would feed is deliberately out of scope.
  run_ts scripts/check-resume-launch-identity.ts
}

check_mux_placement() {
  # Deterministic gate for the T0-b placement primitives (mux-placement.ts): the argv shapes,
  # the anchor precondition, the parse, and the close classification — everything decidable
  # without tmux. It does NOT simulate tmux; no fake tmux exists in this repo on purpose.
  # Topology is judged by check-mux-placement-tmux against a real private server.
  run_ts scripts/check-mux-placement.ts
}

check_mux_placement_tmux() {
  # REAL tmux acceptance: drives the production placement functions against a private fixture
  # server (unique -S socket, never the operator's), with TMUX/TMUX_PANE actually INHERITED by
  # a fixture pane. Proves one session throughout, 1,2 -> 1,2,3 -> 1,2,3,4 -> 1,2, surviving
  # pane pids and focus, stable @window/%pane handles, the display-message rc=0 trap and its
  # refusal, and both close paths (closed / already-gone). Skips (97) without tmux or /proc.
  # Operator-run: kept OUT of pnpm check, and it is not a release-gate MUST at T0.
  run_ts scripts/check-mux-placement-tmux.ts
}

check_mux_launch() {
  # Deterministic gate for the T1-a visible launch (mux-launch.ts): the named preconditions
  # that run BEFORE any window opens, the PATH resolution rule, the `--` argv shape, and the
  # docs §11 import boundary. It does NOT simulate tmux. The measured trap it exists for — a
  # failed exec exits 0, prints a handle, and its window is still listed on an immediate
  # re-read — is judged against a real server by check-mux-launch-tmux.
  run_ts scripts/check-mux-launch.ts
}

check_mux_fresh_call() {
  # Transition shim (issue #62): this lane is the vitest pilot, so the gate NAME is preserved
  # while the contracts live in test/*.test.ts. Same scope as before — the per-backend argv
  # dialects (both measured to fail the other way round), first-turn framing order, named
  # refusals, per-surface caller identity — PLUS the runtime axes the retired source-text gate
  # could not see: real bridge boot → tools/list schema/description, Rust-regex-family pattern
  # validity on every emitted pattern (the #62 escape), and the schema riding the actual
  # anthropic-messages request body. No fake tmux: the real-window axis is smoke-mux-fresh-call-live.
  # copilot-fresh-preflight rides here rather than in its own gate: it exists only as
  # freshCall's pre-mutation branch (#82 RAIL 9), and splitting it would let the two halves
  # of one refusal be certified in different runs.
  # omp-fresh-bootstrap.contract rides here for the same reason and one more: it is the ONLY
  # place the launcher's payload and the installed birth extension's decoder are read together.
  # They ship in different directories and cannot import each other (#87 Bundle C), so this
  # lane is what keeps a deliberate duplication from becoming drift.
  run_vitest test/mux-fresh-call.test.ts test/copilot-fresh-preflight.test.ts test/fresh-call-surfaces.contract.test.ts test/fresh-call-provider.contract.test.ts test/omp-fresh-bootstrap.contract.test.ts
}

smoke_mux_fresh_call_live() {
  # LIVE acceptance for entwurf_fresh_call — OUT of pnpm check, needs LIVE=1, spends two model
  # turns. The one axis no deterministic gate reaches: a real window, a real runtime, a real first
  # turn, and a real nonce callback whose SENDER ENVELOPE carries the new sibling's garden id.
  # Entwurf-owned write axes (XDG, all four meta roots, v2 locks, cwd) are fixture-bound; Pi also
  # gets fixture HOME so its control socket is isolated. Runtime-owned auth/config stays real and
  # native transcripts remain as evidence. Private tmux servers plus entry-set/GID residue checks
  # prove no fixture citizen lands in the operator's real record or control-socket directories.
  run_ts scripts/smoke-mux-fresh-call-live.ts
}

smoke_mux_lifecycle_live() {
  # RELEASE MUST integrated LIVE acceptance for the whole mux lifecycle, through the REAL MCP
  # surface. Needs LIVE=1; spends model turns on the operator's configured runtimes (two pi
  # siblings — native provider and recorded-ACP provider — each resumed once, plus one Claude
  # Code sibling). Enters via tools/call on the shipped bridge launcher and follows one citizen
  # around: fresh_call launch receipt -> nonce callback SENDER ENVELOPE -> entwurf_v2 control
  # send landing in the sibling's own transcript -> resume_call REFUSED while live (window count
  # unchanged) -> stable-handle close proving pane/socket gone with the record preserved ->
  # dormant delivery refused honestly -> public entwurf_resume_call with its LAUNCH and
  # OBSERVATION receipts kept apart, same-gid socket alive, no new citizen, no lock residue,
  # resumed pane_start_path == the RECORD's cwd (separate tmux query, never pane text), and the
  # transcript byte-identical across the resume itself -> entwurf_v2 recalling the fact from
  # BEFORE the close, which is what proves the same CONVERSATION returned. Claude Code runs the
  # callback+mailbox half and its resume is refused as target-not-pi with no window opened and no lock residue.
  # Fixture-fenced writes (XDG, four meta roots, v2 lock dir, control socket via fixture HOME);
  # the runtime auth roots stay REAL and sibling transcripts remain in the real pi agent dir as
  # evidence. Private tmux server per cell, bounded teardown, operator real-root entry sets
  # proven unchanged.
  run_ts scripts/smoke-mux-lifecycle-live.ts
}

check_mux_launch_tmux() {
  # REAL tmux acceptance for T1-a: drives production launchPi against a private fixture server
  # (unique -S socket, never the operator's) with TMUX/TMUX_PANE actually INHERITED. Proves the
  # window lands at {end} of the caller's own session, the pane process IS the runtime (no
  # shell wrapper), focus and the original panes survive, a precondition refusal opens NO
  # window, and the failed-exec trap is real. The runtime is a fixture stand-in, never the
  # operator's pi. Skips (97) without tmux or /proc. Operator-run: kept OUT of pnpm check.
  run_ts scripts/check-mux-launch-tmux.ts
}


smoke_acp_socket_citizen_live() {
  # S1 acceptance smoke (ACP plugin on v2) — OUT of pnpm check, needs LIVE=1.
  # Spawns a REAL `pi --entwurf-control` resident on an ACP model
  # (entwurf/claude-opus-5) and proves it is a first-class socket-citizen:
  # the control socket stands up, get_info answers with the ACP model (model-lock
  # did NOT revert — QM1), idle/cwd are reported, and the fail-loud streamSimple
  # stub never fires (turn-free launch — QM2). No prompt is sent: S1 proves
  # citizenship, never a backend turn (that is S2). Honest skip when LIVE!=1.
  # Model override: ENTWURF_S1_MODEL (default claude-opus-5).
  #   LIVE=1 ./run.sh smoke-acp-socket-citizen-live
  run_ts scripts/smoke-acp-socket-citizen-live.ts
}

smoke_acp_raw_turn_live() {
  # S2a-2 acceptance smoke (ACP plugin on v2) — OUT of pnpm check, needs LIVE=1.
  # Drives ONE real ACP turn through the pinned Claude adapter: spawns
  # claude-agent-acp from its resolved package bin, speaks ACP over stdio NDJSON
  # (ndJsonStream + the connectAcpClient adapter), runs initialize -> newSession ->
  # (sonnet) setSessionConfigOption(model) -> prompt("say OK"), and asserts a live "OK" reply
  # plus captured raw NDJSON bytes. NO provider/overlay/streamSimple/_meta — the
  # raw backend pipe only. Launch source must be the package bin (PATH fallback
  # fails acceptance unless ENTWURF_ACP_RAW_TURN_ALLOW_PATH_FALLBACK=1, debug).
  # Model override: ENTWURF_ACP_RAW_TURN_MODEL (default claude-sonnet-5).
  #   LIVE=1 ./run.sh smoke-acp-raw-turn-live
  run_ts scripts/smoke-acp-raw-turn-live.ts
}

smoke_acp_overlay_live() {
  # S2b acceptance smoke (ACP plugin on v2) — OUT of pnpm check, needs LIVE=1.
  # One layer above the S2a raw turn: materializes the Claude config overlay
  # (realDir = operator ~/.claude for live creds; overlay settings.json is ours,
  # hooks:{}), spawns claude-agent-acp with CLAUDE_CONFIG_DIR=<overlay> (verified
  # in the child's /proc/<pid>/environ), opens a session with a tool-narrowed
  # _meta.claudeCode.options (tools + disallowedTools) and NO _meta.systemPrompt
  # (billing carrier stays absent), then drives one live "OK" turn. NO
  # provider/streamSimple (backend-stub stays fail-loud — that is S2c); no
  # event-mapping/session-reuse/engraving (S2d). Does NOT diff the live
  # meta-store for mailbox absence (flaky — concurrent sessions); the honest
  # claim is overlay-supplies-hooks:{}. Launch must be the package bin (PATH
  # fallback fails acceptance unless ENTWURF_ACP_OVERLAY_ALLOW_PATH_FALLBACK=1).
  # Model override: ENTWURF_ACP_OVERLAY_MODEL (default claude-sonnet-5).
  #   LIVE=1 ./run.sh smoke-acp-overlay-live
  run_ts scripts/smoke-acp-overlay-live.ts
}

smoke_acp_memory_containment_live() {
  # Gate D — ACP Claude memory containment, end-to-end. OUT of pnpm check, LIVE=1.
  # THE regression guard that was missing: drives the SHIPPED config (overlay +
  # PRESENT engraving carrier = the v1 preset-replacement lever) with a turn that
  # EXPLICITLY asks the model to persist a nonce to its memory, then asserts NO
  # file appears under <overlay>/projects/**/memory/**. Permission is GRANTED (not
  # cancelled) and writeTextFile delegation is PERFORMED, so the only thing that
  # can stop a memory write is the lever — not us. Fails loud if engraving.md is
  # empty (carrier OFF = no containment). Launch must be the package bin (PATH
  # fallback fails acceptance unless ENTWURF_ACP_MEMORY_ALLOW_PATH_FALLBACK=1).
  # Model override: ENTWURF_ACP_MEMORY_MODEL (default claude-sonnet-5).
  #   LIVE=1 ./run.sh smoke-acp-memory-containment-live
  run_ts scripts/smoke-acp-memory-containment-live.ts
}

smoke_acp_long_turn_live() {
  # 0.13.1 LIVE acceptance for the prompt-lifecycle contract — OUT of pnpm check,
  # needs LIVE=1. Drives ONE real pi provider turn whose tool work (default
  # 3 x 240s foreground wait) deliberately outlasts the RETIRED 600s prompt cutoff, and
  # requires it to finish as ONE turn: the nonce arrives, elapsed > 600000ms, the
  # persisted transcript shows exactly ONE cold ACP bootstrap (no replay), and no
  # retry/timeout is reported anywhere. Takes >12 minutes by construction.
  # Overrides: ENTWURF_ACP_LONG_TURN_{MODEL,SLEEP_SECONDS,ROUNDS,HORIZON_MS}.
  #   LIVE=1 ./run.sh smoke-acp-long-turn-live
  run_ts scripts/smoke-acp-long-turn-live.ts
}

smoke_acp_provider_live() {
  # S2c acceptance smoke (ACP plugin on v2) — OUT of pnpm check, needs LIVE=1.
  # Drives the REAL pi PROVIDER path end to end: a real `pi` loads this
  # checkout's extension (--no-extensions -e REPO_ROOT), selects
  # entwurf/<model>, and pi's runner calls our streamSimple (backend.ts),
  # which spawns claude-agent-acp under the overlay, runs one turn, and maps the
  # result back through the S2c event mapper. Asserts a unique nonce in the
  # assistant reply (live model proof) + the removed S0 stub error never appears
  # (provider path actually opened) + pi exits 0. Tool-free prompt; the
  # event-mapper gate owns the tool→notice contract.
  # Model override: ENTWURF_ACP_PROVIDER_MODEL (default claude-sonnet-5).
  #   LIVE=1 ./run.sh smoke-acp-provider-live
  run_ts scripts/smoke-acp-provider-live.ts
}

smoke_acp_session_reuse_live() {
  # S2d-1b-2b acceptance smoke (in-memory session reuse) — OUT of pnpm check,
  # needs LIVE=1. Forces process-scoped (pushes --entwurf-control into argv) and
  # drives TWO real ACP turns over ONE reused claude-agent-acp child via the real
  # streamShellAcp: turn 1 introduces a codeword (full transcript), turn 2 sends
  # ONLY the latest user delta and must recall the codeword — proving the child
  # was reused and the live ACP session kept turn-1 history (a respawn-per-turn
  # backend would forget it). The one-shot exit0 half is owned by
  # smoke-acp-provider-live.
  # Model override: ENTWURF_ACP_PROVIDER_MODEL (default claude-sonnet-5).
  #   LIVE=1 ./run.sh smoke-acp-session-reuse-live
  run_ts scripts/smoke-acp-session-reuse-live.ts
}

smoke_acp_carrier_augment_live() {
  # S2e-1 acceptance smoke (billing carrier + first-user augment) — OUT of pnpm
  # check, needs LIVE=1. Writes a unique secret into the scratch cwd's AGENTS.md
  # (never the prompt) and drives one real provider turn: the reply must carry the
  # secret (the augment rode the wire to the model) and the EMPTY default carrier
  # must bill clean (exit 0, no HTTP-400 canary — 핀1 live). Optional tiny carrier
  # check via SMOKE_ACP_CARRIER_PRESENT=1 (non-blocking).
  # Model override: ENTWURF_ACP_PROVIDER_MODEL (default claude-sonnet-5).
  #   LIVE=1 ./run.sh smoke-acp-carrier-augment-live
  run_ts scripts/smoke-acp-carrier-augment-live.ts
}

smoke_acp_mcp_live() {
  # S2g LIVE 1 — operator MCP passthrough acceptance. OUT of pnpm check, needs
  # LIVE=1. Registers a TINY isolated probe MCP server (scripts/fixtures/
  # probe-mcp-server.ts, one tool probe_nonce) in a scratch .pi/settings.json and
  # drives one real provider turn: the model must CALL the tool and echo the nonce
  # that lives only inside the MCP server env. Proves the operator's
  # entwurfProvider.mcpServers reaches the live ACP session (the GLG-baseline
  # fix). Isolated probe (not entwurf-bridge) so a failure does not blur into
  # identity/env wiring. Model override: ENTWURF_ACP_PROVIDER_MODEL.
  #   LIVE=1 ./run.sh smoke-acp-mcp-live
  run_ts scripts/smoke-acp-mcp-live.ts
}

smoke_acp_skill_live() {
  # S2g LIVE 2 — operator skillPlugins passthrough acceptance. OUT of pnpm check,
  # needs LIVE=1. Builds a temp skill plugin (.claude-plugin/plugin.json +
  # skills/<name>/SKILL.md carrying a unique nonce instruction), points
  # entwurfProvider.skillPlugins at it, and drives one real provider turn: the
  # model must surface/use the skill and echo the nonce. Proves skillPlugins +
  # the Skill/Skill(*) auto-add reach the live session (the other half of the GLG
  # baseline). Model override: ENTWURF_ACP_PROVIDER_MODEL.
  #   LIVE=1 ./run.sh smoke-acp-skill-live
  run_ts scripts/smoke-acp-skill-live.ts
}

smoke_acp_bundled_mcp_live() {
  # S2g LIVE 3 (axis 3) — the BUNDLED entwurf-bridge reaches the live ACP session
  # via the 0.11.0 resident/RPC circuit. OUT of pnpm check, needs LIVE=1. Launches a
  # real `pi --entwurf-control --mode rpc` resident on an ACP model and drives ONE
  # model turn over the stdin RPC asking it to call mcp__entwurf-bridge__entwurf_self;
  # captures the identity envelope (the resident's own fresh gid — never told to the
  # model, only in the bridge env — + agentId + socketState alive) and agent_end
  # DIRECTLY from the stdout RPC event stream (resident-rpc-drive shape). Complements
  # smoke-acp-mcp-live (tiny isolated probe): this proves the REAL bundled bridge with
  # envelope injection.
  #
  # Why the resident/RPC circuit and not a `pi -p` one-shot: the resident IS the
  # long-lived socket-citizen circuit this release ships — a citizen that stays
  # addressable across turns. (This comment used to justify the choice by a
  # "bundled-MCP teardown hang" in one-shot mode; that claim was re-tested on
  # 2026-07-24 against pi 0.82.0 + claude-agent-acp 0.61.0 and did NOT reproduce
  # — one-shot exits 0, with and without a bundled tool call. The circuit, not a
  # hang, is the reason.) A one-shot run WITHOUT `--entwurf-control` is a
  # provider-surface run and has no garden identity by contract; see
  # docs/setup-clean-host.md Stage 6. Model override: ENTWURF_ACP_PROVIDER_MODEL.
  #   LIVE=1 ./run.sh smoke-acp-bundled-mcp-live
  run_ts scripts/smoke-acp-bundled-mcp-live.ts
}

smoke_acp_v2_send_live() {
  # S2g LIVE 4 (axis 4) — an ACP-backed model SENDS through entwurf_v2 and the message
  # lands in a peer's mailbox carrying the sender's real garden identity. OUT of pnpm
  # check, needs LIVE=1. Seeds an isolated world (store+mailbox+receivers under one temp
  # root) holding ONE armed self-fetch receiver, launches a real `pi --entwurf-control
  # --mode rpc` resident on an ACP model with that world in its env, and drives one turn
  # asking the model to call mcp__entwurf-bridge__entwurf_v2 at that exact target with a
  # nonce. Asserts ON DISK: exactly one `.msg`, doorbell poked, nonce intact, and the
  # rendered sender naming the RESIDENT's own gid + entwurf/<model> + replyable +
  # pi-session shape. The sender gid is never in the prompt.
  #
  # WHY it is not covered elsewhere: smoke-entwurf-v2-matrix-live dispatches
  # PROGRAMMATICALLY (no model in the loop) and smoke-acp-bundled-mcp-live is
  # RECEIVE-only (entwurf_self reads identity, writes no `.msg`). This is the SEND half
  # of "a Claude behind ACP is a garden citizen" — the half GLG hit as missing in real
  # use on 2026-07-24. MUST, not BEHAVIOR: the model is TOLD which tool to call, so a
  # failure here is a defect in OUR wiring, not a model preference — which is exactly
  # what its one measured failure turned out to be (see the MCP-readiness note in the
  # script header). It was briefly demoted on a misread of that sample and restored
  # once the transcripts were read. Model override: ENTWURF_ACP_PROVIDER_MODEL.
  #   LIVE=1 ./run.sh smoke-acp-v2-send-live
  run_ts scripts/smoke-acp-v2-send-live.ts
}

smoke_acp_rgg_live() {
  # S2e-2 — ACP-provider resident garden guard (RGG). Thin wrapper (GPT c32a6c8):
  # runs the SHARED resident-garden-guard runner against the entwurf provider
  # target with the DETERMINISTIC half only (SMOKE_RGG_POSITIVE=0). What this lane
  # treats as release-blocking is that resident CITIZEN discipline (#50 C2: record
  # birth, record-keyed socket, attach-on-reopen, no pi-session-id socket) holds
  # under the ACP provider too — the logic is provider-agnostic. The POSITIVE cell
  # (one real turn completing transcriptPath/model) is the only model-in-loop part.
  # Target override: ENTWURF_RGG_TARGET (default entwurf/claude-sonnet-5).
  #   ./run.sh smoke-acp-rgg-live
  local target="${ENTWURF_RGG_TARGET:-entwurf/claude-sonnet-5}"
  (cd "$REPO_DIR" && ENTWURF_LIVE_TARGET="$target" SMOKE_RGG_POSITIVE=0 bash scripts/smoke-resident-garden-guard.sh)
}

smoke_acp_cortex_live() {
  # On-demand LIVE smoke for the Cortex (Snowflake Cortex Code) ACP backend — the
  # first NON-claude adapter on the rail (docs/acp-backend-rail.md, Cortex audit). OUT of
  # `pnpm check` AND OUTSIDE the claude-only aggregate LIVE floor (capability
  # dignity, invariant #7): a host with no cortex install / no Snowflake auth must
  # not redden a release for a backend it does not run, so this is deliberately
  # absent from release-gate's 11-smoke ACP acceptance floor. That is a WIRING
  # decision, not a lower evidence bar — a cut that SHIPS cortex still owes a
  # deliberate run of this smoke, and the aggregate gate's silence is not a pass
  # (ACP rail Cortex verification boundary). Drives one real
  # cortex ACP turn through the entwurf provider path (outbound entwurf_v2 +
  # dual-HOME overlay facts + process-group reclaim — CP2).
  # HONEST-SKIP (protocol exit 97, never 0) when LIVE!=1 OR `cortex` is not on PATH OR no
  # connection is pinned — the live turn needs `cortex` installed with the
  # operator's own web-login auth already present (there is no `cortex auth`
  # subcommand — CP0 D6), reached through the overlay's narrow credential
  # symlinks — narrow in WHICH paths are reachable (D5), not read-only: a symlink
  # carries no write protection (AGENTS §ACP Plugin Boundary: entwurf never
  # provides/proxies the Snowflake credential). The connection must ride the adapter seam
  # (ENTWURF_ACP_CORTEX_CONNECTION) because the dual-HOME overlay denies the
  # operator settings.json where a default would live. PR #40 called this
  # `smoke-cortex`; the canonical family name is smoke-acp-cortex-live.
  #   LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> ./run.sh smoke-acp-cortex-live
  entwurf_require_step_outcome
  if [ "${LIVE:-}" != "1" ]; then
    echo "[entwurf:skip] smoke-acp-cortex-live — set LIVE=1 (+ ENTWURF_ACP_CORTEX_CONNECTION) to run."
    return "$ENTWURF_STEP_SKIP_EXIT"
  fi
  if ! command -v cortex >/dev/null 2>&1; then
    echo "[entwurf:skip] smoke-acp-cortex-live — cortex not on PATH (install Snowflake Cortex Code and complete its own login flow)."
    return "$ENTWURF_STEP_SKIP_EXIT"
  fi
  run_ts scripts/smoke-acp-cortex-live.ts
}

smoke_entwurf_v2_matrix_live() {
  # LIVE sentinel for 0.11 Stage 0 step 5d-5 (D4-b) — kept OUT of `pnpm check`. The deterministic
  # sibling (check-entwurf-v2-matrix) fixes every (target kind → transport → lock) cell over fakes
  # with ZERO IO; this drives the REAL production runEntwurfV2 deps against REAL OS objects on the
  # substrate happy path across 3 cells: C1 control-socket (a real `pi --entwurf-control` resident
  # → control-socket RPC send → lock acquire→release ×1), C2 meta-mailbox deliverable (armed
  # self-fetch citizen → real .msg enqueue, lock-free), C3 meta-mailbox guard (no armed receiver →
  # reject, no garbage). Model-in-loop is OUT (GPT Q2): "does the sender model call entwurf_v2"
  # is a separate behavior test — this is a transport/lock/enqueue gate. Negative/timeout/contention
  # stay deterministic. Honest skip when LIVE!=1 so the release-gate is runnable unattended.
  # Model: ENTWURF_LIVE_TARGET=<provider>/<model> (default openai-codex/gpt-5.6-luna).
  #   LIVE=1 ./run.sh smoke-entwurf-v2-matrix-live
  entwurf_require_step_outcome
  if [ "${LIVE:-}" != "1" ]; then
    echo "[entwurf:skip] smoke-entwurf-v2-matrix-live — set LIVE=1 to run (spawns a real pi --entwurf-control + opens a real socket)."
    return "$ENTWURF_STEP_SKIP_EXIT"
  fi
  run_ts scripts/smoke-entwurf-v2-matrix-live.ts
}

check_entwurf_facts() {
  # Deterministic gate for 0.11 Stage 0 step 4 (fact-provider slice 1): the PURE
  # fact core. Locks the PeerFact shape + R1/R3b liveness invariant before any IO
  # wiring (gate-first). R1: out-of-domain backend (claude-code/codex/antigravity)
  # → unsupported for EVERY socket input (never coerced to the socket value or
  # dead). R3b: in-domain pi → alive/dead/indeterminate, null → indeterminate
  # (no proof ≠ dead). facts-only keyset: identity facts + liveness, NO
  # verb-routing (resumable/sendable/transport/dispatch/action) and NO
  # transcriptPath (동결결정 10). Pure, no IO, no API.
  run_ts scripts/check-entwurf-facts.ts
}

check_control_socket_path() {
  # Deterministic gate: the control-socket path grammar `<dir>/<gid>.sock` has ONE
  # definition (pi-extensions/lib/control-socket-path.js) instead of one per
  # importer. Two duties: the leaf's own forward/inverse/round-trip behaviour
  # including the null case, and a re-implementation fence over all three adapters
  # (socket-discovery, entwurf-control, the MCP bridge) so a local ".sock" literal,
  # an inline join, an inline filename parse, or a dropped leaf import goes RED.
  run_ts scripts/check-control-socket-path.ts
}

check_socket_discovery() {
  # Deterministic gate for 0.11 Stage 0 step 4 (fact-provider slice 3): the
  # SOCKET-axis wiring scanSocketProbes. Probes the union of (dir sockets) ∪
  # (every in-domain pi citizen's canonical path) so a dormant citizen with no
  # socket file reads dead (ENOENT) → resumable, never an unprobed gap (slice 2
  # throws on that). Three-valued throughout — a stalled socket stays
  # indeterminate (F3), never folded to dead by an alive-only listing. Dir
  # hygiene (non-.sock / malformed names ignored), dedup, missing-dir, sort, and
  # an end-to-end scanSocketProbes→resolveFactList. readdir/probe injected, no IO.
  run_ts scripts/check-socket-discovery.ts
}

check_meta_listing() {
  # Deterministic gate for 0.11 Stage 0 step 4 (fact-provider slice 4a): the
  # meta-store axis listAllMetaIdentities. Explicit-partial: a parse failure or
  # body/filename drift does NOT blind the listing (valid records still surface)
  # and does NOT throw (0.10 "corrupt blocks registration forever" lesson) — it
  # becomes an explicit error carrying ONLY {filename, message}, verbatim (a
  # salvaged gid string as a fact = synthetic backdoor). mode strict throws on
  # any error, collect returns partial. entries/readRecord injected, no IO.
  run_ts scripts/check-meta-listing.ts
}

check_meta_facts() {
  # Deterministic gate for the #65 owner-normalized store projection. Drives the
  # REAL scripts/meta-facts.ts as a subprocess against sandboxed fixture stores:
  # full verbatim v3 records in the join, parse-before-uniqueness (a schema-invalid
  # rival never quarantines a healthy citizen), no-winner duplicates, drift /
  # symlink / invalid-UTF-8 defects in-band with exit 0, byte-deterministic JSON,
  # missing store = readable empty store, unreadable store = exit 3 with NO JSON,
  # usage = exit 2, plus dispatch + compiled-twin emit reachability.
  run_ts scripts/check-meta-facts.ts
}

check_entwurf_fact_provider() {
  # Deterministic gate for 0.11 Stage 0 step 4 (fact-provider slice 4b): the
  # ASSEMBLY layer listEntwurfFacts. listAllMetaIdentities → scanSocketProbes →
  # pre-quarantine out-of-socket-domain/socket conflicts → resolveFactList(clean) →
  # {facts, diagnostics}. Throw-vs-diagnostics policy (GPT힣 C-원칙): expected
  # corruption (parse failure / gardenId↔socket collision) → diagnostics, listing
  # survives; impossible wiring invariant (resolveFactList duplicate/unprobed) →
  # throw, never swallowed. A collision quarantines BOTH the PeerFact and the
  # socket (gid is the universal address). meta + socket deps injected, no IO.
  run_ts scripts/check-entwurf-fact-provider.ts
}

check_entwurf_peers_surface() {
  # Deterministic gate for 0.11 Stage 0 step 4 (fact-provider slice 4c; #50 C4
  # re-author): the MCP entwurf_peers RENDER/PAYLOAD layer renderEntwurfPeers.
  # Payload keyset is exactly {peers, diagnostics} — the legacy `sessions`
  # projection, socketOnly section, controlDir/count and every socketPath left
  # with the socket identity axis; FORBIDDEN_C4_KEYS + "no .sock in text" pin
  # that. A record-less socket surfaces ONLY as an aggregated record-less-socket
  # diagnostic (F8, liveness-keyed message). NO verb-routing field in JSON (deep
  # key scan) NOR word in text (title leak); diagnostics in both surfaces; empty
  # → "(none)"; unsupported shown. WIRING guard: both surfaces call
  # listEntwurfFacts+renderEntwurfPeers; getLiveSessions and the /entwurf-sessions
  # socket-scan command stay gone. Facts fabricated, no IO (only static source read).
  run_ts scripts/check-entwurf-peers-surface.ts
}


check_entwurf_self_address() {
  # Deterministic gate for the self-addressability honesty predicate (SE-1/SE-2
  # slice 1). Guards the bug where the MCP bridge / pi-native claim replyable:true
  # from env presence alone: a socketless pi session, or a meta citizen whose owner
  # exited / whose idle-watch was never armed, all advertised replyable while
  # delivery silently failed (SE-1). Asserts: PURE truth table (pi replyable ⟺
  # socketAlive; external never; meta BY RAIL — self-fetch ⟺ recordBacked ∧ ownerAlive ∧
  # watchArmed, native-push ⟺ recordBacked ∧ probeAlive, unsupplied rail fail-closed),
  # incl. the two regression-proof rows (record-present + owner-dead / watch-unarmed)
  # that stay meaningful after slice 3 mints records; SOURCE GUARD that
  # buildStrictPiSenderEnvelope drops the hardcoded `replyable: true` and existsSync-
  # probes the socket, and entwurf_self renders alive vs expected (no path lie).
  # Slice boundary: meta watchArmed is wired from the slice-2 presence marker; do NOT
  # claim slice 1 green standalone (1+2 close in the same release block).
  run_ts scripts/check-entwurf-self-address.ts
}

check_entwurf_deliverability() {
  # Deterministic gate for the conversational-mailbox deliverability predicate
  # (SE-1/SE-2 slice 2c). The predicate the enqueue sites must consult (slice 2d)
  # before writing a .msg. Asserts: computeMetaReceiverActive (active iff recordBacked
  # AND ownerAlive AND watchArmed, fail-closed, per-cause reasons); mailboxConversational-
  # Deliverable (deliverable iff wakeMode self-fetch AND active) — KEY rows: direct-inject
  # (pi) refused even when active (SE-1, no mailbox drain), self-fetch + dead-owner/unarmed
  # refused (SE-2, would rot); WIRING that the self-addressability predicate shares the
  # SAME active-receiver atom (one source of truth). Pure, no IO.
  run_ts scripts/check-entwurf-deliverability.ts
}

check_native_push_adapter() {
  # Deterministic gate for the native-push adapter LEAF (봉인 3/8). Drives
  # createAntigravityAdapter with a FAKE runner (no real agy/ss/pgrep). Asserts: FULL pid
  # scan (only the 2nd host pid serves the conv → probe still finds the route; raw-agy-send
  # head -1 corrected); dead (no host) vs indeterminate (host alive, no LS port served the
  # conv, never coerced to dead); VOLATILE route / no cache (a repeated probe re-discovers a
  # CHANGED route); send argv === [binary,agentapi,send-message,conv,body] with
  # ANTIGRAVITY_LS_ADDRESS env, non-zero exit THROWS; NO retry in the adapter (single send,
  # no re-probe — retry is the executor hand's job, step ⑥); resolveNativePushAdapter fail-fast.
  run_ts scripts/check-native-push-adapter.ts
}

check_native_push_register() {
  # Deterministic gate for 봉인 5: registerNativeConversation (the core of the
  # entwurf_register_native MCP tool). Drives it with a FAKE adapter + an ISOLATED mkdtemp
  # store (never the real ~/.pi). Asserts: live probe -> CREATE (record carries backend/
  # nativeSessionId/caller-cwd); re-register -> ATTACH (SAME garden id, cwd refreshed, ONE
  # record, no duplicate mint); dead/indeterminate probe -> REFUSE (throws, NO record written);
  # RECEIVER-MARKER ABSTINENCE (보정①) — the register source references no receiver-marker
  # writer (writeMetaReceiverMarker / armProvenance / META_RECEIVER_ARM_PROVENANCES).
  run_ts scripts/check-native-push-register.ts
}

check_agy_sender_identity() {
  # Deterministic gate for the #46 sender-identity lane — WHO is calling the bridge.
  # A birthed agy conversation could already CALL entwurf_v2 for real, yet its message
  # landed as external-mcp/unknown-host (non-replyable): the hook wrote only the
  # meta-record, and the bridge's resolver looked markers up under `claude-code` alone.
  # Behavioral, not source-regex: the real hook runs as a child process (so the marker's
  # ownerPid is the gate's own pid — the same parent-pid join production performs), and
  # the resolver runs against isolated marker/record stores.
  # Rows: hook writes an antigravity marker keyed by its PARENT pid; an upsert failure
  # writes NO marker (record authority first); resolver 0→null, 1→identity on EITHER
  # backend, no-record/drifted marker→null, two distinct live identities on one owner pid
  # →THROW (never guess, never downgrade to anonymous), two markers naming the SAME
  # identity→not a conflict; antigravity is native-push so its replyable comes from the
  # adapter probe, never from a mailbox watch it can never arm (보정①).
  run_ts scripts/check-agy-sender-identity.ts
}



check_package_source_routing() {
  # Deterministic gate for #29 (package-installed Entwurf ACP routing). Pins
  # resolveExplicitExtensionSpec()'s package-source -> install-root mapping and
  # the fail-fast routing contract through the two public routing surfaces
  # (getRegistryRouting spawn path, getEntwurfExplicitExtensions resume path).
  # Covers the install matrix: local path / git user / npm user (+version) /
  # install-missing / project-scope-unseen / no-source, across local + remote,
  # plus self-root fallback and the resume unresolvedAcpIntent signal. Isolated
  # via a temp PI_CODING_AGENT_DIR — the real ~/.pi/agent is never touched. No
  # backend, no spawn, no API cost.
  run_ts scripts/check-package-source-routing.ts
}


# smoke-session-id-name is GONE (#50 C3): it proved the pi --session-id/--name
# substrate entwurf used to stand on. C2 removed every entwurf use of that
# substrate (the record mints the address; pi owns id and name), so the smoke's
# subject no longer exists. The resident identity axis is covered by
# smoke-pi-attach (deterministic, in pnpm run check:full) + smoke-resident-garden-guard (LIVE).



check_dep_versions() {
  # Catches pi version-pin drift across package.json, run.sh, and the baseline
  # docs. Concretely the kind of skew that produced commit 21de0f9's "0.11.1
  # leftover" review comment: package.json bumped to 0.12.0 while README
  # and run.sh's setup gate still claimed 0.11.1. Static check, no
  # subprocess — fast enough to run inside `pnpm check`.
  # The doc half of that promise was prose only until 0.12.8 — see the
  # BASELINE DOCS block below, which finally makes this comment true.
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const geminiBundled = pkg.dependencies['@google/gemini-cli'] ?? pkg.optionalDependencies?.['@google/gemini-cli'];
assert.equal(geminiBundled, undefined, 'package.json must not bundle @google/gemini-cli — gemini is an external PATH runtime');

// `^` + `m` flag anchors to the start-of-line shell assignment so we don't
// accidentally pick up the regex literal inside this very check function's
// heredoc (which is indented, so won't match `^...`).
const runSh = readFileSync('run.sh', 'utf8');

// pi peer/dev alignment (#26 / 0.8.0 dep-alignment gate). The three
// @earendil-works/pi-* devDeps must pin one identical version, and that
// version must match the check-pack-install peer-install pins below
// (`pnpm add @earendil-works/pi-ai@X ...`). Without this, a pi bump could
// drift package.json devDeps away from the fresh-temp install smoke and
// the "dependency alignment gate" would not actually verify pi.
const piAi = pkg.devDependencies?.['@earendil-works/pi-ai'];
const piCoding = pkg.devDependencies?.['@earendil-works/pi-coding-agent'];
const piTui = pkg.devDependencies?.['@earendil-works/pi-tui'];
assert.ok(piAi, 'package.json devDependencies must pin @earendil-works/pi-ai');
assert.equal(piCoding, piAi,
  `@earendil-works/pi-coding-agent (${piCoding}) must match @earendil-works/pi-ai (${piAi})`);
assert.equal(piTui, piAi,
  `@earendil-works/pi-tui (${piTui}) must match @earendil-works/pi-ai (${piAi})`);

// check-pack-install peer-install pins (quoted `@earendil-works/pi-*@<ver>`
// args; the `\d`-anchored version avoids matching this regex literal itself).
const peerAi = runSh.match(/"@earendil-works\/pi-ai@(\d[\d.]*)"/)?.[1];
const peerCoding = runSh.match(/"@earendil-works\/pi-coding-agent@(\d[\d.]*)"/)?.[1];
const peerTui = runSh.match(/"@earendil-works\/pi-tui@(\d[\d.]*)"/)?.[1];
assert.equal(peerAi, piAi,
  `run.sh check-pack-install pi-ai peer pin (${peerAi}) must match package.json devDep (${piAi})`);
assert.equal(peerCoding, piAi,
  `run.sh check-pack-install pi-coding-agent peer pin (${peerCoding}) must match (${piAi})`);
assert.equal(peerTui, piAi,
  `run.sh check-pack-install pi-tui peer pin (${peerTui}) must match (${piAi})`);

// peerDependencies must be a CLOSED range (0.11 Stage 0, drift-proofing): the
// floor tracks the devDep pin so a consumer can't install against a pi lacking
// the public trust exports the bridge imports at the pinned minor, AND an upper
// bound at the next minor stops a fresh install from silently pulling a future
// pi (past the declared ceiling — 0.85+ at the current 0.84.4 pin) whose
// internal export surface has drifted from the one we typecheck against.
// pi moves its public surface every minor (the 0.79→0.80 getModels→provider-
// factory churn is exactly this), so an open `>=` floor is exactly how the next
// installer re-acquires the drift. The floor is also the HARD MINIMUM a consumer
// install resolves: at `>=0.84.4` an existing 0.84.3 host is upgraded, not kept.
// Expected shape: `>=<devDep> <0.<minor+1>` (e.g. `>=0.84.4 <0.85`).
const [piMaj, piMin] = piAi.split('.').map(Number);
assert.equal(piMaj, 0,
  `pi pin major must stay 0 for the next-minor ceiling rule (got ${piAi}); revisit check-dep-versions when pi reaches 1.x`);
const expectedPeer = `>=${piAi} <0.${piMin + 1}`;
const peerDepAi = pkg.peerDependencies?.['@earendil-works/pi-ai'];
const peerDepCoding = pkg.peerDependencies?.['@earendil-works/pi-coding-agent'];
const peerDepTui = pkg.peerDependencies?.['@earendil-works/pi-tui'];
assert.equal(peerDepAi, expectedPeer,
  `package.json peerDependencies @earendil-works/pi-ai (${peerDepAi}) must be "${expectedPeer}" (devDep floor + next-minor ceiling)`);
assert.equal(peerDepCoding, expectedPeer,
  `package.json peerDependencies @earendil-works/pi-coding-agent (${peerDepCoding}) must be "${expectedPeer}"`);
assert.equal(peerDepTui, expectedPeer,
  `package.json peerDependencies @earendil-works/pi-tui (${peerDepTui}) must be "${expectedPeer}"`);

// BASELINE DOCS (0.12.8). This gate was BORN reading a doc: 362becd added it
// after the 21de0f9 drift and asserted README.md's codex-acp install pin against
// package.json. bf4a533 then dropped the openclaw/ACP lane and took that
// assertion out with it — but left the coverage CLAIM standing in the usage line
// and the comment above. So the doc half of the promise has been prose ever
// since, and pi's baseline docs were never bound here at all. The 0.80.3→0.80.6
// bump touched FIVE such files, and a hand-grep — not a gate — is what kept
// demo/README.md from being left behind. A declaration no gate reads is exactly
// what this repair cut exists to delete, so the docs are back IN the gate.
// Scope is deliberately narrow: only sentences that DECLARE the pi pin. History
// (CHANGELOG/NEXT) keeps its old versions, and a pi mention without a version
// (an uninstall line, a type import) is not a declaration.
const BASELINE_DOCS = ['AGENTS.md', 'README.md', 'ROADMAP.md', 'docs/setup-clean-host.md', 'demo/README.md'];
let rangeDecls = 0, exactDecls = 0;
for (const file of BASELINE_DOCS) {
  const text = readFileSync(file, 'utf8');
  // Closed-range declarations: `>=<floor> <0.<ceiling>` (spaces optional).
  for (const [decl, floor, ceilMinor] of text.matchAll(/>=\s?(\d+\.\d+\.\d+)\s?<\s?0\.(\d+)/g)) {
    rangeDecls++;
    assert.equal(floor, piAi,
      `${file}: declared pi floor in "${decl}" is ${floor}, but the devDep pin is ${piAi} — a baseline doc may not advertise a version no gate drives`);
    assert.equal(Number(ceilMinor), piMin + 1,
      `${file}: declared pi ceiling in "${decl}" must be the next minor (0.${piMin + 1})`);
  }
  // Exact install pins: `@earendil-works/pi-<pkg>@<version>`.
  for (const [decl, ver] of text.matchAll(/@earendil-works\/pi-(?:ai|coding-agent|tui)@(\d+\.\d+\.\d+)/g)) {
    exactDecls++;
    assert.equal(ver, piAi, `${file}: install example "${decl}" pins ${ver}, but the devDep pin is ${piAi}`);
  }
}
// Prose declarations carry the pin in sentences the two patterns above cannot
// see. Each MUST still be found: a reworded baseline sentence has to fail loud
// here, never pass by matching nothing.
const PROSE_DECLS = [
  ['demo/README.md', /current floor (\d+\.\d+\.\d+)/, 'current floor <version>'],
  ['ROADMAP.md', /\bpi (\d+\.\d+\.\d+) fence\b/, 'pi <version> fence'],
  ['ROADMAP.md', /floor = \*\*(\d+\.\d+\.\d+)\*\*/, 'floor = **<version>**'],
  ['AGENTS.md', /devDep exact `(\d+\.\d+\.\d+)`/, 'devDep exact `<version>`'],
];
for (const [file, re, shape] of PROSE_DECLS) {
  const m = readFileSync(file, 'utf8').match(re);
  assert.ok(m, `${file}: the baseline sentence "${shape}" is gone — restore it or update check-dep-versions; a doc reword must not silently drop the pin from the gate`);
  assert.equal(m[1], piAi, `${file}: "${shape}" declares ${m[1]}, but the devDep pin is ${piAi}`);
}
// Guard the guard: if the patterns ever stop matching, the loops above pass
// vacuously and the docs fall back OUT of the gate without a word.
assert.ok(rangeDecls >= 5, `expected at least 5 pi range declarations across the baseline docs, found ${rangeDecls} — the doc scan matched (almost) nothing and would pass vacuously`);
assert.ok(exactDecls >= 1, `expected at least 1 exact pi install pin in the baseline docs, found ${exactDecls}`);

console.log(`[check-dep-versions] ok — pi ${piAi} is coherent across package.json (devDeps + peer range), run.sh (peer-install pins), and ${BASELINE_DOCS.length} baseline docs (${rangeDecls} range + ${exactDecls} exact + ${PROSE_DECLS.length} prose declarations)`);
EOF
  )
}

check_node_floor_coherence() {
  # #51 gate 3. The Node floor is declared across SIX contract surfaces
  # (package.json engines, run.sh setup preflight, meta-bridge install + doctor,
  # docs/setup-clean-host.md, mcp/entwurf-bridge/start.sh) plus the CI runner's
  # node-version, and TWO of those are live judgment logic (the installer `die`,
  # the doctor ok/bad branch), not prose. Before this gate they were bound to
  # nothing: the contract said one thing, CI exercised another, and the docs
  # advertised a dual "recommended / minimum" floor that no consumer image ever
  # ran. That is the same shape as check-dep-versions' regression — the
  # assertion was removed and the declaration survived, advertising a coverage
  # that had stopped existing.
  #
  # package.json engines.node is the SSOT; every other spelling is DERIVED and
  # compared against it. There must be exactly ONE number to move.
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const declared = pkg.engines?.node;
// The derived sites below compare MAJORS only (`-lt 24`, `>= 24`). A SSOT of
// `>=24.3.0` would therefore be unenforceable: installer and doctor would bless
// 24.0 while the contract demanded 24.3, and this gate would print green. The
// supported axis is a MAJOR lane, so pin the SSOT to a `.0.0` floor and reject
// anything finer rather than silently under-enforcing it. (Raising this to a
// minor floor means implementing a full semver compare at every derived site.)
assert.match(String(declared), /^>=\d+\.0\.0$/,
  `package.json engines.node must be a major-lane floor ">=<major>.0.0" — the derived sites compare majors only and cannot enforce a finer floor (got ${declared ?? 'nothing'})`);
const MAJOR = Number(String(declared).slice(2).split('.')[0]);

// The gate itself must not run BELOW the axis it certifies: a coherence green
// printed by an unsupported runtime is exactly the "declared ≠ verified" split
// this gate exists to close.
const runner = Number(process.versions.node.split('.')[0]);
assert.ok(runner >= MAJOR,
  `this gate is running on Node ${process.versions.node}, below the floor it certifies (${declared}) — a green from an unsupported runtime proves nothing`);

// Every site that must agree with the SSOT. `min` is the guard-the-guard: if a
// pattern ever stops matching, the site has drifted out of the gate and we fail
// loud instead of passing vacuously on zero matches.
const SITES = [
  ['run.sh', /process\.versions\.node\.split\("\."\)\[0\]\) >= (\d+)/g, 1, 'setup preflight logic'],
  ['run.sh', /entwurf requires Node >= (\d+)/g, 1, 'setup preflight message'],
  ['scripts/meta-bridge-install.sh', /NODE_MAJOR" -lt (\d+)/g, 1, 'installer die condition'],
  ['scripts/meta-bridge-install.sh', /entwurf requires Node >= (\d+)/g, 1, 'installer die message'],
  ['scripts/meta-bridge-doctor.sh', /MJ:-0}" -ge (\d+)/g, 1, 'doctor judgment logic'],
  ['scripts/meta-bridge-doctor.sh', /need >= (\d+)/g, 1, 'doctor bad message'],
  // Anchored to the Node ROW, not to any `>=x.y.z` in the file. The loose pattern
  // matched the Claude Code floor row the moment that table grew one (2026-07-22) and
  // read its major as the Node major. A site rule has to name its own site.
  ['docs/setup-clean-host.md', /\| Node \| \*\*`>=(\d+)\.\d+\.\d+`\*\*/g, 1, 'clean-host pin matrix'],
  ['mcp/entwurf-bridge/start.sh', /Node >= (\d+) \(engines\.node/g, 1, 'bridge launcher header'],
  ['.github/workflows/ci.yml', /node-version: (\d+)/g, 2, 'CI runner node-version'],
];

let bound = 0;
for (const [file, re, min, label] of SITES) {
  const text = readFileSync(file, 'utf8');
  const hits = [...text.matchAll(re)];
  assert.ok(hits.length >= min,
    `${file}: ${label} — pattern matched ${hits.length} time(s), expected >= ${min}. The declaration left the gate; re-bind it instead of deleting the assertion.`);
  for (const [decl, major] of hits) {
    assert.equal(Number(major), MAJOR,
      `${file}: ${label} declares Node major ${major} in "${decl.trim()}", but engines.node is ${declared}`);
  }
  bound += hits.length;
}

// Sweep the tracked first-party contract TEXT surfaces, NOT just the files
// already registered above. The first cut of this gate swept only SITES' own
// files and therefore could not see a declaration in an UNREGISTERED file —
// which is precisely how `mcp/entwurf-bridge/start.sh` kept advertising the old
// floor while the gate printed green (review lane, 2026-07-21). A sweep scoped
// to what is already bound is not a safety net; it is a restatement.
// pnpm-lock.yaml is excluded on purpose: those engine ranges belong to third-
// party dependencies and are not this repo's supported axis.
// `--cached` ONLY — deliberately not `--others`. The corpus must be the
// candidate contract (what is tracked/staged), never the operator's working
// directory: an un-ignored scratch file would otherwise turn this gate RED on
// one host and green on another, which is the read-coupling this cut exists to
// remove (rule 11 — a gate may not READ operator state any more than WRITE it).
// A genuinely new source file enters `--cached` the moment it is staged, i.e.
// before the commit that would ship it. (Review lane, 2026-07-21.)
const tracked = execFileSync('git', ['ls-files', '--cached', '--', '*.sh', '*.json', '*.ts', '*.md', '*.yml', '*.yaml'], { encoding: 'utf8' })
  .split('\n')
  .filter((f) => f && f !== 'pnpm-lock.yaml' && f !== 'CHANGELOG.md' && f !== 'NEXT.md');
assert.ok(tracked.length >= 20,
  `git ls-files returned ${tracked.length} first-party files — the sweep lost its corpus and would pass vacuously`);

// A floor declaration = the word node, then a comparison operator, then a
// two-digit major. Case-insensitive: the miss above was literally a capital N.
const FLOOR_DECL = /node[^0-9\n]{0,20}(?:>=|-lt|-ge|-gt)\s*(\d{2})/gi;
let swept = 0;
for (const file of tracked) {
  // `git ls-files --cached` still names an UNSTAGED deletion. That is a valid
  // release-surface migration before the commit workflow stages it, not an
  // unreadable candidate file. Skip ENOENT only; every other read failure crashes.
  let text;
  try { text = readFileSync(file, 'utf8'); }
  catch (error) {
    if (error?.code === 'ENOENT') continue;
    throw error;
  }
  for (const line of text.split('\n')) {
    if (line.includes('check_node_floor_coherence') || line.includes('FLOOR_DECL')) continue;
    for (const [decl, major] of line.matchAll(FLOOR_DECL)) {
      swept++;
      assert.equal(Number(major), MAJOR,
        `${file}: unregistered Node floor "${decl.trim()}" — expected major ${MAJOR}. Bind it in SITES or fix it.`);
    }
  }
}
assert.ok(swept >= 6,
  `sweep found only ${swept} node floor declarations across ${tracked.length} tracked files — the pattern rotted and would pass vacuously`);

// `bound` is the real declaration count; SITES.length is the number of RULES
// (the CI rule alone matches two node-version lines). Naming the rule count a
// declaration count would be this gate telling a small lie about its own reach.
console.log(`[check-node-floor-coherence] ok — Node >=${MAJOR} is coherent across engines.node, ${bound} bound declarations from ${SITES.length} site rules, and ${swept} declarations swept over ${tracked.length} tracked first-party contract text surfaces (single supported axis, no legacy lane). Non-text carriers (e.g. a Dockerfile \`FROM node:*\`) are OUTSIDE this pattern and must be bound by their own gate.`);
EOF
  )
}

check_claude_floor_coherence() {
  # #51 policy A. The Claude Code floor is a THREE-PART version, unlike the Node
  # floor's major lane: the discriminator lives in the patch position (2.1.138 drops
  # `args`, 2.1.139 introduces the exec form, 2.1.217 is the version actually proven
  # in a live session). So it cannot borrow check-node-floor-coherence's major-only
  # comparison and needs its own binding.
  #
  # package.json `entwurf.claudeCodeFloor` is the SSOT. The installer and the doctor
  # DERIVE it at runtime through scripts/meta-bridge-claude-floor.sh, so they carry no
  # literal to drift — that shared file is itself part of the contract and is asserted
  # below. What remains are the human-facing declarations (the launcher's refusal
  # message, docs, AGENTS) plus every fake `claude` CLI stub the gates spawn: a stub
  # that reports a version BELOW the floor would make the doctor legitimately refuse
  # its own fixture, so those are bound too — as `>=`, not equality, since a stub may
  # honestly claim a newer version.
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const declared = pkg.entwurf?.claudeCodeFloor;
assert.match(String(declared), /^>=\d+\.\d+\.\d+$/,
  `package.json entwurf.claudeCodeFloor must be a ">=X.Y.Z" spec (got ${declared ?? 'nothing'})`);
const FLOOR = String(declared).slice(2);
const cmp = (a, b) => {
  const x = a.split('.').map(Number), y = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] - y[i];
  return 0;
};

// The installer and doctor must DERIVE, never retype. If either grows a literal
// floor, the number stops being single and this gate has to say so.
const DERIVERS = ['scripts/meta-bridge-install.sh', 'scripts/meta-bridge-doctor.sh'];
for (const file of DERIVERS) {
  const text = readFileSync(file, 'utf8');
  assert.ok(text.includes('meta-bridge-claude-floor.sh'),
    `${file}: must source scripts/meta-bridge-claude-floor.sh — the floor is derived from package.json, never retyped`);
  assert.ok(text.includes('claude_floor_satisfied'),
    `${file}: sources the floor helper but never calls claude_floor_satisfied — a floor that is read and not enforced is decoration`);
  const stray = [...text.matchAll(/Claude Code >=\s*(\d+\.\d+\.\d+)/g)];
  for (const [decl, ver] of stray) {
    assert.equal(ver, FLOOR, `${file}: hardcodes "${decl.trim()}" but the SSOT floor is ${FLOOR}`);
  }
}

// Exact-equality declarations: prose and user-facing text that names the floor.
const SITES = [
  ['pi/meta-bridge/entwurf-meta-receive/scripts/hook-launch.sh', /Claude Code >= (\d+\.\d+\.\d+)/g, 1, 'launcher refusal message'],
  ['scripts/meta-bridge-claude-floor.sh', /THE FLOOR IS (\d+\.\d+\.\d+)/g, 1, 'floor helper rationale header'],
  ['docs/setup-clean-host.md', /`>=(\d+\.\d+\.\d+)`\*\* — the exec-form hook floor/g, 1, 'clean-host pin matrix'],
  ['AGENTS.md', /Claude Code `>=(\d+\.\d+\.\d+)`/g, 1, 'AGENTS rule 14'],
  ['README.md', /supported floor `>=(\d+\.\d+\.\d+)`/g, 1, 'README doctor description'],
  ['scripts/check-hook-launch-topology.ts', /\/(\d+)\\\.(\d+)\\\.(\d+)\//g, 1, 'topology gate floor assertion'],
];
let bound = 0;
for (const [file, re, min, label] of SITES) {
  const text = readFileSync(file, 'utf8');
  const hits = [...text.matchAll(re)];
  assert.ok(hits.length >= min,
    `${file}: ${label} — pattern matched ${hits.length} time(s), expected >= ${min}. The declaration left the gate; re-bind it instead of deleting the assertion.`);
  for (const hit of hits) {
    const ver = hit.length > 2 ? `${hit[1]}.${hit[2]}.${hit[3]}` : hit[1];
    assert.equal(ver, FLOOR, `${file}: ${label} declares ${ver} in "${hit[0].trim()}", but the SSOT floor is ${FLOOR}`);
  }
  bound += hits.length;
}

// Every fake `claude` CLI a gate spawns. These are not prose: the doctor reads them
// and judges the version, so a stub below the floor turns a healthy fixture RED for
// the wrong reason. Swept over tracked files rather than a registered list, because
// the miss this repo already paid for was a declaration in an UNREGISTERED file.
const tracked = execFileSync('git', ['ls-files', '--cached', '--', '*.sh', '*.ts'], { encoding: 'utf8' })
  .split('\n').filter(Boolean);
assert.ok(tracked.length >= 20, `git ls-files returned ${tracked.length} files — the sweep lost its corpus`);
const STUB = /echo\s+"(\d+\.\d+\.\d+) \(Claude Code\)"/g;
// `git ls-files --cached` still names an UNSTAGED deletion (same contract as the
// node-floor sweep): a valid release-surface migration before the commit workflow
// stages it. Skip ENOENT only; every other read failure crashes.
const readTracked = (file) => {
  try { return readFileSync(file, 'utf8'); }
  catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
};
let stubs = 0;
for (const file of tracked) {
  const text = readTracked(file);
  if (text === null) continue;
  for (const [decl, ver] of text.matchAll(STUB)) {
    stubs++;
    assert.ok(cmp(ver, FLOOR) >= 0,
      `${file}: fake claude CLI reports ${ver} in "${decl.trim()}", BELOW the floor ${FLOOR} — the doctor would refuse this fixture for the version, not for what the fixture is testing`);
  }
}
assert.ok(stubs >= 4,
  `sweep found only ${stubs} fake claude version stubs — the pattern rotted and would pass vacuously`);

// The sweep above can only judge stubs that ANSWER `--version`. A fake `claude` with
// no version arm at all is invisible to it — and that is not hypothetical: adding the
// installer's floor check turned three such stubs into silent installer deaths on the
// first full run (2026-07-22), caught by the smoke rather than by this gate. A gate
// that binds only the declarations that exist is the same "sweep what is already
// bound" mistake check-node-floor-coherence had to fix. So: if a file MINTS a fake
// claude, that stub must be able to say who it is.
const MINT = /(?:cat|tee)\s*>+\s*"?\$?\{?\w+\}?\/claude"?\s*<<-?\s*'?(\w+)'?/g;
let stubsMinted = 0;
for (const file of tracked) {
  const text = readTracked(file);
  if (text === null) continue;
  for (const m of text.matchAll(MINT)) {
    stubsMinted++;
    const body = text.slice(m.index + m[0].length);
    const end = body.search(new RegExp(`^\\s*${m[1]}\\s*$`, 'm'));
    const stub = end >= 0 ? body.slice(0, end) : body;
    assert.ok(stub.includes('--version'),
      `${file}: a fake \`claude\` stub is minted here with no \`--version\` arm. The installer and doctor read the version to enforce the floor, so this stub makes them die (or pass) for a reason that has nothing to do with what the fixture is testing.`);
  }
}
assert.ok(stubsMinted >= 4,
  `sweep found only ${stubsMinted} fake claude stub definitions — the mint pattern rotted and would pass vacuously`);

// PROSE SWEEP over the tracked contract text, not just SITES' own files. Binding only
// the declarations someone remembered to register is the "sweep what is already bound"
// restatement check-node-floor-coherence had to fix, and this gate shipped with the same
// shape: measured 2026-07-22, THREE floor declarations (DELIVERY.md x2, the clean-host
// upgrade note) sat outside SITES, so moving the floor would have left them advertising
// the old number while this gate printed green.
//
// Scope is deliberately narrow: only a COMPARISON (`>=`) next to the word Claude is a
// floor declaration. A bare "Claude Code 2.1.217 actual session" in VERIFY/BASELINE is an
// OBSERVATION — the version some evidence was taken at — and must not be rewritten when
// the floor moves. CHANGELOG.md and NEXT.md are excluded for the same reason
// check-node-floor-coherence excludes them: they are history, and history keeps the number
// it was written with.
const proseCorpus = execFileSync('git', ['ls-files', '--cached', '--', '*.sh', '*.json', '*.ts', '*.md', '*.yml', '*.yaml'], { encoding: 'utf8' })
  .split('\n')
  .filter((f) => f && f !== 'pnpm-lock.yaml' && f !== 'CHANGELOG.md' && f !== 'NEXT.md');
assert.ok(proseCorpus.length >= 20,
  `git ls-files returned ${proseCorpus.length} first-party files — the prose sweep lost its corpus and would pass vacuously`);
const FLOOR_DECL = /[Cc]laude[^0-9\n]{0,24}>=\s*(\d+\.\d+\.\d+)/g;
let sweptProse = 0;
for (const file of proseCorpus) {
  // As above, an unstaged deletion remains in `git ls-files --cached` until the
  // commit workflow stages it. Skip only that ENOENT transition; do not hide any
  // other read failure.
  let text;
  try { text = readFileSync(file, 'utf8'); }
  catch (error) {
    if (error?.code === 'ENOENT') continue;
    throw error;
  }
  for (const line of text.split('\n')) {
    if (line.includes('check_claude_floor_coherence') || line.includes('FLOOR_DECL')) continue;
    for (const [decl, ver] of line.matchAll(FLOOR_DECL)) {
      sweptProse++;
      assert.equal(ver, FLOOR,
        `${file}: unregistered Claude Code floor declaration "${decl.trim()}" — the SSOT floor is ${FLOOR}. Bind it in SITES or fix it.`);
    }
  }
}
assert.ok(sweptProse >= 8,
  `prose sweep found only ${sweptProse} Claude floor declarations across ${proseCorpus.length} tracked files — the pattern rotted and would pass vacuously`);

console.log(`[check-claude-floor-coherence] ok — Claude Code >=${FLOOR} is coherent across package.json (SSOT), ${DERIVERS.length} runtime derivers that never retype it, ${bound} bound declarations from ${SITES.length} site rules, ${stubs} fake-CLI version declarations (>= floor, since a stub may honestly claim newer), ${stubsMinted} minted fake-claude stubs each able to answer --version, and ${sweptProse} floor declarations swept over ${proseCorpus.length} tracked contract text surfaces (observations without a comparison operator are OUT of scope; CHANGELOG/NEXT keep their history).`);
EOF
  )

  # The shared detector is called from a bare assignment under `set -euo pipefail`.
  # A failed or unparseable probe must therefore return success-with-empty so each
  # caller reaches its own explicit NOT CERTIFIED / install-refusal diagnosis instead
  # of dying at the assignment. The long-writer cell reproduces the old early-reader
  # SIGPIPE class with 128 KiB before the version line; the parser must consume it all.
  local probe_tmp
  probe_tmp="$(mktemp -d -t entwurf-claude-floor.XXXXXX)"
  cat > "$probe_tmp/claude" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] || exit 2
case "${FAKE_CLAUDE_VERSION_MODE:-ok}" in
  ok)          printf '%s\n' 'diagnostic prelude' '2.1.217 (Claude Code)' ;;
  unparseable) printf '%s\n' 'Claude Code version unknown' ;;
  nonzero)     printf '%s\n' '2.1.217 (failed probe)'; exit 7 ;;
  longwriter)  python3 - <<'PY'
import sys
sys.stdout.write("x" * (128 * 1024) + "\n2.1.217 (Claude Code)\n")
PY
    ;;
esac
SH
  chmod +x "$probe_tmp/claude"
  for mode in ok longwriter; do
    FAKE_CLAUDE_VERSION_MODE="$mode" PATH="$probe_tmp:$PATH" bash -c '
      set -euo pipefail
      source "$1"
      [ "$(claude_detected_version)" = 2.1.217 ]
    ' _ "$REPO_DIR/scripts/meta-bridge-claude-floor.sh"
  done
  for mode in unparseable nonzero; do
    FAKE_CLAUDE_VERSION_MODE="$mode" PATH="$probe_tmp:$PATH" bash -c '
      set -euo pipefail
      source "$1"
      [ -z "$(claude_detected_version)" ]
    ' _ "$REPO_DIR/scripts/meta-bridge-claude-floor.sh"
  done
  ok "[check-claude-floor-coherence] detector returns the intended value for normal, nonzero, unparseable, and 128-KiB long-writer probes"

  # Do not stop at helper behavior: prove both production callers reach THEIR OWN
  # diagnostic branches. Every writable/readable root is sandboxed; these probes stop
  # before an installer side effect and let the doctor finish its normal FAIL summary.
  local probe_home="$probe_tmp/home" install_out doctor_out
  mkdir -p "$probe_home" "$probe_tmp/xdg-data" "$probe_tmp/xdg-state" "$probe_tmp/xdg-cache" "$probe_tmp/agent"
  if install_out="$(env \
      HOME="$probe_home" XDG_DATA_HOME="$probe_tmp/xdg-data" XDG_STATE_HOME="$probe_tmp/xdg-state" XDG_CACHE_HOME="$probe_tmp/xdg-cache" \
      PI_CODING_AGENT_DIR="$probe_tmp/agent" CLAUDE_CONFIG_DIR="$probe_home/.claude" \
      FAKE_CLAUDE_VERSION_MODE=unparseable PATH="$probe_tmp:$PATH" \
      bash "$REPO_DIR/scripts/meta-bridge-install.sh" 2>&1)"; then
    echo "[check-claude-floor-coherence] FAIL: installer accepted an unparseable Claude version" >&2
    rm -rf "$probe_tmp"
    return 1
  fi
  case "$install_out" in
    *"meta-bridge-install: could not read a version from 'claude --version'"*) ;;
    *) echo "[check-claude-floor-coherence] FAIL: installer died before its own unidentifiable-version diagnosis: $install_out" >&2; rm -rf "$probe_tmp"; return 1 ;;
  esac
  ok "[check-claude-floor-coherence] installer reaches its own unidentifiable-version refusal branch"

  if doctor_out="$(env \
      HOME="$probe_home" XDG_DATA_HOME="$probe_tmp/xdg-data" XDG_STATE_HOME="$probe_tmp/xdg-state" XDG_CACHE_HOME="$probe_tmp/xdg-cache" \
      PI_CODING_AGENT_DIR="$probe_tmp/agent" CLAUDE_CONFIG_DIR="$probe_home/.claude" \
      FAKE_CLAUDE_VERSION_MODE=nonzero PATH="$probe_tmp:$PATH" \
      bash "$REPO_DIR/scripts/meta-bridge-doctor.sh" 2>&1)"; then
    echo "[check-claude-floor-coherence] FAIL: doctor certified a failed Claude version probe" >&2
    rm -rf "$probe_tmp"
    return 1
  fi
  case "$doctor_out" in
    *"could not read a version from 'claude --version' — NOT CERTIFIED"*"meta-bridge doctor: FAIL"*) ;;
    *) echo "[check-claude-floor-coherence] FAIL: doctor did not reach its own NOT CERTIFIED branch and final FAIL summary: $doctor_out" >&2; rm -rf "$probe_tmp"; return 1 ;;
  esac
  ok "[check-claude-floor-coherence] doctor reaches its own NOT CERTIFIED branch and final FAIL summary"
  rm -rf "$probe_tmp"
}

check_pi_import_surface() {
  # 0.11 Stage 0 (동결결정 9): the bridge may reference @earendil-works/pi-*
  # ONLY by the package root. ANY subpath (`/dist`, `/core`, `/src`, `/foo`, …)
  # reaches pi's private surface and silently breaks on pi internal reshuffles.
  # The check is intentionally SPECIFIER-shaped, not import-keyword-shaped: it
  # matches a quoted/backtick module specifier `@earendil-works/pi-*/…`, so one
  # pattern catches static `from`, dynamic `import()`, `require()`,
  # `export … from`, side-effect `import "…"`, and whitespace variants alike.
  # Root import `@earendil-works/pi-coding-agent` (no trailing slash) is allowed.
  # Scans the whole git WORK SURFACE (tracked + untracked-non-ignored), not a
  # hardcoded or index-only file list. The index-only corpus was the #62 measured
  # escape: a brand-new test file carrying a forbidden subpath was invisible to the
  # floor until it happened to be staged, so the gate went green on a candidate CI
  # then rejected. The denominator is re-proved every run against an EXTERNAL
  # throwaway git repo (never this worktree — the frozen candidate must not be
  # written to) holding one tracked-clean and one untracked-forbidden fixture.
  #
  # pi 0.80 EXCEPTION — exactly ONE allowlisted subpath:
  #   @earendil-works/pi-ai/compat
  # 0.80 moved the standalone root `getModels()` to the deprecated `/compat`
  # entrypoint. This repo's pi-extensions/** are loaded by pi's EXTENSION loader
  # (pi-coding-agent `core/extensions/loader.ts`), whose jiti alias map resolves
  # FOUR pi-ai specifiers for extensions — the bare root, `/compat`, `/oauth`, and
  # (since pi 0.81) `/providers/all`. Other `providers/*` subpaths are NOT in that
  # map: jiti prefix-matches the bare `@earendil-works/pi-ai` alias and appends
  # the remainder, producing the unresolvable `…/dist/compat.js/providers/
  # anthropic` (verified live: extension load crash — invisible to static
  # typecheck, which resolves against node_modules `exports`). So `/compat` is the
  # sanctioned extension entrypoint, and the ONLY allowlisted exception. It has TWO
  # consumers: lib/acp/models.ts (`getModels`, the old global model-catalog API) and
  # test/fresh-call-provider.contract.test.ts (`stream`, the loopback provider-conversion
  # contract — pi-ai 0.84's package ROOT exports no stream/streamAnthropic at all, and
  # root `lazyStream(model, setup)` only defers the same private import into `setup`,
  # so /compat is the only surface that can observe the real anthropic request body). The
  # allow-pattern is closing-quote-anchored (`@earendil-works/pi-ai/compat["'\`]`)
  # so it permits ONLY that exact specifier: `/compat-foo`, `/oauth`, every
  # `/providers/*`, and any deeper path stay FORBIDDEN (we use only `/compat`).
  # Do NOT widen this to a `providers/*` subpath — it typechecks but CANNOT
  # resolve under the extension loader.
  # ONE corpus, TWO callers. The real scan and the denominator fixture must run the
  # SAME two lines, or the fixture would prove a command the gate does not use.
  pi_import_work_surface() {
    git ls-files -z --cached --others --exclude-standard -- '*.ts' '*.js' '*.mjs' '*.cjs'
  }
  pi_import_scan() {
    pi_import_work_surface \
      | xargs -0r grep -HnE "[\"'\`]@earendil-works/pi-(ai|coding-agent|tui)/" 2>/dev/null \
      | grep -vE "[\"'\`]@earendil-works/pi-ai/compat[\"'\`]" 2>/dev/null || true
  }

  local probe_dir probe_hits hits
  probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/entwurf-pi-import-denominator.XXXXXX")
  (
    cd "$probe_dir" || exit 1
    git -c init.defaultBranch=main init -q .
    printf '%s\n' 'import { getModels } from "@earendil-works/pi-ai/compat";' > tracked-allowed.ts
    git add tracked-allowed.ts
    printf '%s\n' 'import "@earendil-works/pi-ai/private-probe";' > untracked-forbidden.ts
  ) || { fail "[check-pi-import-surface] could not build the denominator fixture in $probe_dir"; rm -rf "$probe_dir"; return 1; }
  probe_hits=$(cd "$probe_dir" && pi_import_scan)
  rm -rf "$probe_dir"
  # ONE assertion, ONE claim token: the manifest contract requires the signature to
  # occur exactly once in this file, so both fixture conditions are folded into a
  # single failure whose message still names which half broke.
  local saw_untracked_forbidden="no" saw_tracked_allowed="no"
  grep -qF 'untracked-forbidden.ts' <<<"$probe_hits" && saw_untracked_forbidden="yes"
  grep -qF 'tracked-allowed.ts' <<<"$probe_hits" && saw_tracked_allowed="yes"
  if [ "$saw_untracked_forbidden" != "yes" ] || [ "$saw_tracked_allowed" != "no" ]; then
    fail "[QK:PIIMPORT-WORK-SURFACE] the denominator fixture disagrees with the corpus — untracked-forbidden reached=$saw_untracked_forbidden (want yes: a brand-new forbidden import must not escape until it is staged), tracked-allowed flagged=$saw_tracked_allowed (want no: the /compat exception must survive)"
    return 1
  fi

  hits=$(cd "$REPO_DIR" && pi_import_scan)
  if [ -n "$hits" ]; then
    echo "[check-pi-import-surface] FAIL: pi private subpath reference(s) — import @earendil-works/pi-* by the package ROOT only:"
    echo "$hits"
    exit 1
  fi
  ok "[check-pi-import-surface] pi references are root/compat-only across tracked + untracked-non-ignored ts/js; the untracked denominator is proved on an external fixture repo"
}

check_env_namespace() {
  # 0.11 S3 cutover lock: after the env-namespace rename, NO tracked source may
  # carry the old pi-centric env/const prefixes (PI_SHELL_ACP*, PI_META*,
  # PI_TOOLS_BRIDGE*, PI_ENTWURF*). This deterministic guard keeps the cutover
  # from silently regressing — a single old prefix slipping back in fails loud.
  # KEEP pi-adapter env (PI_SESSION_ID, PI_AGENT_ID, PI_CODING_AGENT_DIR,
  # PI_SETTINGS_PATH, PI_EMACS_AGENT_SOCKET) is NOT in the forbidden set, so it
  # passes untouched. The forbidden pattern uses a [_] char-class for the
  # trailing underscore so THIS gate's own definition never self-matches; for
  # the same reason every prose mention above uses a `*`, not a trailing `_`.
  # Docs/CHANGELOG/NEXT keep historical mentions and are excluded.
  local hits
  hits=$(cd "$REPO_DIR" && git ls-files \
    | grep -vE '\.(md|org)$|(^|/)NEXT|(^|/)CHANGELOG|^docs/' \
    | xargs -r grep -HnE 'PI_SHELL_ACP[_]|PI_META[_]|PI_TOOLS_BRIDGE[_]|PI_ENTWURF[_]' 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "[check-env-namespace] FAIL: old pi env/const prefix survived the S3 cutover — rename to ENTWURF_*/ENTWURF_ACP_*/ENTWURF_META_*/ENTWURF_BRIDGE_*:"
    echo "$hits"
    exit 1
  fi
  ok "[check-env-namespace] env namespace is entwurf-only (no old pi env/const prefix in tracked source)"
}

check_pi_runtime_version() {
  # 0.11 Stage 0 (동결결정 9, runtime half): tsc catches a missing 0.80 export
  # at dev time, but an installed environment can still resolve a pi OUTSIDE the
  # supported range at runtime — older, where the named trust exports / 0.80
  # provider-factory surface do not exist; or newer, where they have moved again.
  # Verify VERSION against the DECLARED CLOSED RANGE (both ends, see below) via a
  # DYNAMIC import of the package root only — never statically import a
  # range-only symbol here, or this guard would crash before it can fail loud.
  #
  # The floor is DERIVED from the package.json devDep pin, never a second literal.
  # A hand-kept `const FLOOR = '<version>'` is a declaration no gate enforces:
  # check-dep-versions binds the devDeps, the peer range, and the check-pack-install
  # peer pins to one another, but it never saw this constant — so a pi bump that
  # forgot it would leave the runtime gate still blessing the OLD floor, silently.
  # That is the same "declared runtime ≠ verified runtime" split the 0.12.8
  # check-pack-install fix closed; there must be exactly ONE pin to move.
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { readFileSync } from 'node:fs';

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const FLOOR = pkg.devDependencies?.['@earendil-works/pi-coding-agent'];
if (typeof FLOOR !== 'string' || !/^\d+\.\d+\.\d+$/.test(FLOOR)) {
  console.error(`[check-pi-runtime-version] FAIL: package.json devDependencies['@earendil-works/pi-coding-agent'] must be an EXACT x.y.z pin to serve as the runtime floor (got ${FLOOR ?? 'nothing'})`);
  process.exit(1);
}
// The declared contract is a CLOSED range (`>=<devDep> <0.<minor+1>`, enforced on
// package.json by check-dep-versions), so the runtime check must be closed too.
// A floor-only comparison would bless a resolved pi ABOVE the ceiling — and an
// out-of-range pi is exactly the drift this cut exists to stop: 0.80.6 landed on
// the dev box while the repo still declared 0.80.3, and every gate stayed green.
// Verifying only half of a declared range is the same lie in the other direction.
const CEILING = `0.${Number(FLOOR.split('.')[1]) + 1}.0`;
const cmp = (a, b) => {
  const pa = a.split('.').map(Number), pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) { if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0); }
  return 0;
};
let VERSION;
try {
  ({ VERSION } = await import('@earendil-works/pi-coding-agent'));
} catch (e) {
  console.error(`[check-pi-runtime-version] FAIL: cannot import @earendil-works/pi-coding-agent root — ${e?.message ?? e}`);
  process.exit(1);
}
if (typeof VERSION !== 'string') {
  console.error('[check-pi-runtime-version] FAIL: pi root export VERSION is not a string');
  process.exit(1);
}
if (cmp(VERSION, FLOOR) < 0) {
  console.error(`[check-pi-runtime-version] FAIL: pi VERSION ${VERSION} < ${FLOOR} — the bridge is built and tested against the ${FLOOR} public/runtime surface (trust exports hasTrustRequiringProjectResources + ProjectTrustStore nearest-ancestor get, the 0.80 model-catalog API getModels reached via the deprecated /compat entrypoint — 0.80 moved the standalone root getModels there, and the extension loader resolves only /compat, NOT the providers/* factory subpath — provider registration surface, compaction semantics) that older pi lacks or behaves differently on. Bump @earendil-works/pi-*.`);
  process.exit(1);
}
if (cmp(VERSION, CEILING) >= 0) {
  console.error(`[check-pi-runtime-version] FAIL: pi VERSION ${VERSION} >= ${CEILING} — OUTSIDE the declared range (>=${FLOOR} <${CEILING.slice(0, -2)}). pi moves its public surface every minor (the 0.79→0.80 getModels→/compat churn), so a next-minor runtime is unverified by definition: no gate here has driven it. Either pin the repo to that pi (devDeps + peer range + baseline docs move together) or install the declared one.`);
  process.exit(1);
}
console.log(`[check-pi-runtime-version] ok — pi VERSION ${VERSION} within the declared range (>=${FLOOR} <${CEILING.slice(0, -2)})`);
EOF
  )
}

check_install_preflight() {
  # 0.12 relocation guard (2026-06-23): `install` MUST fail loud on a repo whose
  # node_modules is missing (fresh clone, no pnpm install) or path-stale (a dir
  # move/rename broke the pnpm symlink store) — and it must fail BEFORE writing
  # settings.json, so the breakage is not a silent-red that only surfaces minutes
  # later as a dead MCP bridge (entwurf-bridge ✘ Failed to connect) + a
  # check-entwurf-v2-surface ERR_MODULE_NOT_FOUND. The preflight follows each
  # dep's symlink to its real package.json (immune to per-package "exports" maps
  # that forbid a bare-root or ./package.json import), which a bare
  # `test -d node_modules` cannot do for a dir-move. REPO_DIR is the dir holding
  # run.sh (line 16), so the negative cases copy run.sh into a temp dir to point
  # REPO_DIR at a deliberately-broken tree.
  local rc out proj fake dep

  # positive — the live repo passes the REAL preflight. Calling it directly keeps
  # preflight_dep_integrity the single source of truth for the probe set (no
  # second hardcoded list to drift). Subshell so its exit-on-fail can't kill us.
  if ! ( preflight_dep_integrity ) >/dev/null 2>&1; then
    fail "[check-install-preflight] live repo fails preflight_dep_integrity — run 'pnpm install' (gate cannot validate against a broken repo)"
    exit 1
  fi
  ok "[check-install-preflight] live repo passes preflight (all runtime hard deps resolve)"

  # negative 1 — missing node_modules (fresh clone)
  fake=$(mktemp -d); proj=$(mktemp -d)
  cp "$REPO_DIR/run.sh" "$fake/run.sh"
  rc=0; out=$("$fake/run.sh" install "$proj" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "[check-install-preflight] missing node_modules did NOT fail install"; rm -rf "$fake" "$proj"; exit 1
  fi
  if [ -f "$proj/.pi/settings.json" ]; then
    fail "[check-install-preflight] install wrote settings.json with missing deps (SILENT-RED)"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  if ! printf '%s' "$out" | grep -q "repo dependency integrity check failed"; then
    fail "[check-install-preflight] missing node_modules failed for the WRONG reason:"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  rm -rf "$fake" "$proj"
  ok "[check-install-preflight] missing node_modules → fails before writing settings"

  # negative 2 — representative dangling symlink (dir move): node_modules/ EXISTS
  # (a bare `test -d` would pass) with the other runtime deps symlinked live, but a
  # representative dep (@anthropic-ai/sdk) dangles. Asserts the dir-move blind spot
  # is closed AND that the failure names the broken dep. Uses a BUNDLED runtime dep
  # because the @earendil-works/pi-* peer trio is loader-provided and no longer part
  # of the install preflight probe set.
  fake=$(mktemp -d); proj=$(mktemp -d)
  cp "$REPO_DIR/run.sh" "$fake/run.sh"
  mkdir -p "$fake/node_modules/@modelcontextprotocol" "$fake/node_modules/@agentclientprotocol" "$fake/node_modules/@anthropic-ai"
  ln -s "$REPO_DIR/node_modules/@modelcontextprotocol/sdk" "$fake/node_modules/@modelcontextprotocol/sdk"
  ln -s "$REPO_DIR/node_modules/@agentclientprotocol/sdk" "$fake/node_modules/@agentclientprotocol/sdk"
  ln -s "$REPO_DIR/node_modules/@agentclientprotocol/claude-agent-acp" "$fake/node_modules/@agentclientprotocol/claude-agent-acp"
  ln -s "$REPO_DIR/node_modules/zod" "$fake/node_modules/zod"
  ln -s /nonexistent/pnpm-store/anthropic-sdk "$fake/node_modules/@anthropic-ai/sdk"
  rc=0; out=$("$fake/run.sh" install "$proj" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "[check-install-preflight] dangling dep symlink did NOT fail install (test -d blind spot)"; rm -rf "$fake" "$proj"; exit 1
  fi
  if [ -f "$proj/.pi/settings.json" ]; then
    fail "[check-install-preflight] install wrote settings.json with a dangling dep (SILENT-RED)"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  if ! printf '%s' "$out" | grep -q "repo dependency integrity check failed"; then
    fail "[check-install-preflight] dangling symlink failed for the WRONG reason:"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  if ! printf '%s' "$out" | grep -q "@anthropic-ai/sdk"; then
    fail "[check-install-preflight] dangling case did not name the broken dep (@anthropic-ai/sdk):"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  rm -rf "$fake" "$proj"
  ok "[check-install-preflight] representative dangling symlink (test -d blind spot) → fails before writing settings, names the dep"

  # negative 3 — corrupt project provider shape. install_local_package now has a
  # two-step writer (packages[] SSOT, then entwurfProvider.mcpServers), so a
  # malformed provider MUST fail before the packages[] step writes anything.
  fake=$(mktemp -d); proj=$(mktemp -d)
  mkdir -p "$proj/.pi" "$fake/home"
  printf '{"entwurfProvider": []}\n' > "$proj/.pi/settings.json"
  local before after
  before=$(sha256sum "$proj/.pi/settings.json" | cut -d' ' -f1)
  rc=0; out=$(HOME="$fake/home" PI_CODING_AGENT_DIR="$fake/home/.pi/agent" "$REPO_DIR/run.sh" install "$proj" 2>&1) || rc=$?
  after=$(sha256sum "$proj/.pi/settings.json" | cut -d' ' -f1)
  if [ "$rc" -eq 0 ]; then
    fail "[check-install-preflight] corrupt entwurfProvider did NOT fail install"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  if [ "$before" != "$after" ]; then
    fail "[check-install-preflight] corrupt entwurfProvider was partially rewritten (packages[] leak)"; echo "$out"; cat "$proj/.pi/settings.json"; rm -rf "$fake" "$proj"; exit 1
  fi
  if ! printf '%s' "$out" | grep -q "entwurfProvider is not an object"; then
    fail "[check-install-preflight] corrupt entwurfProvider failed for the WRONG reason:"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  if [ -f "$fake/home/.pi/agent/settings.json" ]; then
    fail "[check-install-preflight] corrupt project provider still wrote user-scope settings"; cat "$fake/home/.pi/agent/settings.json"; rm -rf "$fake" "$proj"; exit 1
  fi
  rm -rf "$fake" "$proj"
  ok "[check-install-preflight] corrupt project entwurfProvider → fails before any project/user settings write"

  # negative 4 — corrupt project mcpServers shape, same no-partial-write contract.
  fake=$(mktemp -d); proj=$(mktemp -d)
  mkdir -p "$proj/.pi" "$fake/home"
  printf '{"entwurfProvider": {"mcpServers": []}}\n' > "$proj/.pi/settings.json"
  before=$(sha256sum "$proj/.pi/settings.json" | cut -d' ' -f1)
  rc=0; out=$(HOME="$fake/home" PI_CODING_AGENT_DIR="$fake/home/.pi/agent" "$REPO_DIR/run.sh" install "$proj" 2>&1) || rc=$?
  after=$(sha256sum "$proj/.pi/settings.json" | cut -d' ' -f1)
  if [ "$rc" -eq 0 ]; then
    fail "[check-install-preflight] corrupt entwurfProvider.mcpServers did NOT fail install"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  if [ "$before" != "$after" ]; then
    fail "[check-install-preflight] corrupt mcpServers was partially rewritten (packages[] leak)"; echo "$out"; cat "$proj/.pi/settings.json"; rm -rf "$fake" "$proj"; exit 1
  fi
  if ! printf '%s' "$out" | grep -q "entwurfProvider.mcpServers is not an object"; then
    fail "[check-install-preflight] corrupt mcpServers failed for the WRONG reason:"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  rm -rf "$fake" "$proj"
  ok "[check-install-preflight] corrupt project entwurfProvider.mcpServers → fails before any project settings write"

  # negative 5 — corrupt user-scope packages shape. Since install writes project
  # settings before user registration, this preflight must catch the user file up
  # front so a bad ~/.pi/agent/settings.json cannot leave the project half-wired.
  fake=$(mktemp -d); proj=$(mktemp -d)
  mkdir -p "$fake/home/.pi/agent"
  printf '{"packages": {"broken": true}}\n' > "$fake/home/.pi/agent/settings.json"
  rc=0; out=$(HOME="$fake/home" PI_CODING_AGENT_DIR="$fake/home/.pi/agent" "$REPO_DIR/run.sh" install "$proj" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "[check-install-preflight] corrupt user packages did NOT fail install"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  if [ -f "$proj/.pi/settings.json" ]; then
    fail "[check-install-preflight] corrupt user packages still wrote project settings (partial install)"; echo "$out"; cat "$proj/.pi/settings.json"; rm -rf "$fake" "$proj"; exit 1
  fi
  if ! printf '%s' "$out" | grep -q "user settings packages is not a JSON array"; then
    fail "[check-install-preflight] corrupt user packages failed for the WRONG reason:"; echo "$out"; rm -rf "$fake" "$proj"; exit 1
  fi
  rm -rf "$fake" "$proj"
  ok "[check-install-preflight] corrupt user-scope packages → fails before project settings write"

  # negative 6 — remove has the same two-step write risk (packages[] remove,
  # then provider cleanup). A corrupt provider must fail before packages[] is
  # altered, otherwise uninstall becomes a partial destructive write.
  proj=$(mktemp -d)
  mkdir -p "$proj/.pi"
  printf '{"entwurfProvider": [], "packages": ["%s"]}\n' "$REPO_DIR" > "$proj/.pi/settings.json"
  before=$(sha256sum "$proj/.pi/settings.json" | cut -d' ' -f1)
  rc=0; out=$("$REPO_DIR/run.sh" remove "$proj" 2>&1) || rc=$?
  after=$(sha256sum "$proj/.pi/settings.json" | cut -d' ' -f1)
  if [ "$rc" -eq 0 ]; then
    fail "[check-install-preflight] corrupt provider did NOT fail remove"; echo "$out"; rm -rf "$proj"; exit 1
  fi
  if [ "$before" != "$after" ]; then
    fail "[check-install-preflight] corrupt provider remove partially rewrote packages[]"; echo "$out"; cat "$proj/.pi/settings.json"; rm -rf "$proj"; exit 1
  fi
  rm -rf "$proj"
  ok "[check-install-preflight] remove with corrupt provider → fails before packages[] removal"
}

check_pi_preflight() {
  # 0.11 Stage 0 (2): the controlled-launch trust decision. Proves frozen
  # decision 8 precedence (saved false > saved true > prefix > no-inputs >
  # fail-fast) and decision 7's separator-boundary prefix against pi's own
  # ProjectTrustStore in a temp agentDir. Deterministic, no network/backend.
  run_ts scripts/check-pi-preflight.ts
}



check_auth_boundary() {
  # Auth-boundary guard (re-introduced for the ACP plugin on v2, retargeted off
  # the deleted 0.11.0 index.ts/acp-bridge.ts onto the new provider entry). This
  # is the code-level pair of AGENTS §Operating boundaries (trust invariants):
  # entwurf is a no-auth ACP plugin at the pi provider layer — it does NOT
  # provide, resell, or bypass any backend credentials.
  #
  # pi.registerProvider requires an apiKey when defining custom models, but the
  # plugin consumes none: backend auth belongs to the operator's own Claude CLI
  # child process. The registration MUST therefore use the lowercase+hyphen
  # no-auth sentinel, NOT a bare ALL-CAPS legacy-ENV reference (e.g.
  # "ANTHROPIC_API_KEY") which trips pi's legacy-env deprecation AND falsely
  # presents the plugin as API-key dependent.
  #
  # Scope: the new provider entry + its lib/acp/* modules. The regex matches only
  # an `apiKey:` field assigned a quoted ALL-CAPS env name, so explanatory
  # comments and the no-auth sentinel identifier pass.
  section "auth boundary (ACP plugin no-auth sentinel)"
  (cd "$REPO_DIR" && node --input-type=module <<'EOF'
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
const files = ['pi-extensions/acp-provider.ts'];
for (const f of readdirSync('pi-extensions/lib/acp')) {
  if (f.endsWith('.ts')) files.push(`pi-extensions/lib/acp/${f}`);
}
const offenders = [];
let sentinelSeen = false;
for (const f of files) {
  const src = readFileSync(f, 'utf8');
  const re = /apiKey:\s*"([A-Z][A-Z0-9_]*)"/g;
  let m;
  while ((m = re.exec(src)) !== null) offenders.push(`${f}: apiKey: "${m[1]}"`);
  if (src.includes('entwurf-no-auth')) sentinelSeen = true;
}
assert.equal(offenders.length, 0,
  `ACP provider apiKey must be a no-auth sentinel, not a legacy-ENV reference. Offenders:\n  ${offenders.join('\n  ')}`);
assert.ok(sentinelSeen,
  'no-auth sentinel literal "entwurf-no-auth" not found in the ACP provider surface — auth boundary unverified');
console.log(`[check-auth-boundary] ok — no legacy-ENV apiKey literal across ${files.length} ACP provider file(s); no-auth sentinel present`);
EOF
  )
}

check_acp_provider_surface() {
  # Deterministic gate for the ACP provider registration surface. Loads the REAL
  # provider lib modules AND compiles + drives the REAL entry against a fake pi,
  # asserting: one surface name, the no-auth sentinel shape, full
  # ProviderModelConfig rows on the curated claude anchor, the EXACT curated model
  # set both adapters contribute (claude 2 + cortex 4 —
  # [QK:CORTEX-PROVIDER-SIX-ROW-SURFACE], the claim that catches an entry which
  # silently drops a whole backend), and that streamSimple is the real
  # streamShellAcp backend (checked BY NAME, never invoked — invoking spawns an
  # ACP child). Pure, no pi runtime, no API.
  section "ACP provider surface (registration + both-adapter model set)"
  run_ts scripts/check-acp-provider-surface.ts
}

check_acp_sdk_surface() {
  # Transition shim (issue #62 Phase 3): the gate NAME is preserved while the S2a
  # ACP SDK dependency-surface contracts live in the vitest lane. Same layers as
  # the retired scripts gate — exact dep pins, pnpm-lock peer-resolution lock,
  # runtime resolver probes (anthropic peer / shared wire SDK / MCP peer edge),
  # wire-SDK value-export surface, and the forbidden anthropic-import sweep. The
  # per-layer mapping table is in the test file's header.
  section "ACP SDK surface (S2a dep pin + peer-resolution + no-client-use)"
  run_vitest test/acp-sdk-surface.contract.test.ts
}

check_acp_overlay() {
  # Deterministic gate for the S2b Claude config overlay materializer. Drives
  # ensureClaudeConfigOverlay against injected temp realDir/overlayDir (no
  # operator ~/.claude touched) and asserts: settings.json hooks:{} +
  # defaultMode bypassPermissions (unattended turns never prompt) + autoMemory off; whitelisted entries symlinked;
  # projects/sessions overlay-private real dirs (NOT symlinks); operator
  # personal config (CLAUDE.md/settings.local.json/plugins/agents) never leaks;
  # stale symlinks cleaned; binary-owned files preserved; CLAUDE_CONFIG_DIR
  # launch-env planted; idempotent. Pure, no live model.
  section "ACP overlay (S2b claude-config-overlay)"
  run_ts scripts/check-acp-overlay.ts
}

check_acp_tool_surface() {
  # Deterministic gate for the S2b Claude tool surface + exclude-tools
  # truthfulness preflight. Matrix over assertExcludeToolsHonored (claude
  # narrows via tools / native always-exposes / extension-tool exclusion is
  # honest) + buildClaudeSessionMeta shape lock (tools/allow/disallowed/
  # extraArgs/plugins) + the S2b billing-carrier guard (no _meta.systemPrompt
  # unless a caller supplies one). Pure preflight — NOT a backend wire read.
  section "ACP tool surface (S2b exclude-tools preflight + session meta)"
  run_ts scripts/check-acp-tool-surface.ts
}

check_acp_event_mapper() {
  # Deterministic gate for the S2c ACP→pi event mapper + context conversion.
  # Feeds synthetic ACP session_notification updates through the mapper and
  # asserts the pi AssistantMessageEvent sequence, including the hard boundary:
  # tool_call / tool_call_update render as TEXT NOTICES, never structured
  # toolcall_* (the ACP child already executed the tool). Also locks the
  # context→ACP-prompt transcript passthrough (excludes systemPrompt/thinking,
  # single text block). Pure, no live backend.
  section "ACP event mapper (S2c notification→stream + context)"
  run_ts scripts/check-acp-event-mapper.ts
}

check_acp_usage_accounting() {
  # Deterministic gate for the ACP USAGE ACCOUNTING contract (#93). A long-lived
  # Claude ACP session's dashboard read 10-18x high on three live ledgers,
  # because the per-turn token partition was dropped at the type boundary while
  # the backend's RUNNING SESSION TOTAL was assigned to a per-turn cost field pi
  # then summed. Drives streamAcpTurn against a fake ACP child + connection whose
  # turns are scripted (usage_update notification + PromptResponse.usage) for
  # five cells: the four-way token partition reaches the pi message; per-turn
  # costs are adjacent diffs of the running total and sum back to it across a
  # reused session; a turn with no cost notification attributes $0 and HOLDS the
  # baseline; a decreasing total rebaselines, attributes $0 and tells the
  # operator; totalTokens stays CONTEXT OCCUPANCY (asserted through pi's own
  # calculateContextTokens) and carries forward; and cortex — no measured
  # extractor — keeps its pre-#93 output untouched.
  section "ACP usage accounting (turn partition + adjacent-diff cost)"
  run_ts scripts/check-acp-usage-accounting.ts
}

check_acp_stop_reason() {
  # Deterministic gate for the ACP stop-reason contract. Drives every member of
  # the closed ACP terminal set (end_turn / max_tokens / max_turn_requests /
  # refusal / cancelled), plus an unrecognized reason and an ABSENT one, end to
  # end through streamAcpTurn against a fake connection — asserting the event
  # kind, the event reason, and the final message's stopReason / rawStopReason /
  # errorMessage together. Forbids the collapse-to-"stop" default that reported
  # refusals and exhausted turn budgets as finished answers. Also pins the
  # "pending" seed on the freshly created stream state.
  section "ACP stop reason (terminal set → pi verdict)"
  run_ts scripts/check-acp-stop-reason.ts
}

check_acp_prompt_lifecycle() {
  # Deterministic gate for the ACP prompt LIFECYCLE contract. A prompt has no
  # wall-clock cutoff: it ends when it resolves, when the operator aborts, or
  # when the child dies / its stdio ends. Drives streamAcpTurn against a fake
  # ACP child + connection for eight cells — a quiet in-flight turn is not
  # sealed and later completes on its ORIGINAL prompt; an abort sends ACP
  # session/cancel first (cancelled→aborted, no signal to a cooperating child);
  # a wedged agent is torn down after the bounded grace and still returns; a
  # mid-prompt child death reports exit status + stderr tail on BOTH the new and
  # the reuse path; a death BETWEEN turns is announced once by the next turn
  # while a teardown WE performed stays silent — plus pi's own
  # isRetryableAssistantError as
  # the oracle that our prompt-phase failure text is not a transient
  # (cold-replay) error.
  section "ACP prompt lifecycle (no wall clock; abort/child-death endings)"
  run_ts scripts/check-acp-prompt-lifecycle.ts
}

check_acp_launch_namespace() {
  # #72: the Claude ACP child must launch under a name entwurf OWNS. A janitor
  # installed on the host for ANOTHER harness selects the vendor process name
  # `claude-agent-acp` by argv substring and SIGTERMs it by age; entwurf retains
  # its child across turns, so its age is the session's. This gate holds the
  # name split, holds the launcher transparent (the vendor still answers
  # --version through it), and keeps an explicit operator override verbatim.
  section "ACP launch namespace (#72 — no vendor process name in our argv)"
  run_ts scripts/check-acp-launch-namespace.ts
}

check_acp_stream_hooks() {
  # Deterministic gate for the pi 0.84 streamSimple hook contract on the ACP rail
  # (#63; upstream pi-mono #7372 → doc-only #7576). before_provider_request
  # (onPayload) receives the EXACT ACP session/prompt wire params on new AND
  # reuse turns and its replacement becomes the wire — fail-closed: a non-null/
  # non-array-object violation, a changed bootstrapped sessionId, or an emptied
  # prompt array refuses the turn loudly with zero sends, a hook rejection fails
  # loud, and an abort raised while the hook is awaited wins before the wire
  # write on BOTH the new and the reuse path. after_provider_response (onResponse)
  # is an explicit local non-HTTP exemption: ACP has no truthful {status,
  # headers} and its terminal result arrives after the body was consumed, so the
  # gate pins ZERO invocations across success/error/abort turns.
  section "ACP streamSimple hooks (truthful onPayload; onResponse exemption)"
  run_ts scripts/check-acp-stream-hooks.ts
}

check_acp_prompt_builder() {
  # Deterministic gate for the S2d bootstrapPath-scoped ACP prompt builder (핀4).
  # Proves prompt SCOPE follows bootstrapPath: new=full transcript (history
  # carrier), reuse/resume/load=latest user delta (first user after last
  # assistant, SessionStart hook skipped, image marker kept, prior history
  # excluded so a reuse session is not re-injected its own history). Pure — it
  # touches no session store; the store and the reuse paths it feeds landed in
  # S2d-1b and carry their own gates (check-acp-session-store / -session-reuse).
  section "ACP prompt builder (S2d bootstrapPath prompt scope)"
  run_ts scripts/check-acp-prompt-builder.ts
}

check_acp_config() {
  # Deterministic gate for the S2g operator provider-config loader. Locks:
  # global+project merge (project overrides defined keys only; mcpServers merge
  # per-name with project win), defaults (strict-mcp-config on, [] sources,
  # baseline tools), fail-loud on invalid mcpServers/skillPlugins/
  # appendSystemPrompt:true/strictMcpConfig:false, nonempty skillPlugins auto-add
  # Skill+Skill(*), deterministic sorted mcp hash sensitive to command/env/url/
  # headers, and envelope enrich (PI_SESSION_ID/PI_AGENT_ID into entwurf-bridge
  # only, stale filtered, post-hash). Pure + temp-dir settings I/O, no child/spawn.
  section "ACP provider config (S2g operator mcpServers/skillPlugins/tools passthrough)"
  run_ts scripts/check-acp-config.ts
}

check_acp_session_store() {
  # Deterministic gate for the S2d-1b-1 session store / signature / bootstrap
  # decision. Locks: model-lock fail-loud throw in the pure decision, prefix-
  # compat (only a prefix history reuses; edited/compaction → new), carrier
  # drift → signature change → incompatible, and bootstrapPath ⟂ lifecyclePolicy
  # (turn-scoped/-p one-shot is ALWAYS new — no in-memory reuse, no persisted
  # resume/load in the first cut). Pure + temp-dir record I/O, no child/spawn.
  section "ACP session store (S2d-1b-1 signature/compat/bootstrap decision)"
  run_ts scripts/check-acp-session-store.ts
}

check_acp_backend_preflight() {
  # Deterministic gate for the S2c runtime tool-surface preflight. Calls
  # streamShellAcp with a context whose declared tools exclude a built-in the
  # Claude child still exposes (read) and asserts the turn fails fast into the
  # returned stream as an error event BEFORE any spawn — proving
  # assertExcludeToolsHonored is wired into the live provider path, not just the
  # pure gate. No backend launched (preflight throws first). Pure.
  section "ACP backend preflight (S2c runtime exclude-tools wiring)"
  run_ts scripts/check-acp-backend-preflight.ts
}

check_acp_session_reuse() {
  # Deterministic gate for S2d-1b-2b in-memory session reuse (backend.ts). Injects
  # a fake spawn/connection seam and CAPTURES each turn's prompt payload to prove
  # reuse is DELTA-ONLY: turn 2 carries the new nonce, never the turn-1 history,
  # with no second spawn/newSession. Also proves the mutable activePromptHandler
  # routes each turn's notices to its own stream, a persisted record is NOT
  # resumed in 1b-2b, a concurrent prompt fails loud (busy), the reused child is
  # never torn down between turns, and source-locks buildAcpPrompt wiring +
  # single-site applyAcpSessionUpdate via the router. No real child launched.
  section "ACP session reuse (S2d-1b-2b delta-only capture + mutable routing)"
  run_ts scripts/check-acp-session-reuse.ts
}

check_acp_carrier_augment() {
  # Deterministic gate for S2d-1c billing carrier (engraving) + first-user augment.
  # Separate axis from the reuse gate (GPT c32a6c8): locks that the carrier is
  # SHORT/empty-by-default/pure and folds into bridgeConfigSignature (so a carrier
  # change invalidates reuse but a stable carrier never rebuilds), and that the
  # rich augment rides the `new` prompt on the WIRE only — never the pi Context,
  # so it never enters contextMessageSignatures — with entwurf cwd/AGENTS.md
  # de-dup. Pure + temp-dir fs, no spawn.
  section "ACP carrier + augment (S2d-1c engraving + first-user augment)"
  run_ts scripts/check-acp-carrier-augment.ts
}

check_acp_cortex() {
  # Deterministic gate for the Cortex (Snowflake Cortex Code) ACP backend — the
  # first non-claude adapter on the rail, landed 0.13.0 on the CP0-measured
  # contract (docs/acp-backend-rail.md, Cortex audit D1–D10). The cortex source is one
  # `cortexAdapter` object (backend-adapter.ts) + its curated surface (models.ts)
  # + the dual-HOME overlay (overlay.ts); the 결합 규칙 requires the gate to land
  # WITH it, extending the check-acp-* family, so cortex's whole
  # deterministic axis lives here. Locks (each Cortex-audit D-pinned): the GLG-decided
  # 4-row curation rides real registry bases and the `cortex-` prefix routes to
  # cortexAdapter; launch is `cortex acp serve` with NO -m — the model is
  # enforced per turn via session/set_config_option with the native id (E);
  # CORTEX_HOME presence (empty included) refuses the spawn (D3); the dual-HOME
  # overlay isolates HOME+SNOWFLAKE_HOME per session key (P0-1: scope =
  # backend-passed resolveSessionKey, never ambient), passes through only
  # connections.toml / optional config.toml / credential_cache (D5/F — never the
  # whole cache, never skills; symlink-through, no copies — AGENTS §ACP Plugin
  # Boundary), authors autoUpdate:false (D4), and projects envelope-enriched
  # explicit servers into cortex/mcp.json with the real HOME restored on
  # entwurf-bridge alone (D9/D10), non-stdio failing loud; the
  # CORTEX_ACP_COMMAND override single-quotes shell-metachar connection tokens.
  # The gate self-manages the tsc-emit layer for the .js-suffixed backend-adapter
  # imports; no auth, no spawn, no live cortex needed. Kill-qualified via the
  # `acp-cortex` mutant lane under check-gate-qualification.
  section "ACP cortex backend (Snowflake Cortex Code — 1st non-claude adapter)"
  run_ts scripts/check-acp-cortex.ts
}

check_pack() {
  # Dry-run tarball invariant gate for the public npm surface.
  #
  # Runs `npm pack --dry-run --json`, then asserts:
  #   - runtime-critical files and the public verification/docs
  #     surface (run.sh, scripts/, curated docs/assets/*.gif,
  #     demo/) are present;
  #   - private/dev residue is absent (session dumps, debug logs,
  #     dev configs, workspace metadata, the OpenClaw plugin
  #     monorepo sibling that ships as its own npm package).
  #
  # Scope: this is the first of four checks in #13's publish gate.
  # The remaining three — actual `npm pack`, `tar -tf`, and local
  # install smoke from the packed tarball — are covered by
  # check_pack_install() below (commit 9e2a2ca, Phase 2.3 closeout).
  # Intent + policy live in NEXT.md Phase 2.3.
  section "pack invariants (dry-run)"

  local json
  # --silent so the `prepack` build (pnpm --silent run build-bridge → tsc) and
  # npm's own lifecycle banner stay off stdout; otherwise they pollute the --json
  # payload this parses. prepack runs on dry-run too, which is how dist lands in
  # this gate's file list.
  # with-dist-lock wraps the WHOLE pack (prepack build-bridge emit + npm's
  # post-build dist read) so a concurrent pack/build can't `rm -rf dist` mid-read
  # (the 2026-07-03 phantom "dist missing" race). The nested prepack build-bridge
  # is reentrant via ENTWURF_BUILD_LOCK_HELD.
  json=$(cd "$REPO_DIR" && bash scripts/with-dist-lock.sh npm pack --dry-run --json --silent 2>/dev/null) || {
    fail "[check-pack] npm pack --dry-run failed"
    return 1
  }

  local file_list
  file_list=$(node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    if (!Array.isArray(data) || data.length !== 1) {
      console.error("[check-pack] expected single tarball entry, got " +
        (Array.isArray(data) ? data.length : "non-array"));
      process.exit(2);
    }
    for (const f of data[0].files) console.log(f.path);
  ' <<<"$json") || {
    fail "[check-pack] failed to parse npm pack output"
    return 1
  }

  # .sh mode regression gate. The repo tracks 100755 in git, but if a
  # contributor's umask or a stray `git update-index --chmod=-x` drops
  # the bit the tarball will ship 0644 — and pi install hands the
  # tarball straight to `npm install`, so the bit needs to survive the
  # whole publish pipeline. Catch it here at dry-run time.
  local sh_mode_violations
  sh_mode_violations=$(node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const bad = data[0].files
      .filter(f => f.path.endsWith(".sh"))
      .filter(f => (f.mode & 0o111) === 0);
    for (const f of bad) console.log(f.path + " mode=0" + (f.mode || 0).toString(8));
  ' <<<"$json") || {
    fail "[check-pack] failed to inspect tarball modes"
    return 1
  }
  if [ -n "$sh_mode_violations" ]; then
    fail "[check-pack] .sh files missing executable bit in tarball:"
    echo "$sh_mode_violations" | sed 's/^/    /' >&2
    return 1
  fi

  local required=(
    "package.json" "README.md" "LICENSE" "CHANGELOG.md"
    "protocol.js" "run.sh"
    "pi-extensions/acp-provider.ts"
    "pi-extensions/lib/acp/models.ts" "pi-extensions/lib/acp/backend.ts"
    "pi-extensions/lib/acp/overlay.ts" "pi-extensions/lib/acp/tool-surface.ts"
    "pi-extensions/lib/acp/event-mapper.ts" "pi-extensions/lib/acp/context.ts"
    "pi-extensions/entwurf-control.ts"
    "pi-extensions/model-lock.ts" "pi-extensions/lib/entwurf-core.ts"
    "mcp/entwurf-bridge/src/index.ts"
    # 0.12.1 C — the prepack-built node_modules-safe boot artifact. start.sh runs
    # this dist JS when present (the .ts source can't strip-types under
    # node_modules). prepack runs on `npm pack --dry-run`, so it is in this gate.
    "mcp/entwurf-bridge/dist/mcp/entwurf-bridge/src/index.js"
    # 0.12.4 — the doctor's node_modules-safe store-scan artifact. meta-bridge-
    # doctor.sh runs this prebuilt JS when installed under node_modules (strip-types
    # refuses the .ts there), same boundary start.sh crosses. build-bridge emits it.
    "mcp/entwurf-bridge/dist/scripts/meta-bridge-store-doctor.js"
    # 0.12.7 — node_modules-safe agy PreInvocation hook. The stable npm bin
    # dispatches here because Node refuses raw .ts below node_modules.
    "mcp/entwurf-bridge/dist/scripts/agy-imprint.js"
    # 0.12.7 — the three OPERATOR commands run.sh dispatches. Installed, REPO_DIR is
    # under node_modules, so run_ts must find a compiled twin or the command is dead.
    "mcp/entwurf-bridge/dist/scripts/doctor-pi-provider.js"
    "mcp/entwurf-bridge/dist/scripts/new-session-id.js"
    "mcp/entwurf-bridge/dist/scripts/meta-bridge-prune.js"
    # #81 — the boot probe doctor-pi-provider imports (and `entwurf probe-bridge-command` runs).
    # Without the twin the installed doctor dies on the import before printing a verdict.
    "mcp/entwurf-bridge/dist/scripts/probe-bridge-command.js"
    # The generation verb. The hosts that need it are installed hosts on a
    # previous-generation store; without this twin the prescription every
    # v3-only rejection names would be dead exactly where it matters.
    "mcp/entwurf-bridge/dist/scripts/meta-bridge-fresh-cut.js"
    # #65 — the owner-normalized store projection consumers call INSTEAD of
    # parsing the store; installed hosts are exactly where those consumers live.
    "mcp/entwurf-bridge/dist/scripts/meta-facts.js"
    # #87 Bundle B — omp-receive-doctor drives this operator projection through
    # run.sh, so installed node_modules must have the compiled twin too.
    "mcp/entwurf-bridge/dist/scripts/omp-receive-facts.js"
    # 0.12.5 — the node_modules-safe plugin hook + its lib. install-meta-bridge copies
    # these compiled JS into the assembled plugin when installed (raw .ts can't
    # strip-types under node_modules). meta-session.js is shared with the store-doctor
    # above; listed here too so the hook axis fails loud if the emit graph drops it.
    "mcp/entwurf-bridge/dist/pi-extensions/meta-bridge-hook.js"
    # #82 — the Copilot birth entry's compiled closure, for the same node_modules
    # strip-types refusal that forces the Claude one.
    "mcp/entwurf-bridge/dist/pi-extensions/meta-bridge-hook-copilot.js"
    # #87 — the OMP birth entry's compiled closure. install-omp-bridge SELECTS this path
    # under node_modules, and docs/setup-clean-host.md tells operators to run that installer,
    # so its absence is not a degraded path: the installed installer dies at its own artifact
    # check before assembling anything. The unit skeleton's package.json below is the other
    # half — the installer copies it, and `pi/` ships per-FILE.
    "mcp/entwurf-bridge/dist/pi-extensions/meta-bridge-omp.js"
    "pi/meta-bridge-omp/entwurf-meta-omp/package.json"
    "mcp/entwurf-bridge/dist/pi-extensions/lib/meta-session.js"
    "scripts/postinstall-chmod.cjs"
    "pi/entwurf-capabilities.json"
    "pi/meta-bridge/.claude-plugin/marketplace.json"
    "pi/meta-bridge/entwurf-meta-receive/.claude-plugin/plugin.json"
    "pi/meta-bridge/entwurf-meta-receive/hooks/hooks.json"
    "pi/meta-bridge/entwurf-meta-receive/scripts/doorbell.sh"
    # 0.12.8 (#51) — the exec form names hook-launch.sh as the EXECUTABLE, so its
    # absence is not a degraded path: install dies at the chmod and no hook can run.
    # It rides a per-FILE entry in the files array (not a whole directory), so one
    # deleted line drops it from the tarball while every other gate stays green.
    "pi/meta-bridge/entwurf-meta-receive/scripts/hook-launch.sh"
    # #82 — the Copilot BIRTH unit. It is a SECOND marketplace root, not a second
    # plugin inside the Claude one: the Claude installer assembles one root and copies
    # one plugin out of it, so a shared marketplace.json would publish a `source` the
    # assembly does not contain. Same per-FILE listing discipline as the Claude unit.
    "pi/meta-bridge-copilot/.claude-plugin/marketplace.json"
    "pi/meta-bridge-copilot/entwurf-meta-receive-copilot/.claude-plugin/plugin.json"
    "pi/meta-bridge-copilot/entwurf-meta-receive-copilot/hooks/hooks.json"
    "pi/meta-bridge-copilot/entwurf-meta-receive-copilot/scripts/copilot-hook-launch.sh"
    "pi-extensions/meta-bridge-hook-copilot.ts"
    "scripts/copilot-bridge-install.sh"
    "scripts/copilot-bridge-uninstall.sh"
    "scripts/copilot-bridge-oracle.sh"
    "scripts/copilot-bridge-doctor.sh"
    # #82 RAIL 5 — the Copilot RECEIVER. A vendor EXTENSION (forked child, stdio
    # JSON-RPC), not a plugin, so it ships as its own unit and installs into the user
    # extensions dir. `extension.mjs` is the vendor's required entry NAME: a rename in
    # the tarball is not a degraded path, it is a unit Copilot never discovers.
    "pi/copilot-receive/entwurf-receive/extension.mjs"
    "scripts/copilot-receive-bridge.sh"
    "pi-extensions/meta-bridge-hook.ts"
    "pi-extensions/lib/meta-session.ts"
    "pi-extensions/lib/session-id.js"
    "scripts/meta-bridge-install.sh"
    # Both the installer and the doctor `source` this floor helper under `set -e`.
    # Missing, the doctor dies before printing a single line — the release oracle
    # would be silent rather than red.
    "scripts/meta-bridge-claude-floor.sh"
    "scripts/meta-bridge-state.py"
  )

  # Patterns that must NOT appear in the tarball. Anchored where the
  # match should be exact (e.g. ^bench\.sh$); loose where the residue
  # may appear under any path (e.g. \.log$).
  local forbidden_patterns=(
    'pi-session-.*\.html$'
    '\.log$'
    '\.cast$'
    '^bench\.sh$'
    '^biome\.json$'
    '^tsconfig\.json$'
    '^pnpm-(lock\.yaml|workspace\.yaml)$'
    '^NEXT\.md$'
    '^plugins/'
    '^node_modules/'
    '\.tmp-verify/'
    '\.agent-(reports|shell)/'
    'pi/meta-bridge/\.assembled/'
    # Python bytecode residue — `scripts/` ships whole via the files allowlist,
    # which BYPASSES .gitignore/.npmignore for its contents, so a `pnpm run check:full`
    # run's generated scripts/__pycache__/*.pyc rode into the 0.12.6 tarball. The
    # files-array `!**/__pycache__` / `!**/*.pyc` negations exclude it; this is the
    # tripwire that fails loud if that negation is ever dropped (결합 규칙).
    '__pycache__'
    '\.pyc$'
  )

  local pass=1 f pat hit

  for f in "${required[@]}"; do
    if ! grep -qxF "$f" <<<"$file_list"; then
      fail "[check-pack] MISSING required: $f"
      pass=0
    fi
  done

  for pat in "${forbidden_patterns[@]}"; do
    hit=$(grep -E "$pat" <<<"$file_list" || true)
    if [ -n "$hit" ]; then
      fail "[check-pack] FORBIDDEN matches pattern $pat:"
      echo "$hit" | sed 's/^/    /' >&2
      pass=0
    fi
  done

  local total
  total=$(printf '%s\n' "$file_list" | wc -l | tr -d ' ')
  echo "[check-pack] $total files in tarball"

  if [ "$pass" = "1" ]; then
    ok "[check-pack] invariants pass"
    return 0
  fi
  fail "[check-pack] invariants violated"
  return 1
}

# The pin-leak filter for the install tree's .pnpm listing, shared by the real scan and its
# self-test below. The version BOUNDARY is load-bearing: a pnpm .pnpm entry is
# `<name>@<version>` followed by either `_<peer-hash>` or end-of-name (measured pnpm 11.20.0
# on this tree), so an unbounded substring match would bless a lookalike such as `@0.84.40`
# while announcing the pinned floor — a false-green oracle (found by independent review,
# 2026-08-25).
pack_install_leaked_pi() {
  grep '^@earendil-works+pi-' | grep -Ev '@0\.84\.4(_|$)' || true
}

# Matcher self-test on SYNTHETIC lookalikes: a healthy install tree cannot exercise the
# false-green shape (it contains no 0.84.40), so the oracle is proven against a fixture
# listing. Expected: the two lookalikes leak, the pinned version passes bare and with a
# peer-hash suffix. Exposed as its own snapshot-safe subcommand because the heavy
# check-pack-install cannot run inside the qualification snapshot (no install environment),
# and a kill-proof needs a control-green gate there; check-pack-install still runs this
# first so the heavy gate cannot proceed on a broken oracle.
check_pack_pin_matcher() {
  local matcher_probe
  matcher_probe=$(printf '%s\n' \
    '@earendil-works+pi-ai@0.84.4' \
    '@earendil-works+pi-ai@0.84.4_@modelcontextprotocol+sdk@1.29.0_zod@4.3.6' \
    '@earendil-works+pi-ai@0.84.40' \
    '@earendil-works+pi-agent-core@0.84.3' | pack_install_leaked_pi)
  if [ "$matcher_probe" != '@earendil-works+pi-ai@0.84.40
@earendil-works+pi-agent-core@0.84.3' ]; then
    fail "[QK:PACK-INSTALL-PIN-MATCHER-BOUNDED] the pin-leak matcher must flag the 0.84.40/0.84.3 lookalikes and pass 0.84.4 bare or with a peer-hash — got: ${matcher_probe:-<nothing leaked>}"
    return 1
  fi
  echo "[check-pack-pin-matcher] ok — the pin-leak matcher is version-bounded (lookalikes leak, pinned version passes bare and with a peer-hash)"
}

_check_pack_install_impl() {
  check_pack_pin_matcher || return 1

  # Heavy publish gate. Runs the remaining three checks in #13's
  # publish checklist that check_pack (dry-run only) does not cover:
  #
  #   2. actual `npm pack` — produces the real tarball
  #   3. `tar -tf` — cross-checks contents against dry-run invariants
  #   4. fresh-temp project local install smoke — pnpm add the tarball
  #      with required peers, then import('@junghanacs/entwurf/package.json')
  #      to confirm the installed shape resolves end-to-end.
  #
  # Excluded from the default `pnpm check` because the install smoke
  # spends 5-15s on dependency resolution. Wired into prepublishOnly
  # so `npm publish` cannot succeed if the actual install path is
  # broken even when dry-run invariants look fine.
  #
  # Force --dry-run=false because `npm publish --dry-run` exports
  # npm_config_dry_run=true into lifecycle scripts. Without the explicit
  # override, this nested actual-pack smoke prints the tarball name but
  # does not write the .tgz file, causing prepublishOnly to fail before
  # a real publish can be exercised.
  section "publish install smoke (actual pack + tar + fresh install)"

  local version tgz_name tgz_path
  version=$(node -p "require('${REPO_DIR}/package.json').version")
  # Scoped npm packages produce a tarball named "<scope>-<name>-<version>.tgz"
  # where the `@` is stripped and `/` becomes `-`. For `@junghanacs/entwurf`
  # that lands as `junghanacs-entwurf-<version>.tgz`. Hardcoded against
  # the scope above so a name change cannot silently slide past this gate.
  tgz_name="junghanacs-entwurf-${version}.tgz"
  # Pack into a UNIQUE per-run dir, never the repo root. Writing/removing a fixed
  # ${REPO_DIR}/<tgz> pollutes the working tree (a crash leaves a stray tarball) AND
  # lets two concurrent packs corrupt/delete each other's artifact ("tarball data
  # seems corrupted" / ENOENT; a half-installed package then fails the later
  # install-meta-bridge check downstream). A per-run pack dir makes the tarball
  # instance-private end-to-end — every consumer below + the trap follow $pack_tmp.
  local pack_tmp
  pack_tmp=$(mktemp -d -t entwurf-pack.XXXXXX)
  tgz_path="${pack_tmp}/${tgz_name}"

  # 0.12.1 C — stale-dist guard. `tsc` emit does NOT prune orphaned files from
  # outDir, and `files: ["mcp/"]` would carry any leftover dist file into the
  # tarball. build-bridge therefore `rm -rf`s dist before emit. Prove it: plant a
  # sentinel in dist, then assert the pack's prepack (build-bridge) wiped it so it
  # never reaches the tarball. Without the clean step this sentinel ships.
  local stale_probe="${REPO_DIR}/mcp/entwurf-bridge/dist/__stale_probe__.js"
  mkdir -p "$(dirname "$stale_probe")"
  printf 'module.exports = "stale";\n' > "$stale_probe"

  echo "[check-pack-install] npm pack -> ${tgz_name}"
  # with-dist-lock: same whole-pack serialization as check-pack — this heavy gate
  # and a background check-pack (via `pnpm run check:full`) both pack, and unserialized they
  # race the shared dist dir. The stale-dist sentinel planted just above still
  # proves build-bridge's own `rm -rf dist` clean step under the lock.
  (cd "$REPO_DIR" && bash scripts/with-dist-lock.sh npm pack --dry-run=false --pack-destination "$pack_tmp" 2>&1 | tail -1) || {
    fail "[check-pack-install] npm pack failed"
    return 1
  }

  if [ ! -f "$tgz_path" ]; then
    fail "[check-pack-install] tarball not produced: $tgz_path"
    return 1
  fi

  # tar -tf invariants — cross-check against dry-run shape. Same
  # required/forbidden axes as check_pack; if they disagree, the
  # dry-run resolver and the actual tarball diverged (npm bug or
  # files allowlist drift) and publish must not proceed.
  local tar_files pass=1 f pat
  tar_files=$(tar -tf "$tgz_path" | sed 's|^package/||' | grep -v '/$' || true)

  # 0.12.1 C — the planted stale sentinel must NOT have survived into the tarball.
  # If it did, build-bridge's `rm -rf dist` clean step regressed and stale/orphan
  # emit can ship. (See the plant just before npm pack above.)
  if grep -qxF "mcp/entwurf-bridge/dist/__stale_probe__.js" <<<"$tar_files"; then
    rm -rf "$pack_tmp"
    fail "[check-pack-install] stale dist file shipped — build-bridge did not clean dist before emit (orphan-emit publish risk)"
    return 1
  fi

  # Required tarball contents. The old 0.11.0 ACP root files (index.ts,
  # acp-bridge.ts, event-mapper.ts, engraving.ts, pi-context-augment.ts,
  # pi-extensions/entwurf.ts) were removed on v2-only and are GONE — keeping them
  # here made this heavy gate silently RED (publish-blocking) while the deterministic floor
  # (check:full runs only check-pack, not check-pack-install) stayed green. The ACP
  # plugin re-enters on v2 as the provider entry + lib/acp/* modules below.
  local tar_required=(
    "package.json" "README.md" "LICENSE" "CHANGELOG.md"
    "protocol.js" "run.sh"
    "pi-extensions/acp-provider.ts"
    "pi-extensions/lib/acp/models.ts" "pi-extensions/lib/acp/backend.ts"
    "pi-extensions/lib/acp/overlay.ts" "pi-extensions/lib/acp/tool-surface.ts"
    "pi-extensions/lib/acp/event-mapper.ts" "pi-extensions/lib/acp/context.ts"
    "pi-extensions/entwurf-control.ts"
    "pi-extensions/model-lock.ts" "pi-extensions/lib/entwurf-core.ts"
    "mcp/entwurf-bridge/src/index.ts"
    # 0.12.1 C — prepack-built node_modules-safe boot artifact (see check-pack).
    "mcp/entwurf-bridge/dist/mcp/entwurf-bridge/src/index.js"
    # 0.12.4 — prebuilt node_modules-safe store-scan artifact for the doctor
    # (see check-pack). The installed-scan smoke below runs exactly this file.
    "mcp/entwurf-bridge/dist/scripts/meta-bridge-store-doctor.js"
    # 0.12.7 — node_modules-safe agy PreInvocation hook. The installed bin smoke
    # below executes this exact compiled leaf from under node_modules.
    "mcp/entwurf-bridge/dist/scripts/agy-imprint.js"
    # 0.12.7 — the three operator commands (see check-pack). The installed-command
    # regression below drives each one through the real `entwurf` bin.
    "mcp/entwurf-bridge/dist/scripts/doctor-pi-provider.js"
    "mcp/entwurf-bridge/dist/scripts/new-session-id.js"
    "mcp/entwurf-bridge/dist/scripts/meta-bridge-prune.js"
    # #81 — the boot probe the installed doctor imports (see check-pack).
    "mcp/entwurf-bridge/dist/scripts/probe-bridge-command.js"
    # The generation verb (see check-pack). The installed-command regression below
    # opens a fresh generation on a 0-record sandbox through the real bin.
    "mcp/entwurf-bridge/dist/scripts/meta-bridge-fresh-cut.js"
    # #65 — the owner-normalized store projection (see check-pack).
    "mcp/entwurf-bridge/dist/scripts/meta-facts.js"
    # #87 Bundle B — omp-receive-doctor reaches this through the installed dispatcher.
    "mcp/entwurf-bridge/dist/scripts/omp-receive-facts.js"
    # 0.12.5 — node_modules-safe plugin hook + lib (see check-pack). The installed
    # hook regression below runs exactly this compiled JS from under node_modules.
    "mcp/entwurf-bridge/dist/pi-extensions/meta-bridge-hook.js"
    # #82 — the Copilot birth entry's compiled closure, for the same node_modules
    # strip-types refusal that forces the Claude one.
    "mcp/entwurf-bridge/dist/pi-extensions/meta-bridge-hook-copilot.js"
    # #87 — the OMP birth entry's compiled closure. install-omp-bridge SELECTS this path
    # under node_modules, and docs/setup-clean-host.md tells operators to run that installer,
    # so its absence is not a degraded path: the installed installer dies at its own artifact
    # check before assembling anything. The unit skeleton's package.json below is the other
    # half — the installer copies it, and `pi/` ships per-FILE.
    "mcp/entwurf-bridge/dist/pi-extensions/meta-bridge-omp.js"
    "pi/meta-bridge-omp/entwurf-meta-omp/package.json"
    "mcp/entwurf-bridge/dist/pi-extensions/lib/meta-session.js"
    "scripts/postinstall-chmod.cjs"
    "pi/entwurf-capabilities.json"
    "pi/meta-bridge/.claude-plugin/marketplace.json"
    "pi/meta-bridge/entwurf-meta-receive/.claude-plugin/plugin.json"
    "pi/meta-bridge/entwurf-meta-receive/hooks/hooks.json"
    "pi/meta-bridge/entwurf-meta-receive/scripts/doorbell.sh"
    # 0.12.8 (#51) — see check-pack: the exec form's executable and the floor helper
    # both callers source. The install smoke below asserts the ASSEMBLED launcher is
    # executable; this asserts the artifact it is assembled FROM actually shipped.
    "pi/meta-bridge/entwurf-meta-receive/scripts/hook-launch.sh"
    # #82 — the Copilot BIRTH unit. It is a SECOND marketplace root, not a second
    # plugin inside the Claude one: the Claude installer assembles one root and copies
    # one plugin out of it, so a shared marketplace.json would publish a `source` the
    # assembly does not contain. Same per-FILE listing discipline as the Claude unit.
    "pi/meta-bridge-copilot/.claude-plugin/marketplace.json"
    "pi/meta-bridge-copilot/entwurf-meta-receive-copilot/.claude-plugin/plugin.json"
    "pi/meta-bridge-copilot/entwurf-meta-receive-copilot/hooks/hooks.json"
    "pi/meta-bridge-copilot/entwurf-meta-receive-copilot/scripts/copilot-hook-launch.sh"
    "pi-extensions/meta-bridge-hook-copilot.ts"
    "scripts/copilot-bridge-install.sh"
    "scripts/copilot-bridge-uninstall.sh"
    "scripts/copilot-bridge-oracle.sh"
    "scripts/copilot-bridge-doctor.sh"
    # #82 RAIL 5 — the Copilot RECEIVER. A vendor EXTENSION (forked child, stdio
    # JSON-RPC), not a plugin, so it ships as its own unit and installs into the user
    # extensions dir. `extension.mjs` is the vendor's required entry NAME: a rename in
    # the tarball is not a degraded path, it is a unit Copilot never discovers.
    "pi/copilot-receive/entwurf-receive/extension.mjs"
    "scripts/copilot-receive-bridge.sh"
    "pi-extensions/meta-bridge-hook.ts"
    "pi-extensions/lib/meta-session.ts"
    "pi-extensions/lib/session-id.js"
    "scripts/meta-bridge-install.sh"
    "scripts/meta-bridge-claude-floor.sh"
    "scripts/meta-bridge-state.py"
  )
  for f in "${tar_required[@]}"; do
    if ! grep -qxF "$f" <<<"$tar_files"; then
      fail "[check-pack-install] tar missing required: $f"
      pass=0
    fi
  done

  local tar_forbidden=(
    'pi-session-.*\.html$' '\.log$' '\.cast$'
    '^bench\.sh$' '^biome\.json$' '^tsconfig\.json$'
    '^pnpm-(lock\.yaml|workspace\.yaml)$' '^NEXT\.md$'
    '^plugins/' '^node_modules/'
    '\.tmp-verify/' '\.agent-(reports|shell)/'
    'pi/meta-bridge/\.assembled/'
    # Python bytecode residue (see check-pack forbidden note): scripts/ ships
    # whole, so generated pyc bypasses ignore files — this cross-checks the actual
    # tarball, not just the dry-run resolver.
    '__pycache__' '\.pyc$'
  )
  for pat in "${tar_forbidden[@]}"; do
    local hit
    hit=$(grep -E "$pat" <<<"$tar_files" || true)
    if [ -n "$hit" ]; then
      fail "[check-pack-install] tar contains forbidden pattern $pat:"
      echo "$hit" | sed 's/^/    /' >&2
      pass=0
    fi
  done

  if [ "$pass" != "1" ]; then
    rm -rf "$pack_tmp"
    fail "[check-pack-install] tar -tf invariants violated"
    return 1
  fi
  echo "[check-pack-install] tar -tf invariants pass ($(printf '%s\n' "$tar_files" | wc -l | tr -d ' ') files)"

  # Fresh-temp install smoke. Uses pnpm because that is what this
  # repo packages with; --ignore-workspace stops it from re-attaching
  # to our pnpm-workspace.yaml; --ignore-scripts blocks the husky
  # prepare hook (and any future install scripts) from running inside
  # the consumer project. Peer deps are pinned to the CURRENT pi release
  # baseline (the package.json devDep pin — the pins below are what
  # check-dep-versions binds to that devDep) so the smoke matches the same
  # shape an external pi user would have after `pi install`.
  local tmp npm_tmp
  tmp=$(mktemp -d -t entwurf-install-smoke.XXXXXX)
  # Separate tree for the npm-managed regression below: npm install must NOT be
  # nested under $tmp, whose pnpm-add node_modules/package.json would make npm
  # climb the parent and choke ("Cannot read properties of null").
  npm_tmp=$(mktemp -d -t entwurf-npm-managed.XXXXXX)
  trap 'rm -rf "$tmp" "$npm_tmp" "$pack_tmp"' RETURN

  printf '%s\n' '{ "name": "entwurf-install-smoke", "version": "0.0.0", "private": true }' > "$tmp/package.json"

  # pi-agent-core is pinned even though we never import it: pi-coding-agent depends
  # on it by CARET (`^0.84.x`), so with no lockfile in this fresh temp project it
  # floats to whatever pi published last — and that newer core then drags a NESTED
  # pi-ai of its own. Measured 2026-07-21: pinning only the three we import left
  # pi-agent-core@0.80.10 + pi-ai@0.80.10 in the tree while the gate still announced
  # "pinned pi 0.80.7". The gate would then be verifying an UNVERIFIED runtime — the
  # exact class this cut exists to close. Pin every @earendil-works package that
  # constitutes the pi runtime, not just the ones whose types we touch.
  #
  # The constellation is re-measured at each pi bump, never carried forward. At
  # 0.84.0 it GREW: pi-coding-agent's @earendil-works caret set went from
  # {pi-agent-core, pi-ai, pi-tui} at 0.83.0 to {pi-agent-core, pi-ai, pi-client,
  # pi-protocol, pi-tui}, so pi-client and pi-protocol are pinned here for the
  # first time. Unpinned they would float exactly like pi-agent-core did in the
  # 2026-07-21 incident above. pi-telemetry joined the explicit pin list on
  # 2026-08-31: it arrives transitively (pi-agent-core and pi-ai both carry
  # `^0.84.x` carets on it), and upstream's 0.84.4 patch publish (2026-08-28
  # 22:04Z) floated that caret in this lockfile-less temp install, turning CI
  # red through the leak assertion below. That explicit pin is what held the
  # line until the bump lane ran; the verified floor is 0.84.4 as of
  # 2026-09-01, and the pin moved WITH it rather than being retired. The leak
  # assertion below still covers every other pi package, including any package
  # a future pi bump adds to the closure.
  echo "[check-pack-install] pnpm add into $tmp (with 0.84.x peers + typebox)"
  local install_log
  install_log=$(cd "$tmp" && pnpm add \
    "$tgz_path" \
    "@earendil-works/pi-ai@0.84.4" \
    "@earendil-works/pi-coding-agent@0.84.4" \
    "@earendil-works/pi-tui@0.84.4" \
    "@earendil-works/pi-agent-core@0.84.4" \
    "@earendil-works/pi-client@0.84.4" \
    "@earendil-works/pi-protocol@0.84.4" \
    "@earendil-works/pi-telemetry@0.84.4" \
    "typebox@latest" \
    --ignore-workspace --ignore-scripts 2>&1) || {
    fail "[check-pack-install] pnpm add failed:"
    echo "$install_log" | tail -10 | sed 's/^/    /' >&2
    return 1
  }

  # A pin is a wish until the resolved tree is read back. Assert it: EVERY
  # @earendil-works pi package present — direct or transitive, top level or nested —
  # must be the pinned 0.84.4. Anything else means an unpinned caret floated and the
  # rest of this gate would be exercising a runtime nobody verified, while still
  # printing "pinned pi 0.84.4". Fail loud instead of proving the wrong floor.
  local leaked_pi
  leaked_pi=$(ls "$tmp/node_modules/.pnpm" 2>/dev/null | pack_install_leaked_pi)
  if [ -n "$leaked_pi" ]; then
    fail "[check-pack-install] UNVERIFIED pi runtime resolved into the install tree (expected only 0.84.4):"
    printf '%s\n' "$leaked_pi" | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] pi runtime tree pin verified: every @earendil-works pi package is 0.84.4"

  # Resolve the installed package.json and confirm pi.extensions
  # arrived intact. If pi.extensions is empty or missing, the
  # consumer pi runtime would fail to register any extension.
  local probe
  probe=$(cd "$tmp" && node --input-type=module -e "
    const m = await import('@junghanacs/entwurf/package.json', { with: { type: 'json' } });
    const pkg = m.default;
    const exts = Array.isArray(pkg.pi?.extensions) ? pkg.pi.extensions.length : 0;
    if (exts === 0) { console.error('pi.extensions missing or empty'); process.exit(1); }
    console.log(pkg.version + ' (' + exts + ' extensions)');
  " 2>&1) || {
    fail "[check-pack-install] installed package probe failed:"
    echo "$probe" | sed 's/^/    /' >&2
    return 1
  }
  echo "[check-pack-install] installed: $probe"

  # Pi package loader smoke — actual `pi` reads the manifest and
  # registers the provider. rc=0 + the curated model list in the
  # output means pi accepted the package as a real extension, not
  # just a well-shaped npm tarball. `--list-models` does not spawn
  # the Claude/Codex/Gemini backends, so this stays credential-free
  # and safe to run in CI. Output goes to stderr; capture both
  # streams with 2>&1.
  #
  # The pi that loads the tarball is the PINNED peer this smoke just installed next to
  # it ($tmp/node_modules/.bin/pi = the floor of the supported peer range), NEVER
  # whatever `pi` the host happens to have on PATH. A gate may not READ the operator's
  # global install any more than it may WRITE it: PATH resolution made this gate green
  # on a dev box carrying a newer global pi and RED in CI, which carries no global pi
  # at all — and in neither case was it driving the runtime the repo actually pins.
  #
  # EVERY pi invocation below — including `--version` — runs under the throwaway
  # HOME/XDG/agent-dir defined here once. pi reads settings BEFORE it prints its
  # version (bootstrapSettingsManager precedes the --version branch in pi's main),
  # so an unsandboxed probe would open the operator's real ~/.pi/agent/settings.json:
  # the same read coupling this fix exists to remove. One env array, no second
  # spelling to drift out of step.
  local loader_home="$tmp/loader-home"
  mkdir -p "$loader_home/.pi/agent"
  local -a pi_env=(
    HOME="$loader_home"
    XDG_DATA_HOME="$loader_home/.local/share"
    XDG_STATE_HOME="$loader_home/.local/state"
    XDG_CACHE_HOME="$loader_home/.cache"
    PI_CODING_AGENT_DIR="$loader_home/.pi/agent"
  )

  # Assert the version: a gate that cannot name which pi it proved has proved nothing.
  # package.json devDeps is the pin SSOT (check-dep-versions keeps the peer-install
  # literals above in step with it).
  local pi_bin="$tmp/node_modules/.bin/pi" pi_pin pi_ver
  if [ ! -x "$pi_bin" ]; then
    fail "[check-pack-install] pinned pi missing from the install-smoke tree ($pi_bin) — cannot run loader smoke"
    return 1
  fi
  pi_pin=$(cd "$REPO_DIR" && node -p "require('./package.json').devDependencies['@earendil-works/pi-coding-agent']")
  pi_ver=$(cd "$tmp" && env "${pi_env[@]}" "$pi_bin" --version 2>&1 | head -1 | tr -d '[:space:]')
  if [ "$pi_ver" != "$pi_pin" ]; then
    fail "[check-pack-install] install-smoke pi is '$pi_ver', expected the pinned '$pi_pin' — the loader smoke would prove the wrong runtime"
    return 1
  fi
  echo "[check-pack-install] loader runtime: pinned pi $pi_ver (not the host's global pi)"

  # The loader smoke must depend ONLY on the -e package path, never on the operator's
  # real ~/.pi/agent/settings.json — otherwise a live-config change could silently
  # pass/fail the gate (the exact "check must not depend on live wiring" impurity
  # this whole lane is about).
  local loader_out
  loader_out=$(cd "$tmp" && env "${pi_env[@]}" "$pi_bin" -e "$tmp/node_modules/@junghanacs/entwurf" --list-models entwurf 2>&1) || {
    fail "[check-pack-install] pi loader smoke failed (exit non-zero):"
    echo "$loader_out" | tail -10 | sed 's/^/    /' >&2
    return 1
  }
  if ! grep -q "entwurf" <<<"$loader_out"; then
    fail "[check-pack-install] pi loader output missing entwurf model surface:"
    echo "$loader_out" | tail -10 | sed 's/^/    /' >&2
    return 1
  fi
  # Verify the EXACT curated surface the installed package registers — both
  # backends (claude 2 rows + cortex 4 rows = 6), as a SET, not as anchors.
  #
  # Why exact-set and not `grep -q <id>`: the cortex ids CONTAIN the claude ids
  # as substrings (`cortex-claude-sonnet-5` matches a bare `claude-sonnet-5`
  # grep), so a substring probe could go green on a surface that dropped every
  # unprefixed Claude row. And an anchor-only probe cannot see a MISSING cortex
  # row at all — that is exactly the installed-consumer gap this assertion
  # closes: the source-side sets are pinned by check-acp-cortex /
  # check-acp-provider-surface, but only THIS gate proves the ids survive the
  # pack → install → pi-loader path into a real consumer's model list.
  #
  # Parse rows whose FIRST field is the provider `entwurf` (pi prints a
  # `provider model context …` table; the header row's first field is
  # `provider`, so it drops out) and take the second field as the model id.
  local loader_ids loader_expected
  loader_ids=$(awk '$1 == "entwurf" { print $2 }' <<<"$loader_out" | LC_ALL=C sort)
  loader_expected=$(printf '%s\n' \
    claude-opus-5 \
    claude-sonnet-5 \
    cortex-auto \
    cortex-claude-opus-5 \
    cortex-claude-sonnet-5 \
    cortex-openai-gpt-5.4 | LC_ALL=C sort)
  if [ "$loader_ids" != "$loader_expected" ]; then
    fail "[check-pack-install] installed provider model set drifted — expected exactly 6 curated ids (claude 2 + cortex 4):"
    echo "  expected:" >&2
    echo "$loader_expected" | sed 's/^/    /' >&2
    echo "  actual (entwurf rows):" >&2
    echo "${loader_ids:-<none>}" | sed 's/^/    /' >&2
    echo "  raw loader output:" >&2
    echo "$loader_out" | tail -15 | sed 's/^/    /' >&2
    return 1
  fi
  # Name the set on SUCCESS too, not only in the failure branch — same principle as
  # the pinned-pi version assert above: a gate that cannot name what it proved has
  # proved nothing, and "6 rows" without the ids cannot be audited from a CI log.
  echo "[check-pack-install] pi loader smoke pass (entwurf registered; exact 6-row curated set: claude 2 + cortex 4):"
  echo "$loader_ids" | sed 's/^/    /'

  # npm-managed neutral install regression — the README's PRIMARY install path is
  # now `npm install @junghanacs/entwurf` (NOT `pi install npm:...`). This layout
  # lands the package under node_modules, hoists runtime deps to the sibling
  # node_modules, has no package-local node_modules, and the pi peer trio must be
  # absent because pi is an optional adapter lane. The old cwd-relative
  # preflight_dep_integrity rejected every hoisted-dep npm install; 0.12.0 then
  # additionally died because start.sh tried strip-types under node_modules.
  # Prove `entwurf`/`entwurf-bridge` bins exist, `run.sh install` writes settings
  # from the hoisted layout, and the installed bridge boots from dist. HOME is
  # redirected to a throwaway dir so the install's user-scope writes (settings.json
  # registration under $HOME/.pi/agent) land in a temp home, never the operator's.
  if ! command -v npm >/dev/null 2>&1; then
    fail "[check-pack-install] npm not on PATH — cannot run npm-managed install regression"
    return 1
  fi
  local npmroot="$npm_tmp/npmroot" npmhome="$npm_tmp/npmhome" npmproj="$npm_tmp/npmproj" npm_log npm_pkg wire_log
  mkdir -p "$npmroot" "$npmhome" "$npmproj"
  npm_log=$(cd "$npmroot" && npm install "$tgz_path" --no-audit --no-fund 2>&1) || {
    fail "[check-pack-install] npm-managed neutral install failed:"
    echo "$npm_log" | tail -10 | sed 's/^/    /' >&2
    return 1
  }
  npm_pkg="$npmroot/node_modules/@junghanacs/entwurf"
  if [ ! -x "$npm_pkg/run.sh" ]; then
    fail "[check-pack-install] npm-managed layout missing executable run.sh (postinstall-chmod did not run?) at $npm_pkg"
    return 1
  fi
  if [ ! -x "$npmroot/node_modules/.bin/entwurf" ] || [ ! -x "$npmroot/node_modules/.bin/entwurf-bridge" ] || [ ! -x "$npmroot/node_modules/.bin/entwurf-statusline" ] || [ ! -x "$npmroot/node_modules/.bin/entwurf-agy-statusline" ] || [ ! -x "$npmroot/node_modules/.bin/entwurf-agy-imprint" ]; then
    fail "[check-pack-install] npm-managed neutral install missing package bins (entwurf / entwurf-bridge / entwurf-statusline / entwurf-agy-statusline / entwurf-agy-imprint)"
    ls -l "$npmroot/node_modules/.bin" 2>/dev/null | sed 's/^/    /' >&2 || true
    return 1
  fi
  if [ ! -x "$npmroot/node_modules/.bin/entwurf-copilot-statusline" ]; then
    fail "[check-pack-install] npm-managed neutral install missing package bin entwurf-copilot-statusline"
    ls -l "$npmroot/node_modules/.bin" 2>/dev/null | sed 's/^/    /' >&2 || true
    return 1
  fi
  wire_log=$(HOME="$npmhome" XDG_DATA_HOME="$npmhome/.local/share" XDG_STATE_HOME="$npmhome/.local/state" XDG_CACHE_HOME="$npmhome/.cache" "$npm_pkg/run.sh" install "$npmproj" 2>&1) || {
    fail "[check-pack-install] npm-managed run.sh install failed (preflight rejected hoisted deps?):"
    echo "$wire_log" | tail -15 | sed 's/^/    /' >&2
    return 1
  }
  if [ ! -f "$npmproj/.pi/settings.json" ]; then
    fail "[check-pack-install] npm-managed run.sh install did not write settings.json:"
    echo "$wire_log" | tail -15 | sed 's/^/    /' >&2
    return 1
  fi
  if ! grep -q "node_modules/@junghanacs/entwurf" <<<"$wire_log"; then
    fail "[check-pack-install] npm-managed install did not report the npm package source:"
    echo "$wire_log" | tail -15 | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] npm-managed install regression pass (hoisted-dep run.sh install wrote settings)"

  # THE 2026-07-03 regression gate: removing `pi install` from setup dropped
  # user-scope citizen registration, so `--entwurf-control` was Unknown in a
  # foreign cwd. Prove the npm consumer path closes it end-to-end: run.sh install
  # (run above under HOME="$npmhome") must have registered the package in the USER
  # settings, and pi must then load the entwurf extension + its flags from a cwd
  # OUTSIDE the project. Fully isolated in the temp HOME — never touches ~/.pi.
  local npm_user_settings="$npmhome/.pi/agent/settings.json"
  if [ ! -f "$npm_user_settings" ]; then
    fail "[check-pack-install] npm-managed install did not register a user-scope citizen at $npm_user_settings"
    return 1
  fi
  if ! python3 -c "
import json,sys
p=json.load(open('$npm_user_settings')).get('packages',[])
srcs=[(x if isinstance(x,str) else x.get('source')) for x in p]
sys.exit(0 if any(isinstance(s,str) and s.endswith('/node_modules/@junghanacs/entwurf') for s in srcs) else 1)
"; then
    fail "[check-pack-install] user-scope settings.json lacks the npm entwurf package in packages[]:"
    sed 's/^/    /' "$npm_user_settings" >&2
    return 1
  fi
  # Foreign cwd ($tmp — NOT the project, no project .pi): --entwurf-control must be
  # a KNOWN flag and the entwurf provider must load, sourced only from user scope.
  # Before the fix this printed "Unknown options: --entwurf-control".
  local foreign_out
  foreign_out=$(cd "$tmp" && HOME="$npmhome" XDG_DATA_HOME="$npmhome/.local/share" XDG_STATE_HOME="$npmhome/.local/state" XDG_CACHE_HOME="$npmhome/.cache" PI_CODING_AGENT_DIR="$npmhome/.pi/agent" "$pi_bin" --entwurf-control --list-models entwurf 2>&1) || {
    fail "[check-pack-install] foreign-cwd --entwurf-control smoke failed (user-scope citizen not loading?):"
    echo "$foreign_out" | tail -10 | sed 's/^/    /' >&2
    return 1
  }
  if grep -qi "Unknown option" <<<"$foreign_out" || ! grep -q "claude-opus-5" <<<"$foreign_out"; then
    fail "[check-pack-install] foreign-cwd --entwurf-control did not load the entwurf extension from user scope:"
    echo "$foreign_out" | tail -10 | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] user-scope citizen regression pass (npm consumer: --entwurf-control loads from a foreign cwd)"

  # Two-root ownership row (#86 C2, L1b extension): a SECOND npm root under the
  # SAME consumer HOME must not silently steal the user-scope registration the
  # first root owns — normal install refuses (naming takeover-user-scope) and the
  # operator-explicit takeover is what moves the shared entry, old→new reported.
  local npmroot2="$npm_tmp/npmroot2" npmproj2="$npm_tmp/npmproj2" npm2_log two_root_out two_root_rc npm2_pkg
  mkdir -p "$npmroot2" "$npmproj2"
  npm2_log=$(cd "$npmroot2" && npm install "$tgz_path" --no-audit --no-fund 2>&1) || {
    fail "[check-pack-install] second npm root install failed:"
    echo "$npm2_log" | tail -10 | sed 's/^/    /' >&2
    return 1
  }
  npm2_pkg="$npmroot2/node_modules/@junghanacs/entwurf"
  set +e
  two_root_out=$(HOME="$npmhome" XDG_DATA_HOME="$npmhome/.local/share" XDG_STATE_HOME="$npmhome/.local/state" XDG_CACHE_HOME="$npmhome/.cache" "$npm2_pkg/run.sh" install "$npmproj2" 2>&1)
  two_root_rc=$?
  set -e
  if [ "$two_root_rc" -eq 0 ] || ! grep -q "takeover-user-scope" <<<"$two_root_out"; then
    fail "[check-pack-install] a second npm root's normal install must REFUSE the owned user-scope registration and name takeover-user-scope (rc=$two_root_rc):"
    echo "$two_root_out" | tail -10 | sed 's/^/    /' >&2
    return 1
  fi
  if ! python3 -c "
import json,sys
p=json.load(open('$npm_user_settings')).get('packages',[])
srcs=[(x if isinstance(x,str) else x.get('source')) for x in p]
ok_a=any(isinstance(s,str) and s.rstrip('/')== '$npm_pkg' for s in srcs)
bad_b=any(isinstance(s,str) and s.rstrip('/')== '$npm2_pkg' for s in srcs)
sys.exit(0 if ok_a and not bad_b else 1)
"; then
    fail "[check-pack-install] the refused second-root install still altered the user-scope packages[] entry:"
    sed 's/^/    /' "$npm_user_settings" >&2
    return 1
  fi
  set +e
  two_root_out=$(HOME="$npmhome" XDG_DATA_HOME="$npmhome/.local/share" XDG_STATE_HOME="$npmhome/.local/state" XDG_CACHE_HOME="$npmhome/.cache" "$npm2_pkg/run.sh" takeover-user-scope 2>&1)
  two_root_rc=$?
  set -e
  if [ "$two_root_rc" -ne 0 ] || ! grep -q "takeover: user-scope entwurf registration moved" <<<"$two_root_out"; then
    fail "[check-pack-install] explicit takeover-user-scope from the second root failed (rc=$two_root_rc):"
    echo "$two_root_out" | tail -10 | sed 's/^/    /' >&2
    return 1
  fi
  if ! python3 -c "
import json,sys
p=json.load(open('$npm_user_settings')).get('packages',[])
srcs=[(x if isinstance(x,str) else x.get('source')) for x in p]
ok_b=any(isinstance(s,str) and s.rstrip('/')== '$npm2_pkg' for s in srcs)
bad_a=any(isinstance(s,str) and s.rstrip('/')== '$npm_pkg' for s in srcs)
sys.exit(0 if ok_b and not bad_a else 1)
"; then
    fail "[check-pack-install] takeover did not move the user-scope entry old→new:"
    sed 's/^/    /' "$npm_user_settings" >&2
    return 1
  fi
  # #86 C2 amendment: BOTH ownership halves moved — the provider installerRoot must
  # now name the new root, and the OLD root's inverse must refuse (live foreign owner).
  if ! python3 -c "
import json,sys
st=json.load(open('$npmhome/.local/share/entwurf/pi-provider/install-state.json'))
sys.exit(0 if st.get('installerRoot','').rstrip('/')== '$npm2_pkg' else 1)
"; then
    fail "[check-pack-install] takeover did not rebind the provider installerRoot to the new root:"
    sed 's/^/    /' "$npmhome/.local/share/entwurf/pi-provider/install-state.json" >&2
    return 1
  fi
  set +e
  two_root_out=$(HOME="$npmhome" XDG_DATA_HOME="$npmhome/.local/share" XDG_STATE_HOME="$npmhome/.local/state" XDG_CACHE_HOME="$npmhome/.cache" "$npm_pkg/run.sh" remove-user-scope 2>&1)
  two_root_rc=$?
  set -e
  if [ "$two_root_rc" -eq 0 ] || ! python3 -c "
import json,sys
p=json.load(open('$npm_user_settings')).get('packages',[])
srcs=[(x if isinstance(x,str) else x.get('source')) for x in p]
sys.exit(0 if any(isinstance(s,str) and s.rstrip('/')== '$npm2_pkg' for s in srcs) else 1)
"; then
    fail "[check-pack-install] the OLD root's remove-user-scope must refuse after takeover (rc=$two_root_rc) and leave the new owner's entry intact:"
    echo "$two_root_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] two-root ownership row pass (second root: normal install refused naming takeover-user-scope; explicit takeover moved entry + provider installerRoot old->new; old root's inverse refused)"

  # Installed-package aggregate `setup` row (#86 C1, review blocker 2026-08-26):
  # the composed public command itself, driven through the consumer bin from the
  # SAME installed candidate, on a FRESH sandbox home with every harness absent.
  # This is the first living consumer of package-installed `entwurf setup`:
  # mode=installed decided by name before anything else, NO pnpm bootstrap inside
  # node_modules, pi/claude/agy explicit zero-state SKIPs, stable bins PASS as
  # npm-provided, core bridge boundary PASS, computed green, zero harness/auth
  # writes. Harness probes are pinned absent via the PI_BIN/CLAUDE_BIN/AGY_BIN/
  # COPILOT_BIN seams so the gate host's real harnesses never leak in.
  local setup_home="$npm_tmp/setuphome" setup_proj="$npm_tmp/setupproj" setup_out setup_rc setup_auth
  mkdir -p "$setup_home/.pi/agent" "$setup_proj"
  setup_auth="$setup_home/.pi/agent/auth.json"
  printf '{\n  "anthropic": {\n    "type": "oauth",\n    "access": "consumer-oauth-token"\n  }\n}\n' > "$setup_auth"
  local setup_auth_before
  setup_auth_before="$(sha256sum "$setup_auth" | cut -d' ' -f1)"
  set +e
  setup_out=$(HOME="$setup_home" XDG_DATA_HOME="$setup_home/.local/share" XDG_STATE_HOME="$setup_home/.local/state" \
    XDG_CACHE_HOME="$setup_home/.cache" XDG_CONFIG_HOME="$setup_home/.config" PI_CODING_AGENT_DIR="$setup_home/.pi/agent" \
    PI_BIN="$npm_tmp/definitely-absent" CLAUDE_BIN="$npm_tmp/definitely-absent" AGY_BIN="$npm_tmp/definitely-absent" \
    COPILOT_BIN="$npm_tmp/definitely-absent" \
    "$npmroot/node_modules/.bin/entwurf" setup "$setup_proj" 2>&1)
  setup_rc=$?
  set -e
  if [ "$setup_rc" -ne 0 ]; then
    fail "[check-pack-install] installed all-absent setup exited $setup_rc — core must stay green with every harness absent, and an installed package must never re-enter the source pnpm bootstrap:"
    echo "$setup_out" | tail -25 | sed 's/^/    /' >&2
    return 1
  fi
  if ! head -n 1 <<<"$setup_out" | grep -q "mode: installed package"; then
    fail "[check-pack-install] installed setup did not name its mode FIRST:"
    echo "$setup_out" | head -5 | sed 's/^/    /' >&2
    return 1
  fi
  if grep -Eqi "pnpm install|Lockfile is up to date|Progress: resolved" <<<"$setup_out"; then
    fail "[check-pack-install] installed setup reached the source pnpm bootstrap inside node_modules:"
    echo "$setup_out" | grep -Ei "pnpm|Lockfile|Progress" | sed 's/^/    /' >&2
    return 1
  fi
  local skip_probe
  for skip_probe in "pi: SKIP" "claude: SKIP" "agy: SKIP" "copilot: SKIP"; do
    if ! grep -q "$skip_probe" <<<"$setup_out"; then
      fail "[check-pack-install] installed all-absent setup missing explicit zero-state '$skip_probe':"
      echo "$setup_out" | tail -25 | sed 's/^/    /' >&2
      return 1
    fi
  done
  if ! grep -q "bins: PASS — provided by npm bin linking" <<<"$setup_out"; then
    fail "[check-pack-install] installed setup must report stable bins PASS as npm-provided (capability present, not absent):"
    echo "$setup_out" | tail -25 | sed 's/^/    /' >&2
    return 1
  fi
  if ! grep -q "core: PASS" <<<"$setup_out" || ! grep -q "result: green (computed from the component outcomes above)" <<<"$setup_out"; then
    fail "[check-pack-install] installed setup core/computed-green missing:"
    echo "$setup_out" | tail -25 | sed 's/^/    /' >&2
    return 1
  fi
  if [ -e "$setup_proj/.pi" ] || [ -e "$setup_home/.pi/agent/settings.json" ] || [ -e "$setup_home/.gemini" ] || [ -e "$setup_home/.copilot" ]; then
    fail "[check-pack-install] installed all-absent setup wrote harness state (must be zero-write)"
    return 1
  fi
  if [ "$(sha256sum "$setup_auth" | cut -d' ' -f1)" != "$setup_auth_before" ] || [ -e "$setup_auth.bak" ]; then
    fail "[check-pack-install] installed setup touched the credential store (byte drift or .bak)"
    return 1
  fi
  echo "[check-pack-install] installed all-absent setup pass (mode-first, no bootstrap, 4x SKIP, bins npm-provided, core PASS, computed green, zero writes)"

  # Installed copilot-present aggregate `setup` row (#86 C3b): the SAME consumer
  # bin on a fresh sandbox home, with the shared fake vendor
  # (scripts/fake-copilot-vendor.sh) on PATH. The presence-driven composition
  # must run all FOUR Copilot units from the installed package: birth assembles
  # the COMPILED hook (no raw .ts under node_modules) and drives the real
  # marketplace-add→plugin-install sequence, MCP + receiver + footer land their
  # configs/units in the sandbox, each unit keeps its package-owned
  # install-state (its inverse authority), and the verdict is computed green.
  local cop_setup_home="$npm_tmp/copsetuphome" cop_setup_proj="$npm_tmp/copsetupproj" cop_fake="$npm_tmp/fake-copilot-vendor"
  mkdir -p "$cop_setup_home/.pi/agent" "$cop_setup_proj"
  printf '{\n  "anthropic": {\n    "type": "oauth",\n    "access": "consumer-oauth-token"\n  }\n}\n' > "$cop_setup_home/.pi/agent/auth.json"
  local cop_auth_before
  cop_auth_before="$(sha256sum "$cop_setup_home/.pi/agent/auth.json" | cut -d' ' -f1)"
  # EXECUTED, never sourced: this impl holds a `trap … RETURN`, and bash fires a
  # RETURN trap when a sourced script finishes — a `. factory` here deleted the
  # whole npm sandbox mid-gate (measured 2026-08-27, C3b review).
  bash "$REPO_DIR/scripts/fake-copilot-vendor.sh" "$cop_fake" "$npm_pkg/pi/meta-bridge-copilot/entwurf-meta-receive-copilot/.claude-plugin/plugin.json" || {
    fail "[check-pack-install] could not build the fake copilot vendor from the PACKED plugin.json (is pi/meta-bridge-copilot missing from the tarball?)"
    return 1
  }
  set +e
  setup_out=$(HOME="$cop_setup_home" XDG_DATA_HOME="$cop_setup_home/.local/share" XDG_STATE_HOME="$cop_setup_home/.local/state" \
    XDG_CACHE_HOME="$cop_setup_home/.cache" XDG_CONFIG_HOME="$cop_setup_home/.config" PI_CODING_AGENT_DIR="$cop_setup_home/.pi/agent" \
    PI_BIN="$npm_tmp/definitely-absent" CLAUDE_BIN="$npm_tmp/definitely-absent" AGY_BIN="$npm_tmp/definitely-absent" \
    COPILOT_BIN="$cop_fake/copilot" PATH="$cop_fake:$npmroot/node_modules/.bin:$PATH" \
    "$npmroot/node_modules/.bin/entwurf" setup "$cop_setup_proj" 2>&1)
  setup_rc=$?
  set -e
  if [ "$setup_rc" -ne 0 ]; then
    fail "[check-pack-install] installed copilot-present setup exited $setup_rc — the four-unit composition must be green against the fake vendor:"
    echo "$setup_out" | tail -30 | sed 's/^/    /' >&2
    return 1
  fi
  local cop_row
  for cop_row in "copilot-birth: PASS" "copilot-mcp: PASS" "copilot-receive: PASS" "copilot-statusline: PASS"; do
    if ! grep -q "$cop_row" <<<"$setup_out"; then
      fail "[check-pack-install] installed copilot-present setup missing unit verdict '$cop_row':"
      echo "$setup_out" | tail -30 | sed 's/^/    /' >&2
      return 1
    fi
  done
  if ! grep -q "result: green (computed from the component outcomes above)" <<<"$setup_out"; then
    fail "[check-pack-install] installed copilot-present setup did not compute green:"
    echo "$setup_out" | tail -10 | sed 's/^/    /' >&2
    return 1
  fi
  local cop_setup_asm="$cop_setup_home/.local/share/entwurf/meta-bridge-copilot/.assembled/entwurf-meta-receive-copilot"
  if [ ! -f "$cop_setup_asm/meta-bridge-hook-copilot.js" ] || [ -f "$cop_setup_asm/meta-bridge-hook-copilot.ts" ]; then
    fail "[check-pack-install] installed copilot-present setup did not assemble the compiled birth hook (want meta-bridge-hook-copilot.js, no raw .ts) in $cop_setup_asm"
    return 1
  fi
  if ! grep -q "^plugin marketplace add " "$cop_fake/calls.log" || ! grep -q "^plugin install entwurf-meta-receive-copilot@meta-bridge-copilot-local$" "$cop_fake/calls.log"; then
    fail "[check-pack-install] installed copilot-present setup did not drive the vendor sequence (marketplace add + plugin install) — calls:"
    sed 's/^/    /' "$cop_fake/calls.log" >&2
    return 1
  fi
  if [ ! -f "$cop_setup_home/.copilot/extensions/entwurf-receive/extension.mjs" ] || [ ! -f "$cop_setup_home/.copilot/extensions/entwurf-receive/lib/meta-session.js" ]; then
    fail "[check-pack-install] installed copilot-present setup did not deploy the receiver unit from the shipped dist closure"
    return 1
  fi
  if ! grep -q "entwurf-bridge" "$cop_setup_home/.copilot/mcp-config.json" || ! grep -q "entwurf-copilot-statusline" "$cop_setup_home/.copilot/settings.json"; then
    fail "[check-pack-install] installed copilot-present setup did not land the MCP config / footer settings in the sandbox home"
    return 1
  fi
  local cop_state
  for cop_state in copilot-bridge copilot-mcp copilot-receive copilot-statusline; do
    if [ ! -f "$cop_setup_home/.local/share/entwurf/$cop_state/install-state.json" ]; then
      fail "[check-pack-install] installed copilot-present setup left no package-owned install-state for $cop_state (its inverse authority)"
      return 1
    fi
  done
  if [ "$(sha256sum "$cop_setup_home/.pi/agent/auth.json" | cut -d' ' -f1)" != "$cop_auth_before" ] || [ -e "$cop_setup_home/.pi/agent/auth.json.bak" ]; then
    fail "[check-pack-install] installed copilot-present setup touched the credential store (byte drift or .bak)"
    return 1
  fi
  echo "[check-pack-install] installed copilot-present setup pass (four units PASS with install-states, compiled birth hook, vendor sequence driven, computed green, credentials untouched)"

  # Installed meta-bridge ownership regression (0.12.5): package upgrades must not
  # bake versioned pnpm-store paths into Claude settings. MCP already uses the
  # stable `entwurf-bridge` bin; statusLine must now use `entwurf-statusline`, and
  # the plugin marketplace source must be the version-stable operator data dir
  # rather than <node_modules>/pi/meta-bridge/.assembled. Use a fake claude CLI so
  # this stays deterministic/offline while running the REAL installed
  # install-meta-bridge path and meta-bridge-state apply.
  local fake_claude_dir="$npm_tmp/fake-claude-bin" fake_claude_log="$npm_tmp/fake-claude.log"
  mkdir -p "$fake_claude_dir"
  cat > "$fake_claude_dir/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_CLAUDE_LOG:?}"
case "$1${2:+ $2}" in
  "--version") echo "2.1.217 (Claude Code)" ;;
  "plugin validate") : ;;
  "plugin uninstall") : ;;
  "plugin marketplace") : ;;
  "plugin install") : ;;
  "plugin list") printf '%s\n' "entwurf-meta-receive@meta-bridge-local" "  Status: enabled" ;;
  "mcp remove") : ;;
  "mcp add") : ;;
  "mcp get") printf '%s\n' "Scope: User config" "Status: ✔ Connected" ;;
  *) : ;;
esac
exit 0
SH
  chmod +x "$fake_claude_dir/claude"
  local mb_home="$npm_tmp/meta-home" mb_cfg="$npm_tmp/meta-claude" mb_log
  mkdir -p "$mb_home" "$mb_cfg"
  mb_log=$(HOME="$mb_home" XDG_DATA_HOME="$mb_home/.local/share" XDG_STATE_HOME="$mb_home/.local/state" XDG_CACHE_HOME="$mb_home/.cache" CLAUDE_CONFIG_DIR="$mb_cfg" FAKE_CLAUDE_LOG="$fake_claude_log" PATH="$fake_claude_dir:$npmroot/node_modules/.bin:$PATH" "$npm_pkg/run.sh" install-meta-bridge 2>&1) || {
    fail "[check-pack-install] installed install-meta-bridge failed under fake claude:"
    echo "$mb_log" | tail -20 | sed 's/^/    /' >&2
    return 1
  }
  local stable_asm="$mb_home/.local/share/entwurf/meta-bridge/.assembled"
  local installed_hook="$stable_asm/entwurf-meta-receive/meta-bridge-hook.js"
  if [ ! -f "$installed_hook" ]; then
    fail "[check-pack-install] installed meta-bridge did not assemble the compiled hook JS into the stable operator data dir: $installed_hook"
    return 1
  fi
  if [ -f "$stable_asm/entwurf-meta-receive/meta-bridge-hook.ts" ]; then
    fail "[check-pack-install] installed meta-bridge shipped a raw .ts hook — installed packages must run compiled JS (strip-types is refused under node_modules)"
    return 1
  fi
  # The artifact existing is not enough (review BLOCKER 1): Claude runs the hooks.json
  # COMMAND, so assert the baked command actually targets the compiled .js with both
  # placeholders resolved. A bake that mis-targeted .ts (or left a placeholder) would
  # still pass the direct-JS smoke below, then fail live.
  local installed_hooks_json="$stable_asm/entwurf-meta-receive/hooks/hooks.json"
  if ! grep -q 'meta-bridge-hook\.js' "$installed_hooks_json"; then
    fail "[check-pack-install] installed hooks.json does not point at the compiled meta-bridge-hook.js: $installed_hooks_json"
    return 1
  fi
  if grep -qE 'meta-bridge-hook\.ts|__HOOK_ENTRY__|__NODE_BIN__' "$installed_hooks_json"; then
    fail "[check-pack-install] installed hooks.json references a raw .ts entry or an unbaked placeholder (__HOOK_ENTRY__/__NODE_BIN__): $installed_hooks_json"
    return 1
  fi
  # Exec-form launch contract on all three owner hooks: `command` is the shipped
  # launcher and the baked entry travels in `args`. Counting the launcher alone would
  # pass a manifest whose args were emptied, so require the pair on the same leaf.
  if [ "$(grep -c 'scripts/hook-launch\.sh' "$installed_hooks_json" || true)" -ne 4 ]; then
    fail "[check-pack-install] installed hooks.json does not route all 4 hooks (3 owner + FileChanged) through the shipped hook-launch.sh: $installed_hooks_json"
    return 1
  fi
  if [ "$(grep -c 'meta-bridge-hook\.js"' "$installed_hooks_json" || true)" -ne 3 ]; then
    fail "[check-pack-install] installed hooks.json lost the baked hook entry in the exec-form args on one of SessionStart/CwdChanged/UserPromptSubmit: $installed_hooks_json"
    return 1
  fi
  if grep -q 'ENTWURF_META_HOOK_OWNER_PID' "$installed_hooks_json"; then
    fail "[check-pack-install] installed hooks.json still carries the RETIRED shell-\$PPID owner carrier: $installed_hooks_json"
    return 1
  fi
  if [ ! -x "$stable_asm/entwurf-meta-receive/scripts/hook-launch.sh" ]; then
    fail "[check-pack-install] assembled hook-launch.sh is missing or not executable — the exec form names it as the executable, so a lost +x bit is ENOEXEC at session open"
    return 1
  fi
  if [ -e "$npm_pkg/pi/meta-bridge/.assembled/entwurf-meta-receive" ]; then
    fail "[check-pack-install] installed meta-bridge still assembled inside the versioned package store: $npm_pkg/pi/meta-bridge/.assembled"
    return 1
  fi
  # 0.12.5 strip-types-fence regression (GPT safety pin). The compiled hook must run
  # FROM UNDER node_modules with plain node — the exact fence that broke oracle's
  # 0.12.4 raw-.ts hook (ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING). L2 relocates
  # the runtime marketplace source to XDG, but this hardens the ARTIFACT itself so
  # it is safe even if a future cache/marketplace path lands under node_modules.
  local nm_probe="$npmroot/node_modules/@junghanacs/entwurf/pi/meta-bridge/.assembled-packprobe/entwurf-meta-receive"
  mkdir -p "$nm_probe/lib"
  cp "$installed_hook" "$nm_probe/meta-bridge-hook.js"
  cp "$stable_asm/entwurf-meta-receive/lib/meta-session.js" "$nm_probe/lib/meta-session.js"
  cp "$stable_asm/entwurf-meta-receive/lib/session-id.js" "$nm_probe/lib/session-id.js"
  cp "$stable_asm/entwurf-meta-receive/entwurf-capabilities.json" "$nm_probe/entwurf-capabilities.json"
  local probe_env='{"session_id":"pack-probe","transcript_path":"/tmp/x.jsonl","cwd":"/tmp","hook_event_name":"SessionStart","model":{"id":"probe"}}'
  local probe_out
  if probe_out="$(printf '%s' "$probe_env" | env PI_CODING_AGENT_DIR="$(mktemp -d)" CLAUDE_PLUGIN_ROOT="$nm_probe" node "$nm_probe/meta-bridge-hook.js" 2>&1)" && printf '%s' "$probe_out" | grep -q hookSpecificOutput; then
    : # compiled hook crosses the node_modules strip-types fence safely
  else
    fail "[check-pack-install] compiled hook failed to run under node_modules with plain node: $(printf '%s' "$probe_out" | tr '\n' ' ' | cut -c1-200)"
    rm -rf "$nm_probe"; return 1
  fi
  # FAIL-reproduction (review BLOCKER 2): a raw .ts at the SAME node_modules location
  # must be refused SPECIFICALLY by the strip-types fence — not by some unrelated
  # failure. A missing lib would also exit nonzero and hollow out the proof, so
  # capture stderr and require the exact ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING.
  cp "$npm_pkg/pi-extensions/meta-bridge-hook.ts" "$nm_probe/meta-bridge-hook.ts"
  local ts_out ts_rc
  ts_out="$(printf '%s' "$probe_env" | env PI_CODING_AGENT_DIR="$(mktemp -d)" CLAUDE_PLUGIN_ROOT="$nm_probe" node "$nm_probe/meta-bridge-hook.ts" 2>&1)" && ts_rc=0 || ts_rc=$?
  if [ "${ts_rc:-0}" -eq 0 ]; then
    fail "[check-pack-install] raw .ts hook UNEXPECTEDLY ran under node_modules — strip-types fence moved; the compiled-hook rationale must be revisited"
    rm -rf "$nm_probe"; return 1
  fi
  if ! printf '%s' "$ts_out" | grep -q 'ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING'; then
    fail "[check-pack-install] raw .ts hook failed under node_modules but NOT via the strip-types fence (expected ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING); got: $(printf '%s' "$ts_out" | tr '\n' ' ' | cut -c1-200) — the regression no longer proves the compiled-hook rationale"
    rm -rf "$nm_probe"; return 1
  fi
  rm -rf "$nm_probe"
  echo "[check-pack-install] installed hook is node_modules-safe compiled JS (hooks.json points at .js; runs under node_modules with plain node; raw .ts refused there by the strip-types fence)"

  # --- #82: the Copilot birth unit's INSTALLED-PACKAGE branch ------------------
  # check-copilot-birth-hook drives the installer from a DEV CLONE, so it only ever
  # exercises the `.ts` branch. The installed-package branch — compiled
  # meta-bridge-hook-copilot.js, its rewritten `./lib/meta-session.js` import, the
  # registry copied to the plugin root — was covered by pack LISTS and by nothing that
  # RUNS it, which is the shape Hard Rule 11 exists to refuse (cross-review, terra +
  # glm independently, 2026-08-21).
  #
  # `--assemble-only` stops before the Copilot CLI, so this needs no Copilot and no fake
  # of one. A fake Copilot CLI would only prove our script calls our fake the way we
  # wrote it — the vendor contract is unmeasured, and the first real execution is the
  # §6 admission itself. This asserts the CITIZEN, not merely that a node process ran.
  local cop_asm="$npm_tmp/copilot-asm" cop_store cop_log
  cop_store="$(mktemp -d)"
  if ! cop_log=$(HOME="$mb_home" XDG_DATA_HOME="$mb_home/.local/share" ENTWURF_COPILOT_ASM="$cop_asm" PATH="$npmroot/node_modules/.bin:$PATH" "$npm_pkg/run.sh" install-copilot-bridge --assemble-only 2>&1); then
    fail "[check-pack-install] installed install-copilot-bridge --assemble-only failed:"
    echo "$cop_log" | tail -20 | sed 's/^/    /' >&2
    return 1
  fi
  local cop_unit="$cop_asm/entwurf-meta-receive-copilot"
  # Branch SELECTION, pinned: an installed package must assemble the compiled entry and
  # no raw .ts. Without this the fire below could pass on a layout that silently chose
  # the dev-clone branch.
  if [ ! -f "$cop_unit/meta-bridge-hook-copilot.js" ] || [ -f "$cop_unit/meta-bridge-hook-copilot.ts" ]; then
    fail "[check-pack-install] installed install-copilot-bridge did not select the compiled branch (want meta-bridge-hook-copilot.js, no raw .ts) in $cop_unit"
    return 1
  fi
  local cop_out
  # Fired the way Copilot fires it: NO ARGV, envelope on stdin.
  if ! cop_out="$(printf '%s' '{"sessionId":"pack-copilot-probe","cwd":"/tmp","source":"new"}' | env PI_CODING_AGENT_DIR="$cop_store" "$cop_unit/scripts/copilot-hook-launch.sh" 2>&1)"; then
    fail "[check-pack-install] the installed Copilot launcher failed: $(printf '%s' "$cop_out" | tr '\n' ' ' | cut -c1-200)"
    return 1
  fi
  local cop_records
  cop_records="$(grep -l '"backend": "copilot"' "$cop_store"/meta-sessions/*.meta.json 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$cop_records" != "1" ]; then
    fail "[check-pack-install] the installed Copilot unit did not mint exactly one copilot citizen (found ${cop_records:-0}); log: $(tail -1 "$cop_store/meta-bridge-hook.log" 2>/dev/null)"
    return 1
  fi
  rm -rf "$cop_store"
  echo "[check-pack-install] installed Copilot birth unit assembles its compiled branch and mints a citizen from a no-argv launch"

  # --- #87: the OMP birth unit's INSTALLED-PACKAGE branch ---------------------
  # Same shape and same reason as the Copilot cell above, and it is here because the gap it
  # closes was REAL, not theoretical: the compiled entry this installer selects under
  # node_modules was in no emit include and no artifact list, so `entwurf install-omp-bridge`
  # — which docs/setup-clean-host.md tells operators to run — died at its own artifact check
  # on every installed host while every gate stayed green (Terra amendment review, #87 A1).
  # The list entries above make that artifact's ABSENCE loud; this RUNS it, which is the half
  # Hard Rule 11 says a list can never stand in for.
  #
  # No omp binary is faked into doing anything: the installer only asks whether one is on
  # PATH (entwurf never installs a harness), and the unit is a module the vendor imports, not
  # a process we launch — so the exercise imports the placed artifact the way omp does.
  local omp_agent="$npm_tmp/omp-agent" omp_home="$npm_tmp/omp-home" omp_bin="$npm_tmp/omp-bin" omp_log
  mkdir -p "$omp_agent" "$omp_home" "$omp_bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$omp_bin/omp"
  chmod +x "$omp_bin/omp"
  if ! omp_log=$(HOME="$omp_home" XDG_DATA_HOME="$omp_home/.local/share" ENTWURF_OMP_AGENT_DIR="$omp_agent" PATH="$omp_bin:$npmroot/node_modules/.bin:$PATH" "$npm_pkg/run.sh" install-omp-bridge 2>&1); then
    fail "[check-pack-install] installed install-omp-bridge failed:"
    echo "$omp_log" | tail -20 | sed 's/^/    /' >&2
    return 1
  fi
  local omp_unit="$omp_agent/extensions/entwurf-meta-omp"
  # Branch SELECTION, pinned exactly as the Copilot cell pins its own: an installed package
  # must place the compiled entry and NO raw .ts, or the fire below could pass on a layout
  # that silently chose the dev-clone branch.
  if [ ! -f "$omp_unit/index.js" ] || [ -f "$omp_unit/index.ts" ]; then
    fail "[check-pack-install] installed install-omp-bridge did not select the compiled branch (want index.js, no raw .ts) in $omp_unit"
    ls -l "$omp_unit" 2>/dev/null | sed 's/^/    /' >&2 || true
    return 1
  fi
  if [ ! -f "$omp_unit/lib/meta-session.js" ] || [ ! -f "$omp_unit/entwurf-capabilities.json" ] || [ ! -f "$omp_unit/package.json" ]; then
    fail "[check-pack-install] installed omp unit is incomplete (want lib/meta-session.js + entwurf-capabilities.json + package.json) in $omp_unit"
    return 1
  fi
  # Fired the way omp fires it: import the module, call the exported factory with a mock
  # ExtensionAPI, and hand the tui host context to the birth edge.
  local omp_fire
  if ! omp_fire=$(OMP_UNIT="$omp_unit" HOME="$omp_home" node --input-type=module <<'JS' 2>&1
const mod = await import(process.env.OMP_UNIT + "/index.js");
const handlers = [];
(mod.default ?? mod)({ on: (event, handler) => { if (event === "session_start") handlers.push(handler); } });
const ctx = {
  mode: "tui",
  cwd: "/tmp",
  ui: { setStatus: () => {} },
  sessionManager: { getSessionId: () => "pack-omp-probe", getCwd: () => "/tmp", getSessionFile: () => null },
};
for (const handler of handlers) await handler({ type: "session_start" }, ctx);
process.stdout.write("fired " + handlers.length + "\n");
JS
  ); then
    fail "[check-pack-install] the installed omp unit failed to import/run from its placed location: $(printf '%s' "$omp_fire" | tr '\n' ' ' | cut -c1-300)"
    return 1
  fi
  # Counted through the OWNER's certified projection, not a grep — and through the INSTALLED
  # bin, so this also proves dist/scripts/meta-facts.js is reachable from a consumer. `env -u
  # PI_CODING_AGENT_DIR` is the omp root policy: for backend omp that variable is the vendor's
  # own agent dir and never a garden root (#87 B1).
  local omp_citizens
  omp_citizens=$(env -u PI_CODING_AGENT_DIR HOME="$omp_home" "$npm_pkg/run.sh" meta-facts 2>&1 | python3 -c '
import json, sys
facts = json.load(sys.stdin)
print(sum(1 for c in (facts.get("citizens") or []) if c.get("backend") == "omp"))
' 2>/dev/null) || omp_citizens=""
  if [ "$omp_citizens" != "1" ]; then
    fail "[check-pack-install] the installed omp unit did not mint exactly one CERTIFIED omp citizen (found ${omp_citizens:-<unreadable>}); log: $(tail -1 "$omp_home/.pi/agent/meta-bridge-hook.log" 2>/dev/null)"
    return 1
  fi
  echo "[check-pack-install] installed OMP birth unit places its compiled branch and mints a certified citizen from a tui birth edge"
  python3 - "$mb_cfg/settings.json" "$mb_home/.claude.json" "$stable_asm" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
root = json.load(open(sys.argv[2]))
stable_asm = sys.argv[3]
market = settings.get("extraKnownMarketplaces", {}).get("meta-bridge-local", {})
assert market == {"source": {"source": "directory", "path": stable_asm}}, market
assert settings.get("statusLine") == {"type": "command", "command": "entwurf-statusline"}, settings.get("statusLine")
mcp = root.get("mcpServers", {}).get("entwurf-bridge", {})
assert mcp.get("command") == "entwurf-bridge" and mcp.get("args") == [], mcp
PY
  if ! grep -q "$stable_asm" "$fake_claude_log"; then
    fail "[check-pack-install] fake claude did not receive the stable marketplace path during install-meta-bridge"
    sed 's/^/    /' "$fake_claude_log" >&2 || true
    return 1
  fi
  echo "[check-pack-install] installed meta-bridge ownership pass (stable statusline bin + stable marketplace dir + stable MCP bin)"

  # 0.12.1 C — installed bridge BOOT regression. This is the test whose absence
  # let the 0.12.0 install bug ship: the README's bridge launcher was
  # `node --experimental-strip-types src/index.ts`, which Node REFUSES under
  # node_modules (ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING). Every gate above
  # wired settings or probed shape but never BOOTED the bridge from its installed
  # node_modules home, so the dead-on-arrival MCP server passed publish. Here we
  # boot the installed start.sh and assert it answers MCP tools/list with the v2
  # surface. Two proofs in one: (1) the prepack dist JS boots under node_modules
  # with plain node — a strip-types fallback would crash with the exact error
  # above, so a parseable tools/list IS proof the dist path was taken; (2) the
  # boot is pi-free — the @earendil-works peer trio is optional and must NOT be
  # installed by the neutral npm path, so the eager closure stands up with pi absent.
  local installed_start="$npmroot/node_modules/.bin/entwurf-bridge"
  local installed_dist="$npm_pkg/mcp/entwurf-bridge/dist/mcp/entwurf-bridge/src/index.js"
  if [ ! -f "$installed_dist" ]; then
    fail "[check-pack-install] installed bridge missing prebuilt dist (prepack did not emit into the tarball?): $installed_dist"
    return 1
  fi
  if [ -d "$npmroot/node_modules/@earendil-works" ]; then
    fail "[check-pack-install] @earendil-works present in npm-managed node_modules — pi-free boot proof is void (neutral npm install should not install optional pi peers)"
    return 1
  fi
  local boot_out
  if ! boot_out=$(START_SH="$installed_start" node --input-type=module <<'JS'
import { spawn } from 'node:child_process';
const start = process.env.START_SH;
// Sanitize the child env so the pi-free proof cannot be masked by a leaked
// module-resolution path: if NODE_PATH (or a stray pi env) pointed at a tree
// holding @earendil-works, a statically pi-importing eager graph could resolve
// and boot anyway, turning this gate falsely green. Strip it so "boots with
// @earendil absent" stays an honest adversarial proof.
const env = { ...process.env };
delete env.NODE_PATH;
const child = spawn(start, { stdio: ['pipe', 'pipe', 'pipe'], env });
let stdout = '', stderr = '', done = false;
const timer = setTimeout(() => {
  child.kill('SIGKILL');
  console.error('installed bridge boot timeout');
  if (stderr.trim()) console.error(stderr.trim());
  process.exit(1);
}, 5000);
function finish(trimmed) {
  if (done) return;
  done = true;
  clearTimeout(timer);
  let msg;
  try { msg = JSON.parse(trimmed); }
  catch { console.error('unparseable tools/list:', trimmed.slice(0, 300)); if (stderr.trim()) console.error(stderr.trim()); process.exit(1); }
  const names = (msg?.result?.tools ?? []).map((t) => t?.name).sort();
  // EXACT set, not a floor. The subset form of this assertion named only the five
  // pre-0.14 verbs, so an ARTIFACT whose bridge boots and answers but carries an older
  // emitted surface — no entwurf_fresh_call, no entwurf_resume_call — passed the very
  // gate that exists to catch "green clone, dead consumer". Equality also catches the
  // other direction the narrow-surface rule cares about: an extra or duplicated verb
  // reaching hosts without a decision. Written sorted; `names` is sorted above.
  const EXPECT_TOOLS = ['entwurf_fresh_call', 'entwurf_inbox_read', 'entwurf_peers', 'entwurf_register_native', 'entwurf_resume_call', 'entwurf_self', 'entwurf_v2'];
  if (names.length !== EXPECT_TOOLS.length || EXPECT_TOOLS.some((n, i) => names[i] !== n)) {
    console.error('installed MCP tool set MISMATCH — want exactly [' + EXPECT_TOOLS.join(',') + '] got [' + names.join(',') + ']');
    process.exit(1);
  }
  console.log(names.join(','));
  child.kill('SIGTERM');
  process.exit(0);
}
child.stdout.on('data', (d) => { stdout += d.toString(); const t = stdout.trim(); if (t) finish(t); });
child.stderr.on('data', (d) => { stderr += d.toString(); });
child.on('error', (e) => { clearTimeout(timer); console.error('installed bridge spawn error:', String(e)); process.exit(1); });
child.on('close', () => { if (done) return; clearTimeout(timer); if (stderr.trim()) console.error(stderr.trim()); console.error('installed bridge closed with empty tools/list'); process.exit(1); });
child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }) + '\n');
JS
  ); then
    fail "[check-pack-install] installed bridge boot FAILED — the npm-installed MCP server does not answer tools/list (the 0.12.0 strip-types-under-node_modules regression):"
    echo "$boot_out" | tail -15 | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] installed bridge boot pass (dist boots under node_modules, pi-free: $boot_out)"

  # 0.12.8 — installed bridge DELIVERY regression. The boot probe above stops at
  # tools/list, and so did every other artifact gate: `entwurf_v2` had never once been
  # CALLED through a shipped bundle. That blind spot shipped a DEAD send path from the
  # birth of the dist (0.12.1) through 0.12.8-repair.0 — the bundle carried no
  # capability registry, so every real send died `ENOENT entwurf-capabilities.json`
  # while the registry-free verbs (entwurf_self/entwurf_peers) stayed green and hid it.
  # Had this probe existed, that corpse would have been RED at the first pack.
  #
  # Same scene as check-bridge-delivery, different cell: there the subject is the
  # checkout's dist, here it is THIS npm-installed tree — peer-free, hoisted deps, the
  # globally installed consumer world — driven through the installed BIN, so start.sh's node_modules→dist
  # branch is itself under test rather than bypassed. The gate seeds strict sender +
  # receiver citizens from repo source in a separate process and asserts the .msg
  # physically landed under that sender; the env-isolated temp world
  # (PI_CODING_AGENT_DIR + every ENTWURF_META_* root + ENTWURF_DIR, with ambient
  # pi/sender carriers and NODE_PATH stripped) lives inside it. No model, no network.
  # HOME/XDG are the sandbox roots this function already uses, so the drive cannot read
  # the operator's real store (rule 11).
  local delivery_out
  if ! delivery_out=$(HOME="$npmhome" XDG_DATA_HOME="$npmhome/.local/share" XDG_STATE_HOME="$npmhome/.local/state" XDG_CACHE_HOME="$npmhome/.cache" ENTWURF_DELIVERY_SUBJECT="$installed_start" run_ts scripts/check-bridge-delivery.ts 2>&1); then
    fail "[check-pack-install] installed bridge DELIVERY failed — the npm-installed MCP server boots but cannot deliver an entwurf_v2 send (the 0.12.1→0.12.8-repair.0 registry corpse):"
    echo "$delivery_out" | tail -20 | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] installed bridge delivery pass (tools/call entwurf_v2 through the installed bin landed a .msg)"

  # 0.12.7 — installed AGY IMPRINT regression. The npm bin resolves through a
  # node_modules symlink; raw scripts/agy-imprint.ts is therefore forbidden by
  # Node's strip-types fence. Execute the real installed bin with an isolated
  # agent dir and prove the neutral hook response + one record write. This is the
  # exact package bug that a dev-only hook smoke cannot see.
  local installed_agy_imprint="$npmroot/node_modules/.bin/entwurf-agy-imprint"
  local agy_imprint_agent="$npm_tmp/agy-imprint-agent" agy_imprint_out agy_record_count
  mkdir -p "$agy_imprint_agent"
  if ! agy_imprint_out=$(printf '%s\n' '{"conversationId":"pack-install-agy-conversation","workspacePaths":["/tmp/entwurf-pack-install"],"modelName":"probe-model"}' | HOME="$npmhome" XDG_DATA_HOME="$npmhome/.local/share" XDG_STATE_HOME="$npmhome/.local/state" XDG_CACHE_HOME="$npmhome/.cache" PI_CODING_AGENT_DIR="$agy_imprint_agent" "$installed_agy_imprint" 2>&1); then
    fail "[check-pack-install] installed entwurf-agy-imprint FAILED under node_modules (raw-.ts strip-types regression or emitted hook missing):"
    echo "$agy_imprint_out" | tail -15 | sed 's/^/    /' >&2
    return 1
  fi
  if [ "$agy_imprint_out" != '{"injectSteps":[]}' ]; then
    fail "[check-pack-install] installed entwurf-agy-imprint returned a non-neutral hook response: $agy_imprint_out"
    return 1
  fi
  agy_record_count=$(find "$agy_imprint_agent/meta-sessions" -maxdepth 1 -name '*.meta.json' -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$agy_record_count" != "1" ]; then
    fail "[check-pack-install] installed entwurf-agy-imprint did not write exactly one isolated meta-record (got $agy_record_count)"
    return 1
  fi
  echo "[check-pack-install] installed agy imprint pass (compiled JS runs under node_modules; neutral response + record write)"

  # 0.12.7 — installed OPERATOR COMMAND regression. `entwurf <cmd>` dispatches through
  # run.sh, whose REPO_DIR is under node_modules once installed, so a raw-.ts entrypoint
  # dies on the strip-types fence. These three are operator surfaces, not dev gates:
  # doctor-pi-provider is the pi-ownership verdict, new-session-id is the alias that mints
  # a garden citizen (docs/setup-clean-host.md tells operators to run the installed bin),
  # and meta-bridge-prune is the store maintenance verb. All three shipped DEAD through
  # 0.12.6 because the only installed smokes drove bins, never subcommands.
  #
  # Assert MEANING, not just the absence of the fence string: a command that regressed to
  # a stub or an empty exit would still "not crash". So: the id must be well-formed, the
  # doctor must reach its own verdict body, and prune must actually walk a 0-record store.
  local installed_entwurf="$npmroot/node_modules/.bin/entwurf"
  local op_agent="$npm_tmp/op-agent" op_out
  mkdir -p "$op_agent/meta-sessions"

  # Same sandbox root set on every operator-command drive: doctor-pi-provider READS install-state
  # below XDG_DATA_HOME, so an inherited real root would make this gate's verdict depend on the
  # operator's host instead of the sandbox (non-hermetic even when nothing is written).
  local op_xdg_data="$npmhome/.local/share" op_xdg_state="$npmhome/.local/state" op_xdg_cache="$npmhome/.cache"
  if ! op_out=$(HOME="$npmhome" XDG_DATA_HOME="$op_xdg_data" XDG_STATE_HOME="$op_xdg_state" XDG_CACHE_HOME="$op_xdg_cache" PI_CODING_AGENT_DIR="$op_agent" "$installed_entwurf" new-session-id 2>&1); then
    fail "[check-pack-install] installed 'entwurf new-session-id' FAILED under node_modules (strip-types fence or missing compiled twin):"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi
  # Same shape as SESSION_ID_RE (the garden id SSOT): <denote-stamp>-<6 hex>. A stub or a
  # truncated id would still "not crash", so the gate reads the id, not just the exit code.
  if ! printf '%s' "$op_out" | grep -qE '^[0-9]{8}T[0-9]{6}-[0-9a-f]{6}$'; then
    fail "[check-pack-install] installed 'entwurf new-session-id' did not print a well-formed garden session id: $op_out"
    return 1
  fi

  if ! op_out=$(HOME="$npmhome" XDG_DATA_HOME="$op_xdg_data" XDG_STATE_HOME="$op_xdg_state" XDG_CACHE_HOME="$op_xdg_cache" PI_CODING_AGENT_DIR="$op_agent" "$installed_entwurf" doctor-pi-provider 2>&1); then
    # A doctor may exit non-zero on an unadopted host — that is a VERDICT, not a crash.
    # The fence, by contrast, kills it before any verdict body is printed.
    if printf '%s' "$op_out" | grep -q ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING; then
      fail "[check-pack-install] installed 'entwurf doctor-pi-provider' hit the node_modules strip-types fence:"
      echo "$op_out" | tail -8 | sed 's/^/    /' >&2
      return 1
    fi
  fi
  if ! printf '%s' "$op_out" | grep -q '\[pi-provider doctor\]' || ! printf '%s' "$op_out" | grep -q 'EFFECTIVE'; then
    fail "[check-pack-install] installed 'entwurf doctor-pi-provider' never reached its verdict body (no scopes/EFFECTIVE report):"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi

  if ! op_out=$(HOME="$npmhome" XDG_DATA_HOME="$op_xdg_data" XDG_STATE_HOME="$op_xdg_state" XDG_CACHE_HOME="$op_xdg_cache" PI_CODING_AGENT_DIR="$op_agent" "$installed_entwurf" meta-bridge-prune "$op_agent/meta-sessions" 2>&1); then
    fail "[check-pack-install] installed 'entwurf meta-bridge-prune' FAILED on a 0-record store:"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi
  if ! printf '%s' "$op_out" | grep -q 'prune candidates' || ! printf '%s' "$op_out" | grep -q "store: $op_agent/meta-sessions"; then
    fail "[check-pack-install] installed 'entwurf meta-bridge-prune' did not scan the store it was given:"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi

  # #82 RAIL 7 — the managed launch, from the INSTALLED package. Hard Rule 11: a green
  # clone is not a green tarball. `entwurf copilot` is a bash leaf, so its risk here is
  # not the strip-types fence but PACKAGING — `scripts/copilot-launch.sh` has to be in
  # the tarball and reachable from the installed `run.sh`, and a file-list assertion
  # cannot tell a shipped script from a shipped script that resolves its siblings wrongly
  # once it lives under node_modules. So the cell RUNS it, against a fake vendor on a
  # sandbox PATH and a fake receiver install-state, and reads what the vendor was handed.
  local cop_launch_home="$npm_tmp/cop-launch-home" cop_launch_xdg="$npm_tmp/cop-launch-xdg" cop_launch_bin="$npm_tmp/cop-launch-bin"
  local cop_unit_dir="$cop_launch_home/.copilot/extensions/entwurf-receive"
  local cop_state_dir="$cop_launch_xdg/entwurf/copilot-receive"
  mkdir -p "$cop_unit_dir" "$cop_state_dir" "$cop_launch_bin"
  printf '// fixture\n' > "$cop_unit_dir/extension.mjs"
  printf '{"schemaVersion":1,"unit":"entwurf-receive","path":"%s"}\n' "$cop_unit_dir" > "$cop_state_dir/install-state.json"
  # The stand-in is installed under the REAL name on a sandbox PATH: the launcher resolves
  # `copilot` and nothing else, so there is no env switch here to prove the wrong contract with.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "FLAG=[${COPILOT_CLI_ENABLED_FEATURE_FLAGS-<unset>}]"\n'
    printf 'for a in "$@"; do printf "ARG<%%s>\\n" "$a"; done\n'
  } > "$cop_launch_bin/copilot"
  chmod +x "$cop_launch_bin/copilot"
  # `env -u` for BOTH carriers, not just a reassignment: an operator running this gate with
  # their own COPILOT_CLI_ENABLED_FEATURE_FLAGS exported would otherwise inherit those tokens
  # into the oracle below and read a FALSE RED, and an inherited launch sentinel would trip
  # the recursion fence before the vendor was ever reached. The cell must measure the
  # installed launcher, not the shell that happened to start it.
  if ! op_out=$(env -u COPILOT_CLI_ENABLED_FEATURE_FLAGS -u ENTWURF_COPILOT_LAUNCH_ACTIVE \
      HOME="$cop_launch_home" XDG_DATA_HOME="$cop_launch_xdg" PATH="$cop_launch_bin:$PATH" \
      "$installed_entwurf" copilot -p hi 2>&1); then
    fail "[check-pack-install] installed 'entwurf copilot' FAILED to reach the vendor:"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi
  # Assert MEANING: the scan flag this whole surface exists to set, the managed defaults,
  # and the operator's own argument, all arriving at the vendor from the installed tree.
  if ! printf '%s' "$op_out" | grep -q 'FLAG=\[EXTENSIONS\]'; then
    fail "[check-pack-install] installed 'entwurf copilot' did not hand the vendor COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS:"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi
  for want in 'ARG<-p>' 'ARG<hi>' 'ARG<--model>' 'ARG<auto>' 'ARG<--yolo>'; do
    if ! printf '%s' "$op_out" | grep -qF "$want"; then
      fail "[check-pack-install] installed 'entwurf copilot' did not forward the managed argv (missing $want):"
      echo "$op_out" | tail -8 | sed 's/^/    /' >&2
      return 1
    fi
  done
  if printf '%s' "$op_out" | grep -qF 'ARG<copilot>'; then
    fail "[check-pack-install] installed 'entwurf copilot' leaked the dispatcher verb into the vendor's argv:"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] installed 'entwurf copilot' reached the vendor with the scan flag and the managed argv"

  # The generation verb must reach its verdict from under node_modules. On the
  # sandbox 0-record agent dir it archives nothing and opens a fresh generation.
  # The exit code alone can't tell a verdict from a fence crash, so read the line.
  if ! op_out=$(HOME="$npmhome" XDG_DATA_HOME="$op_xdg_data" XDG_STATE_HOME="$op_xdg_state" XDG_CACHE_HOME="$op_xdg_cache" PI_CODING_AGENT_DIR="$op_agent" "$installed_entwurf" meta-bridge-fresh-cut 2>&1); then
    fail "[check-pack-install] installed 'entwurf meta-bridge-fresh-cut' FAILED on a 0-record host:"
    echo "$op_out" | tail -8 | sed 's/^/    /' >&2
    return 1
  fi
  if ! printf '%s' "$op_out" | grep -q 'fresh generation open'; then
    fail "[check-pack-install] installed 'entwurf meta-bridge-fresh-cut' never reached its verdict line: $op_out"
    return 1
  fi
  echo "[check-pack-install] installed operator commands pass (new-session-id id-shaped, doctor-pi-provider reaches its verdict, meta-bridge-prune walks a 0-record store, fresh-cut opens a generation)"

  # ── generation lane: the INSTALLED lifecycle on a host that already carries a
  # previous-generation store. Everything above this line meets an empty store,
  # which is the one host state that was never in doubt. This is the state an
  # existing development machine is actually in on upgrade day, driven end to end
  # through the npm-installed bin — not the checkout:
  #
  #     seeded previous-generation store → installed install-meta-bridge REFUSES
  #     (zero Claude calls, persistent regular-file manifest unchanged, refusal
  #     names the installed fresh-cut form) → installed fresh-cut archives the
  #     generation (original bytes intact) + opens an empty one → installed
  #     install-meta-bridge PASSES
  #
  # The store is seeded INLINE (a v2-shaped record the live schema refuses).
  # There is no frozen fixture apparatus anymore: fresh-cut never rewrites a
  # byte — the archive is a rename — so the only byte claim left is
  # `archived == seeded`, checked against a hash taken here before any command
  # runs. HOME is the sandbox root and no store env override is set: the default
  # <pi-agent-dir>/meta-sessions resolution is part of what gets proven.
  local pc_home="$npm_tmp/prevgen-home" pc_cfg="$npm_tmp/prevgen-claude"
  local pc_claude_log="$npm_tmp/prevgen-fake-claude.log"
  local pc_store="$pc_home/.pi/agent/meta-sessions"
  local pc_record="20260305T000000-dddd05.meta.json"
  mkdir -p "$pc_store" "$pc_cfg"
  : > "$pc_claude_log"
  cat > "$pc_store/$pc_record" <<'JSON'
{
  "schemaVersion": 2,
  "gardenId": "20260305T000000-dddd05",
  "backend": "claude-code",
  "nativeSessionId": "prevgen-native-1",
  "cwd": "/tmp/prevgen",
  "model": null,
  "transcriptPath": null,
  "parentGardenId": "20260101T000000-aaaa01",
  "isEntwurf": true,
  "createdAt": "2026-03-05T00:00:00.000Z",
  "recordUpdatedAt": "2026-03-05T00:00:00.000Z"
}
JSON
  local pc_seed_sha
  pc_seed_sha=$(sha256sum "$pc_store/$pc_record" | cut -d' ' -f1)
  local pc_env=(HOME="$pc_home" XDG_DATA_HOME="$pc_home/.local/share" XDG_STATE_HOME="$pc_home/.local/state" XDG_CACHE_HOME="$pc_home/.cache" CLAUDE_CONFIG_DIR="$pc_cfg" FAKE_CLAUDE_LOG="$pc_claude_log" PATH="$fake_claude_dir:$npmroot/node_modules/.bin:$PATH")
  local pc_before pc_after pc_out pc_rc
  pc_before=$(cd "$pc_home" && find . -type f -exec sha256sum {} + 2>/dev/null | sort)

  set +e
  pc_out=$(env "${pc_env[@]}" "$npm_pkg/run.sh" install-meta-bridge 2>&1); pc_rc=$?
  set -e
  if [ "$pc_rc" = 0 ]; then
    fail "[check-pack-install] installed install-meta-bridge ACCEPTED a previous-generation store — the store gate is missing from the packaged artifact:"
    echo "$pc_out" | tail -12 | sed 's/^/    /' >&2
    return 1
  fi
  pc_after=$(cd "$pc_home" && find . -type f -exec sha256sum {} + 2>/dev/null | sort)
  if [ "$pc_before" != "$pc_after" ]; then
    fail "[check-pack-install] the refused install-meta-bridge still wrote to the host:"
    diff <(printf '%s\n' "$pc_before") <(printf '%s\n' "$pc_after") | sed 's/^/    /' >&2
    return 1
  fi
  if [ -n "$(find "$pc_cfg" -type f 2>/dev/null)" ]; then
    fail "[check-pack-install] the refused install-meta-bridge created Claude config under $pc_cfg"
    return 1
  fi
  # ZERO claude invocations, not merely zero mutating ones. The installer decides
  # platform, python3, node and the host's own store before it ever touches the
  # external CLI, so a store refusal is provably free of outside contact — and an
  # empty log is an assertion that cannot rot the way an allow-list of "harmless"
  # subcommands would.
  if [ -s "$pc_claude_log" ]; then
    fail "[check-pack-install] the refused install-meta-bridge invoked the claude CLI before refusing (the store gate must decide first):"
    sed 's/^/    /' "$pc_claude_log" >&2
    return 1
  fi
  echo "[check-pack-install] previous-generation host: installed install-meta-bridge REFUSED before any write (host regular-file manifest unchanged, zero Claude invocations)"

  # The refusal has to be actionable from a packaged host, which cannot type ./run.sh.
  if ! printf '%s' "$pc_out" | grep -q 'entwurf meta-bridge-fresh-cut'; then
    fail "[check-pack-install] the installed refusal never named the INSTALLED fresh-cut invocation form:"
    echo "$pc_out" | tail -12 | sed 's/^/    /' >&2
    return 1
  fi

  # The cut, through the real installed bin: archive + empty generation.
  set +e
  pc_out=$(env "${pc_env[@]}" PI_CODING_AGENT_DIR="$pc_home/.pi/agent" "$installed_entwurf" meta-bridge-fresh-cut 2>&1); pc_rc=$?
  set -e
  if [ "$pc_rc" != 0 ]; then
    fail "[check-pack-install] installed fresh-cut FAILED on the seeded previous-generation store:"
    echo "$pc_out" | tail -20 | sed 's/^/    /' >&2
    return 1
  fi
  local pc_archive pc_got
  pc_archive=$(find "$pc_home/.pi/agent" -maxdepth 1 -type d -name 'meta-sessions.archive-*' | head -1)
  if [ -z "$pc_archive" ]; then
    fail "[check-pack-install] installed fresh-cut opened a generation without archiving the previous one"
    return 1
  fi
  # The archive must hold the ORIGINAL bytes — compared against the hash taken
  # at seed time, never against a re-serialization by the code under test.
  pc_got=$(sha256sum "$pc_archive/$pc_record" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$pc_got" ] || [ "$pc_seed_sha" != "$pc_got" ]; then
    fail "[check-pack-install] the fresh-cut archive does not hold the original seeded bytes (seeded $pc_seed_sha, archive $pc_got)"
    return 1
  fi
  if [ -n "$(find "$pc_store" -name '*.meta.json' 2>/dev/null)" ]; then
    fail "[check-pack-install] the fresh generation is not empty — fresh-cut left records in the live store"
    return 1
  fi

  set +e
  pc_out=$(env "${pc_env[@]}" "$npm_pkg/run.sh" install-meta-bridge 2>&1); pc_rc=$?
  set -e
  if [ "$pc_rc" != 0 ]; then
    fail "[check-pack-install] installed install-meta-bridge STILL failed after the prescribed fresh-cut — the documented upgrade path does not land:"
    echo "$pc_out" | tail -20 | sed 's/^/    /' >&2
    return 1
  fi
  if ! grep -q 'plugin install' "$pc_claude_log"; then
    fail "[check-pack-install] the post-cut install never reached the plugin install step (it exited 0 without doing the work)"
    return 1
  fi
  echo "[check-pack-install] previous-generation host lifecycle pass (REFUSE → installed fresh-cut with original bytes in the archive → empty generation → install-meta-bridge PASSES)"

  # A dev-only gate has NO compiled twin by design. Under an installed package run_ts must
  # REFUSE it with a legible message — never fall back to raw .ts (that just re-raises the
  # fence error) and never exit 0 (a silent no-op would let CI "pass" a gate it never ran).
  local devgate_out devgate_rc=0
  devgate_out=$(HOME="$npmhome" XDG_DATA_HOME="$op_xdg_data" XDG_STATE_HOME="$op_xdg_state" XDG_CACHE_HOME="$op_xdg_cache" PI_CODING_AGENT_DIR="$op_agent" "$installed_entwurf" check-meta-session 2>&1) || devgate_rc=$?
  if [ "$devgate_rc" -eq 0 ]; then
    fail "[check-pack-install] a dev-only gate (check-meta-session) exited 0 from an installed package — it cannot have run; run_ts must refuse it"
    return 1
  fi
  if printf '%s' "$devgate_out" | grep -q ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING; then
    fail "[check-pack-install] a dev-only gate leaked the raw strip-types fence error instead of run_ts's refusal:"
    echo "$devgate_out" | tail -6 | sed 's/^/    /' >&2
    return 1
  fi
  if ! printf '%s' "$devgate_out" | grep -q 'dev-clone-only surface'; then
    fail "[check-pack-install] a dev-only gate under an installed package did not produce run_ts's refusal message:"
    echo "$devgate_out" | tail -6 | sed 's/^/    /' >&2
    return 1
  fi
  # The migrated fresh-call gate takes a third path: run_vitest. Drive that exact
  # installed branch and require both the nonzero refusal and its intended cause;
  # an incidental missing file or raw strip-types crash is not consumer evidence.
  local vitestgate_out vitestgate_rc=0
  vitestgate_out=$(HOME="$npmhome" XDG_DATA_HOME="$op_xdg_data" XDG_STATE_HOME="$op_xdg_state" XDG_CACHE_HOME="$op_xdg_cache" PI_CODING_AGENT_DIR="$op_agent" "$installed_entwurf" check-mux-fresh-call 2>&1) || vitestgate_rc=$?
  if [ "$vitestgate_rc" -eq 0 ]; then
    fail "[check-pack-install] the Vitest-backed check-mux-fresh-call exited 0 from an installed package — the devDependency runner is absent"
    return 1
  fi
  if ! printf '%s' "$vitestgate_out" | grep -q 'dev-clone-only surface' || ! printf '%s' "$vitestgate_out" | grep -q 'vitest is a devDependency'; then
    fail "[check-pack-install] installed check-mux-fresh-call did not refuse for run_vitest's intended devDependency/dev-clone-only reason:"
    echo "$vitestgate_out" | tail -6 | sed 's/^/    /' >&2
    return 1
  fi

  # Same rule, different mechanism. check-fresh-cut-gate is a SHELL gate, so run_ts
  # never sees it — `scripts/` ships whole and the dispatch would happily run it
  # from under node_modules, where the dev sandbox it builds has no business
  # existing. Without the script's own guard it would fail on some incidental path
  # instead of saying it is dev-clone-only, which is hard rule 10 failing quietly.
  local shgate_out shgate_rc=0
  shgate_out=$(HOME="$npmhome" XDG_DATA_HOME="$op_xdg_data" XDG_STATE_HOME="$op_xdg_state" XDG_CACHE_HOME="$op_xdg_cache" PI_CODING_AGENT_DIR="$op_agent" "$installed_entwurf" check-fresh-cut-gate 2>&1) || shgate_rc=$?
  if [ "$shgate_rc" -eq 0 ]; then
    fail "[check-pack-install] the shell-side dev-only gate (check-fresh-cut-gate) exited 0 from an installed package — it cannot have run"
    return 1
  fi
  if ! printf '%s' "$shgate_out" | grep -q 'dev-clone-only surface'; then
    fail "[check-pack-install] check-fresh-cut-gate under an installed package did not REFUSE as dev-clone-only (it failed some other way):"
    echo "$shgate_out" | tail -6 | sed 's/^/    /' >&2
    return 1
  fi
  echo "[check-pack-install] dev-only gate refusal pass (installed package refuses run_ts and run_vitest checks for their exact causes; shell-side check-fresh-cut-gate refuses on its own guard; no silent exit 0)"

  # 0.12.4 — installed STORE-DOCTOR regression. meta-bridge-doctor.sh's full store
  # scan runs the prebuilt dist JS when it lives under node_modules (strip-types
  # refuses the .ts there — the same class as the bridge boot above). Before the dist
  # split the doctor ran the raw .ts and reported a FALSE "corrupt records" FAIL on
  # EVERY installed host. Prove the shipped dist JS scans a fixture store with PLAIN
  # node (a strip-types fallback would crash with the exact
  # ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING) AND that its rewritten import of the
  # emitted meta-session.js resolves — a real record exercises parseMetaIdentity.
  local installed_store_doctor="$npm_pkg/mcp/entwurf-bridge/dist/scripts/meta-bridge-store-doctor.js"
  if [ ! -f "$installed_store_doctor" ]; then
    fail "[check-pack-install] installed store-doctor missing prebuilt dist (prepack did not emit it into the tarball?): $installed_store_doctor"
    return 1
  fi
  local sd_fixture="$npm_tmp/store-fixture"
  mkdir -p "$sd_fixture"
  # One valid v3 record (#50 hard cut keyset — no parentGardenId/isEntwurf):
  # filename == "${gardenId}.meta.json" (no drift), unique nativeSessionId (no
  # dupe). gardenId must match YYYYMMDDTHHMMSS-[0-9a-f]{6}.
  printf '%s\n' '{"schemaVersion":3,"gardenId":"20990101T000000-abcdef","backend":"claude-code","nativeSessionId":"native-store-doctor-fixture","cwd":"/tmp/entwurf-fixture","model":null,"transcriptPath":null,"createdAt":"2099-01-01T00:00:00.000Z","recordUpdatedAt":"2099-01-01T00:00:00.000Z"}' \
    > "$sd_fixture/20990101T000000-abcdef.meta.json"
  local sd_out
  if ! sd_out=$(node "$installed_store_doctor" "$sd_fixture" 2>&1); then
    fail "[check-pack-install] installed store-doctor FAILED to scan under node_modules (strip-types-under-node_modules regression, or the emitted meta-session import broke):"
    echo "$sd_out" | tail -15 | sed 's/^/    /' >&2
    return 1
  fi
  # Anchored on the doctor's own count line: this cell exists to prove the emitted
  # dist actually PARSED the fixture (not that it merely ran), so the number is the
  # claim. If the doctor's wording changes, change it here in the same commit —
  # a silent anchor miss would make this cell pass on a doctor that saw nothing.
  if ! grep -q "1 record(s) certified" <<<"$sd_out"; then
    fail "[check-pack-install] installed store-doctor ran but did not report certifying the fixture record (certifyActiveStore path not exercised, or its count line was reworded without updating this anchor): $sd_out"
    return 1
  fi
  echo "[check-pack-install] installed store-doctor scan pass (dist JS scans under node_modules with plain node: $sd_out)"

  # 0.12.4 — installed DOCTOR DISPATCH lock. The artifact above proves the store-scan
  # target runs under node_modules; this proves the doctor SCRIPT actually routes to
  # it (store scan → dist JS) and defers the strip-types-only source-shape gate
  # (v2-surface) when installed, instead of running raw .ts and false-failing.
  local installed_doctor="$npm_pkg/scripts/meta-bridge-doctor.sh"
  if ! grep -q 'dist/scripts/meta-bridge-store-doctor.js' "$installed_doctor"; then
    fail "[check-pack-install] installed doctor does not dispatch the store scan to the dist JS under node_modules: $installed_doctor"
    return 1
  fi
  if ! grep -q 'shipped surface source present' "$installed_doctor"; then
    fail "[check-pack-install] installed doctor does not defer the v2-surface source-shape gate on installed hosts: $installed_doctor"
    return 1
  fi
  echo "[check-pack-install] installed doctor dispatch lock pass (store-scan → dist JS, v2-surface deferred)"

  ok "[check-pack-install] publish install smoke pass"
  return 0
}

check_pack_install() {
  # SELF-FENCE wrapper (rule 11). Keep this OUTSIDE the implementation so every exit path —
  # including an early failure before the implementation's cleanup trap is installed — returns
  # through the comparison. The DATA tree is byte-fenced. STATE cannot be byte-fenced because a
  # live native session may append legitimate lines concurrently, so fence the gate's unique fake
  # conversation marker instead; any increase proves that agy-imprint escaped its sandbox.
  trap - RETURN
  local real_data_root="${XDG_DATA_HOME:-$HOME/.local/share}/entwurf"
  local real_imprint_log="${XDG_STATE_HOME:-$HOME/.local/state}/entwurf/agy-imprint.log"
  local data_before data_after fake_before fake_after rc=0
  data_before="$( (find "$real_data_root" -type f -print0 2>/dev/null | sort -z | xargs -0r sha256sum) 2>/dev/null || true)"
  fake_before="$(grep -Fc 'conversationId=pack-install-agy-conversation' "$real_imprint_log" 2>/dev/null || true)"

  _check_pack_install_impl "$@" || rc=$?
  # _check_pack_install_impl installs a RETURN cleanup trap after allocating its temp roots.
  # It has fired now; clear it before this wrapper returns so it cannot leak into its caller.
  trap - RETURN

  data_after="$( (find "$real_data_root" -type f -print0 2>/dev/null | sort -z | xargs -0r sha256sum) 2>/dev/null || true)"
  fake_after="$(grep -Fc 'conversationId=pack-install-agy-conversation' "$real_imprint_log" 2>/dev/null || true)"
  if [ "$data_before" != "$data_after" ]; then
    fail "[check-pack-install] SELF-FENCE: this gate changed the operator's REAL install-state tree ($real_data_root) — a sandbox drive is leaking through an inherited XDG root:"
    diff <(printf '%s\n' "$data_before") <(printf '%s\n' "$data_after") | sed 's/^/    /' >&2 || true
    rc=1
  fi
  if [ "$fake_before" != "$fake_after" ]; then
    fail "[check-pack-install] SELF-FENCE: this gate appended its fake agy birth marker to the operator's REAL state log ($real_imprint_log): before=$fake_before after=$fake_after"
    rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    echo "[check-pack-install] self-fence pass (real DATA tree byte-identical; fake STATE marker count unchanged)"
  fi
  return "$rc"
}


# --- v2 install/runtime verification gates ---
#
# These validators complement the local deterministic check_* gates by exercising
# the runtime surfaces an installed v2 package depends on. On v2-only, setup must
# NOT run the legacy ACP/v1 Axis 1 interview gates (session-messaging/sentinel):
# those call removed surfaces and survive only as fail-loud reference subcommands
# until rewritten onto entwurf_v2. The release-gate owns the heavier live v2
# substrate proof (matrix-live).

validate_entwurf_bridge() {
  local bridge_dir="$REPO_DIR/mcp/entwurf-bridge"
  local raw

  if [ ! -x "$bridge_dir/start.sh" ]; then
    fail "entwurf-bridge: launcher missing at $bridge_dir/start.sh"
    return 1
  fi

  # The launcher picks its own mode by LOCATION (dev clone → strip-types source; under
  # node_modules → prebuilt dist), and this subcommand ships, so an operator running
  # `entwurf check-bridge` from an npm install reads this line too. Naming only the dev
  # branch here told that operator the installed bytes were never the subject.
  log "entwurf-bridge: direct MCP smoke (start.sh as it ships — source under a clone, prebuilt dist under node_modules)"

  if ! raw=$(cd "$bridge_dir" && node --input-type=module <<'JS'
import { spawn } from 'node:child_process';

const child = spawn('./start.sh');
let stdout = '';
let stderr = '';
let done = false;

function finishOk(trimmed) {
  if (done) return;
  done = true;
  clearTimeout(timer);
  if (stderr.trim()) console.error(stderr.trim());
  const msg = JSON.parse(trimmed);
  const tools = msg?.result?.tools;
  if (!Array.isArray(tools)) {
    console.error('tools/list response missing result.tools');
    process.exit(1);
  }
  const names = tools.map((t) => t?.name).sort();
  // EXACT set, not a floor. This is the assertion behind the operator-facing claim that
  // `entwurf check-bridge` proves the installed bytes list the seven garden tools — and
  // under an installed package this launcher IS the dist branch of start.sh, so a subset
  // check here let an artifact missing entwurf_fresh_call / entwurf_resume_call read as a
  // green bridge. Equality also refuses an undecided extra verb. Written sorted; `names`
  // is sorted above.
  const expected = ['entwurf_fresh_call', 'entwurf_inbox_read', 'entwurf_peers', 'entwurf_register_native', 'entwurf_resume_call', 'entwurf_self', 'entwurf_v2'];
  if (names.length !== expected.length || expected.some((n, i) => names[i] !== n)) {
    console.error(`MCP tool set MISMATCH — want exactly [${expected.join(',')}] got [${names.join(',')}]`);
    process.exit(1);
  }
  console.log(names.join(','));
  child.kill('SIGTERM');
  process.exit(0);
}

child.stdout.on('data', (d) => {
  stdout += d.toString();
  const trimmed = stdout.trim();
  if (trimmed) finishOk(trimmed);
});
child.stderr.on('data', (d) => { stderr += d.toString(); });
child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }) + '\n');

const timer = setTimeout(() => {
  child.kill('SIGKILL');
  console.error('entwurf-bridge direct smoke timeout');
  process.exit(1);
}, 3000);

child.on('error', (err) => {
  if (done) return;
  clearTimeout(timer);
  console.error(String(err));
  process.exit(1);
});

child.on('close', () => {
  if (done) return;
  clearTimeout(timer);
  const trimmed = stdout.trim();
  if (!trimmed) {
    if (stderr.trim()) console.error(stderr.trim());
    console.error('empty tools/list response');
    process.exit(1);
  }
  finishOk(trimmed);
});
JS
  ); then
    fail "entwurf-bridge: direct MCP smoke failed"
    return 1
  fi
  ok "entwurf-bridge direct MCP smoke ($raw)"

  if ! (cd "$bridge_dir" && ./test.sh >/dev/null); then
    fail "entwurf-bridge: protocol/negative-path tests failed"
    return 1
  fi
  ok "entwurf-bridge test.sh"

  # check-bridge deliberately stops at the objective MCP boundary. Live v2
  # substrate/orchestration is covered by the v2 live smokes, whose assertions
  # parse operational artifacts instead of asking a model to self-report which
  # tool schema it sees. This split keeps check-bridge credential-free and avoids
  # model self-recognition variance blocking setup.
}

check_bridge() {
  section "entwurf-bridge (direct MCP protocol)"
  validate_entwurf_bridge
}


# ── setup verdict engine (#86 C1) ────────────────────────────────────────────
# setup composes harnesses the operator ALREADY installed. Per component the
# verdict is PASS (detected + completed), SKIP (truly absent — zero state
# written), or FAIL (detected but incomplete/below-floor/refused). The final
# summary and exit status are COMPUTED from these outcomes: core survival never
# relabels a detected harness failure as green, and a FAIL owns a nonzero setup
# result while every valid earlier write stays installed (re-running setup is
# the documented repair action).
SETUP_RESULTS=()
setup_result() {  # $1=component $2=PASS|SKIP|FAIL $3=detail
  SETUP_RESULTS+=("$1|$2|$3")
  case "$2" in
    PASS) ok "$1: PASS — $3" ;;
    SKIP) log "$1: SKIP — $3" ;;
    *)    fail "$1: FAIL — $3" ;;
  esac
}

# Installed-vs-source is decided by PACKAGE LOCATION — the same `*/node_modules/*`
# seam run_ts and the bridge launcher already branch on — never by which of
# pnpm/pi happens to be missing (an accidental failure is not a mode gate).
setup_mode() {
  case "$REPO_DIR" in
    */node_modules/*) echo installed ;;
    *) echo source ;;
  esac
}

# Supported pi range, derived at runtime from the package.json devDependencies
# pin (the SSOT check-dep-versions binds: peer range == `>=<pin> <0.<minor+1>`).
# Never retyped here as a second literal.
pi_supported_range() {
  node -e '
    const pkg = require(process.argv[1]);
    const pin = pkg.devDependencies?.["@earendil-works/pi-coding-agent"];
    if (!/^0\.\d+\.\d+$/.test(pin ?? "")) { console.error(`unparseable pi pin: ${pin}`); process.exit(1); }
    const [, min] = pin.split(".").map(Number);
    console.log(`>=${pin} <0.${min + 1}`);
  ' "$REPO_DIR/package.json"
}

pi_version_in_range() {  # $1=detected version  $2=range ">=a.b.c <x.y"; exit 0 in-range
  node -e '
    const [ver, range] = process.argv.slice(1);
    const m = range.match(/^>=(\d+)\.(\d+)\.(\d+) <(\d+)\.(\d+)$/);
    const v = ver.match(/^(\d+)\.(\d+)\.(\d+)$/);
    if (!m || !v) process.exit(2);
    const [maj, min, pat] = v.slice(1).map(Number);
    const lo = m.slice(1, 4).map(Number);
    const hi = m.slice(4, 6).map(Number);
    const geFloor = maj > lo[0] || (maj === lo[0] && (min > lo[1] || (min === lo[1] && pat >= lo[2])));
    const ltCeil = maj < hi[0] || (maj === hi[0] && min < hi[1]);
    process.exit(geFloor && ltCeil ? 0 : 1);
  ' "$1" "$2"
}

# setup_all — one-command presence-driven composition (#86).
#
# Entwurf installs itself only: this command completes the integration of each
# harness the operator already installed and NEVER installs a harness binary,
# subscription, credential or login — `pi` has no privileged exception. It
# verifies the installed bridge boundary; ACP/v1 backend interview gates are
# deliberately not part of setup on v2-only (the heavier live v2 substrate
# proof is release-gate's job). Copilot's four native units (birth / MCP /
# receiver / visible footer) compose presence-driven since the birth inverse
# landed (#86 C3a→C3b); the explicit install-copilot-* / uninstall-copilot-*
# surfaces remain the operator-selected repair and inverse path.
#
# An external harness that consumes entwurf (e.g. agent-config as a
# pi package + skills set) may still have its own install/setup for its
# own concerns; those are outside the scope of this script.
setup_all() {
  # MODE FIRST (#86 C1): the installed-vs-source branch is a NAMED decision
  # ahead of every prerequisite check and write, so an installed consumer is
  # never mode-gated by an accidental missing `pnpm`/`pi`.
  local mode
  mode=$(setup_mode)
  case "$mode" in
    installed)
      echo "[setup] mode: installed package — composition only (no source bootstrap; setup never runs npm/pnpm inside node_modules)" ;;
    *)
      echo "[setup] mode: source checkout — repo dev bootstrap, then the same composition semantics" ;;
  esac

  # Named interpreter prerequisite, decided BEFORE any write (#86 C1/E5):
  # setup's project-path normalization and every pi/agy wiring writer are
  # python3-backed today. `entwurf --help` / `entwurf check-bridge` stay
  # python3-free; only the commands that invoke those writers declare it.
  command -v python3 >/dev/null 2>&1 || {
    echo "[setup] entwurf setup requires python3 on PATH (project-path normalization + wiring writers)." >&2
    echo "[setup] Install python3, or use python3-free surfaces (--help, check-bridge)." >&2
    exit 1
  }
  require_cmd node

  local project_dir
  project_dir=$(normalize_project_dir "$1")

  if [ "$mode" = "source" ]; then
    # Source-only dev fixtures: the pinned repo dependencies are build/test
    # fixtures, never a product promise that consumers receive them (#86 A4).
    require_cmd pnpm
  fi

  # Node 24+ is the SINGLE supported axis (GLG, 2026-07-21). The floor is not
  # derived from a feature gate: type-stripping alone would only demand 23.6.
  # It is derived from what is actually verified — this repo designs and proves
  # BOTH boundaries (dev-clone native-TS/ESM, installed compiled-JS) on Node 24,
  # and no 22 lane is maintained or tested. A floor nobody exercises is a
  # declaration, not a contract; #51 exists because this repo shipped several.
  # DO NOT reintroduce a "24 recommended / 22 minimum" dual declaration.
  # check-node-floor-coherence binds every spelling of this floor.
  if ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)'; then
    echo "[setup] entwurf requires Node >= 24 (got $(node -v))" >&2
    echo "[setup] Node 24+ is the only supported runtime axis; there is no Node 22 lane." >&2
    exit 1
  fi

  echo "[setup] repo:    $REPO_DIR"
  echo "[setup] project: $project_dir"
  echo "[setup] scope:   entwurf v2 package + detected native-harness bridges + pi adapter"
  echo "[setup] verification: v2 install smoke (entwurf-bridge; LIVE substrate = release-gate)"

  # Store gate FIRST — ahead of the source bootstrap and every settings writer
  # below. On an existing development host this is the only step standing
  # between a `git pull` and a V3-only activation over a store the live schema
  # cannot read; putting it inside install_local_package would already be one
  # write too late. The store-doctor imports repo-local libs and node builtins
  # only, so it runs before dependencies exist.
  preflight_v3_store setup

  SETUP_RESULTS=()

  if [ "$mode" = "source" ]; then
    # Source bootstrap is the ONLY install-mode difference (#86): the pinned
    # repo dev dependencies are fixtures this checkout builds/tests with. A
    # broken bootstrap is a broken checkout — crash, don't degrade.
    (cd "$REPO_DIR" && pnpm install --frozen-lockfile)
  fi

  # ── pi (presence + floor, #86 C1/C9) ── pi is OPTIONAL-BY-PRESENCE: absent is
  # an explicit zero-state SKIP (setup never installs pi and writes no Pi
  # wiring), below-floor/unreadable is detected-incomplete FAIL — never a SKIP,
  # so a stale pi is told the truth instead of being silently skipped. PI_BIN
  # pins the probe for the hermetic smoke (same seam as AGY_BIN); production
  # leaves it unset.
  local pi_bin="${PI_BIN:-pi}" pi_range pi_ver
  if ! command -v "$pi_bin" >/dev/null 2>&1; then
    setup_result pi SKIP "pi not on PATH — zero Pi wiring written (the operator installs pi; setup never does)"
  else
    pi_range=$(pi_supported_range)
    # Bounded capture: a resolvable pi whose --version crashes or prints garbage
    # must land in the computed FAIL verdict below, never abort setup via set -e
    # before the summary (review defect, 2026-08-26).
    pi_ver="$("$pi_bin" --version 2>/dev/null | head -n 1 | tr -d '[:space:]')" || pi_ver=""
    if ! pi_version_in_range "${pi_ver:-0}" "$pi_range"; then
      setup_result pi FAIL "detected pi ${pi_ver:-<unreadable version>} is outside the supported range $pi_range — Pi wiring not written; align pi, then re-run setup"
    elif (install_local_package "$project_dir"); then
      setup_result pi PASS "project + user-scope wiring complete (pi $pi_ver in $pi_range) — verify: ./run.sh doctor-pi-provider"
    else
      setup_result pi FAIL "pi wiring did not complete (see above) — repair, then re-run setup"
    fi
  fi

  # ── claude (meta-bridge) ── single confident install command (GLG 2026-06-23):
  # setup ALSO wires the native-harness meta-bridge so a relocate/clone needs ONE
  # command. Detection-gated ("있으면 설정, 없으면 담아준다");
  # meta-bridge-install.sh is idempotent and enforces the Claude floor + its own
  # named prerequisites itself, so a below-floor or refused host lands here as a
  # detected FAIL, never a cosmetic green. CLAUDE_BIN pins the probe for the
  # hermetic smoke; production leaves it unset.
  local claude_bin="${CLAUDE_BIN:-claude}"
  if ! command -v "$claude_bin" >/dev/null 2>&1; then
    setup_result claude SKIP "claude not on PATH — zero meta-bridge wiring written"
  else
    section "meta-bridge install (native harness detected: Claude Code)"
    if (cd "$REPO_DIR" && bash scripts/meta-bridge-install.sh); then
      setup_result claude PASS "meta-bridge wired — verify: ./run.sh doctor-meta-bridge"
    else
      setup_result claude FAIL "detected Claude Code, but the meta-bridge integration did not complete (see above) — repair, then re-run setup"
    fi
  fi

  # ── stable command exposure ── source mode exposes entwurf's STABLE bins on
  # PATH for this DEV checkout (막힘 ②) BEFORE wiring agy: the operator command
  # `entwurf` that Copilot fresh resolves as its managed runtime, plus the bare
  # bridge/statusline/imprint names native-harness configs record. An installed
  # consumer already has the same commands from npm bin linking — nothing to
  # expose there. The core operator stays fail-loud; helper units are attempted
  # independently and a refused helper is a named FAIL, not a cosmetic green.
  local bins_rc
  if [ "$mode" = "installed" ]; then
    # PASS, not SKIP (review, 2026-08-26): the capability IS present — npm bin
    # linking provides the same stable commands the source lane must expose.
    # SKIP stays reserved for a truly absent capability with zero state.
    setup_result bins PASS "provided by npm bin linking (installed package needs no source exposure)"
  else
    bins_rc=0; expose_dev_bin || bins_rc=$?
    if [ "$bins_rc" -eq 0 ]; then
      setup_result bins PASS "source operator + helper bins exposed and certified (PATH winner: this checkout)"
    elif [ "$bins_rc" -eq 3 ]; then
      setup_result bins FAIL "foreign helper bin(s) refused (named above; every unit was attempted) — repair them, then re-run setup"
    else
      setup_result bins FAIL "source operator command not certified (see above) — repair PATH/link, then re-run setup"
    fi
  fi

  # ── agy (Antigravity) ── detection-gated (막힘 ①, GLG 2026-07-04: install
  # ownership moves to entwurf); AGY_BIN pins the probe for the hermetic smoke.
  # agy absent is one zero-state SKIP. agy PRESENT runs all three leaves
  # (bridge / statusLine / PreInvocation imprint) independently; a refused or
  # corrupt config is a named component FAIL that keeps the rest of setup alive
  # but owns a nonzero final result — the old WARN-then-green posture is retired
  # (#86 C6/C7). Hard per-leaf verdicts stay with the doctor commands.
  local agy_rc
  if ! command -v "${AGY_BIN:-agy}" >/dev/null 2>&1; then
    setup_result agy SKIP "agy not on PATH — zero agy wiring written"
  else
    agy_rc=0; wire_agy_bridge || agy_rc=$?
    if [ "$agy_rc" -eq 0 ]; then
      setup_result agy-bridge PASS "MCP bridge wired — verify: ./run.sh doctor-agy-bridge"
    else
      setup_result agy-bridge FAIL "detected agy, but the MCP bridge integration did not complete (reason above) — repair, then re-run setup"
    fi
    agy_rc=0; wire_agy_statusline || agy_rc=$?
    if [ "$agy_rc" -eq 0 ]; then
      setup_result agy-statusline PASS "statusLine wired — verify: ./run.sh doctor-agy-statusline"
    else
      setup_result agy-statusline FAIL "detected agy, but the statusLine integration did not complete (reason above) — repair, then re-run setup"
    fi
    agy_rc=0; wire_agy_hooks || agy_rc=$?
    if [ "$agy_rc" -eq 0 ]; then
      setup_result agy-hooks PASS "birth imprint wired — verify: ./run.sh doctor-agy-hooks"
    else
      setup_result agy-hooks FAIL "detected agy, but the birth-imprint integration did not complete (reason above) — repair, then re-run setup"
    fi
  fi

  # ── copilot (GitHub Copilot CLI) ── presence-driven composition (#86 C3b):
  # the operator's copilot on PATH is the ONLY trigger; absent is one zero-state
  # SKIP (setup never installs a harness). Present runs all FOUR units the
  # fresh-call preflight requires — birth → MCP → receiver → visible footer —
  # INDEPENDENTLY: a failed unit is a named component FAIL that keeps the other
  # units and the rest of setup alive but owns a nonzero final result. Every
  # unit is an operator-selectable install with a package-owned inverse (#86
  # C3a closed the birth inverse), so setup composes only lifecycles it can
  # also undo. COPILOT_BIN pins the PROBE for the hermetic gates (same seam
  # spirit as PI_BIN/CLAUDE_BIN/AGY_BIN); the unit scripts address the vendor
  # as `copilot` on PATH, so production leaves it unset and the two agree.
  local copilot_rc
  if ! command -v "${COPILOT_BIN:-copilot}" >/dev/null 2>&1; then
    setup_result copilot SKIP "copilot not on PATH — zero Copilot wiring written"
  else
    section "copilot units (native harness detected: GitHub Copilot CLI)"
    copilot_rc=0; (cd "$REPO_DIR" && bash scripts/copilot-bridge-install.sh) || copilot_rc=$?
    if [ "$copilot_rc" -eq 0 ]; then
      setup_result copilot-birth PASS "birth plugin installed — verify: ./run.sh doctor-copilot-bridge"
    else
      setup_result copilot-birth FAIL "detected copilot, but the birth plugin install did not complete (see above) — repair, then re-run setup"
    fi
    copilot_rc=0; (cd "$REPO_DIR" && bash scripts/copilot-mcp-bridge.sh install) || copilot_rc=$?
    if [ "$copilot_rc" -eq 0 ]; then
      setup_result copilot-mcp PASS "MCP server registered — verify: ./run.sh doctor-copilot-mcp"
    else
      setup_result copilot-mcp FAIL "detected copilot, but the MCP registration did not complete (see above) — repair, then re-run setup"
    fi
    # The receiver deploys the COMPILED dist closure on every install shape
    # (Copilot's extension runtime cannot strip-types). The tarball ships dist;
    # a source checkout may not have built it yet, and those bytes are
    # entwurf's OWN artifact (Hard Rule 17: the source bootstrap supplies
    # entwurf's own bytes), so the source lane builds it here once when absent.
    copilot_rc=0
    if [ "$mode" = "source" ] && [ ! -f "$REPO_DIR/mcp/entwurf-bridge/dist/pi-extensions/lib/meta-session.js" ]; then
      (cd "$REPO_DIR" && pnpm run build-bridge) || copilot_rc=$?
    fi
    if [ "$copilot_rc" -ne 0 ]; then
      setup_result copilot-receive FAIL "detected copilot, but the receiver's compiled dist closure failed to build (see above) — repair, then re-run setup"
    else
      copilot_rc=0; (cd "$REPO_DIR" && bash scripts/copilot-receive-bridge.sh install) || copilot_rc=$?
      if [ "$copilot_rc" -eq 0 ]; then
        setup_result copilot-receive PASS "receiver extension installed — verify: ./run.sh doctor-copilot-receive"
      else
        setup_result copilot-receive FAIL "detected copilot, but the receiver extension install did not complete (see above) — repair, then re-run setup"
      fi
    fi
    copilot_rc=0; (cd "$REPO_DIR" && bash scripts/copilot-statusline-bridge.sh install) || copilot_rc=$?
    if [ "$copilot_rc" -eq 0 ]; then
      setup_result copilot-statusline PASS "visible footer wired — verify: ./run.sh doctor-copilot-statusline"
    else
      setup_result copilot-statusline FAIL "detected copilot, but the visible-footer integration did not complete (see above) — repair, then re-run setup"
    fi
  fi

  # ── omp (oh-my-pi) ── presence-driven composition, same shape as copilot. OMP
  # was admitted as a garden citizen in v0.16.0 with installers, doctors and
  # inverses for every unit — but it was never composed HERE, so the one-command
  # surface left the fifth backend to a hand-run verb list and the operator setting
  # to a documentation step. That gap is what `docs/adding-a-harness.md` step 10
  # now closes for every future harness: an onboarding is not finished until setup
  # composes it. Four units, each independent: birth (who the citizen is) → MCP
  # hand (what it can call) → the tools.xdev operator setting (whether those calls
  # are REACHABLE) → receiver (whether a reply can land). OMP_BIN pins the PROBE
  # for hermetic gates; the unit scripts address `omp` on PATH.
  local omp_rc
  if ! command -v "${OMP_BIN:-omp}" >/dev/null 2>&1; then
    setup_result omp SKIP "omp not on PATH — zero OMP wiring written"
  else
    section "omp units (native harness detected: oh-my-pi)"
    omp_rc=0; (cd "$REPO_DIR" && bash scripts/omp-bridge-install.sh) || omp_rc=$?
    if [ "$omp_rc" -eq 0 ]; then
      setup_result omp-birth PASS "birth extension installed — verify: ./run.sh doctor-omp-bridge"
    else
      setup_result omp-birth FAIL "detected omp, but the birth extension install did not complete (see above) — repair, then re-run setup"
    fi
    omp_rc=0; (cd "$REPO_DIR" && bash scripts/omp-mcp-bridge.sh install) || omp_rc=$?
    if [ "$omp_rc" -eq 0 ]; then
      setup_result omp-mcp PASS "MCP server registered — verify: ./run.sh doctor-omp-mcp"
    else
      setup_result omp-mcp FAIL "detected omp, but the MCP registration did not complete (see above) — repair, then re-run setup"
    fi
    # The operator setting is a component of its own because its FAIL is a real
    # disagreement, not a broken install: an explicit `tools.xdev: true` is the
    # operator's decision and the writer refuses it by name. Naming that as a
    # component FAIL puts the choice in front of the operator instead of silently
    # shipping a citizen whose tools nobody can call.
    omp_rc=0; (cd "$REPO_DIR" && bash scripts/omp-config-xdev.sh install) || omp_rc=$?
    if [ "$omp_rc" -eq 0 ]; then
      setup_result omp-config PASS "tools.xdev: false written — verify: ./run.sh doctor-omp-mcp"
    else
      setup_result omp-config FAIL "detected omp, but the tools.xdev operator setting did not land (see above) — resolve it, then re-run setup"
    fi
    omp_rc=0; (cd "$REPO_DIR" && bash scripts/omp-receive-install.sh) || omp_rc=$?
    if [ "$omp_rc" -eq 0 ]; then
      setup_result omp-receive PASS "receiver extension installed — verify: ./run.sh doctor-omp-receive"
    else
      setup_result omp-receive FAIL "detected omp, but the receiver extension install did not complete (see above) — repair, then re-run setup"
    fi
  fi

  # ── core bridge boundary ── deterministic preflight lives in `pnpm run
  # check:full`; live substrate acceptance lives in `LIVE=1 ./run.sh
  # release-gate <scratch> --cut`. Setup is the install path, so it verifies the
  # installed MCP bridge boundary only and does NOT run the legacy ACP/v1
  # session-messaging/sentinel gates.
  section "v2 install smoke: entwurf-bridge (direct MCP protocol)"
  if (validate_entwurf_bridge); then
    setup_result core PASS "installed bridge boots and lists the exact v2 tool set"
  else
    setup_result core FAIL "installed bridge boundary did not validate (see above)"
  fi

  # ── computed summary (#86 C7/C8) ── the final verdict is DERIVED from the
  # component outcomes above, never printed independently of them. A detected
  # integration FAIL owns a nonzero exit while valid components stay installed;
  # re-running the same setup is the documented repair action (idempotent).
  section "setup summary (computed from component outcomes)"
  local entry rest s_name s_verdict s_fails=""
  for entry in "${SETUP_RESULTS[@]}"; do
    s_name="${entry%%|*}"; rest="${entry#*|}"; s_verdict="${rest%%|*}"
    printf '  %-18s %-4s %s\n' "$s_name" "$s_verdict" "${rest#*|}"
    if [ "$s_verdict" = "FAIL" ]; then s_fails="$s_fails $s_name"; fi
  done
  echo ""
  if [ -n "$s_fails" ]; then
    echo "DONE: entwurf setup — result: NON-GREEN (FAIL:$s_fails). Valid components above remain installed; repair the named ones and re-run setup."
    return 1
  fi
  echo "DONE: entwurf setup — result: green (computed from the component outcomes above)."
  echo "Run 'LIVE=1 ./run.sh release-gate <scratch> --cut' for live substrate acceptance (--cut refuses any MUST SKIP)."
}

# wire_agy_bridge — detection-gated agy (Antigravity) MCP bridge wiring, folded into
# setup so a relocate/clone needs ONE idempotent command (막힘 ①). Mirrors the meta-bridge
# block: agy on PATH → idempotent install-agy-bridge; no agy → honest skip, NO state ("있으면
# 설정, 없으면 담아준다"). A refused/corrupt agy config still never bricks the rest of setup —
# later components are attempted — but it RETURNS 1 so the aggregate verdict records a named
# component FAIL and setup exits non-green (#86 C6/C7: the old WARN-then-exit-0 posture was the
# false-success shape). The hard per-leaf gate stays doctor-agy-bridge (issue #45). WARNs are
# reason-specific so a transitional symlink (someone else's SSOT) and a corrupt config
# (invalid JSON) are never conflated.
wire_agy_bridge() {
  # Detection = the agy binary on PATH. AGY_BIN pins the target (default `agy`) so the
  # hermetic smoke can point at a fake agy or a definitely-absent path without depending on
  # whatever agy the CI/dev host happens to have — production leaves it unset (= `command -v
  # agy`, no regression). Same override spirit as agy-bridge.sh's AGY_MCP_CONFIG/AGY_BRIDGE_COMMAND.
  if ! command -v "${AGY_BIN:-agy}" >/dev/null 2>&1; then
    echo "[setup] no agy on PATH — skipping agy bridge wiring (no state; this host runs no Antigravity)"
    return 0
  fi
  section "agy bridge install (native harness detected: Antigravity)"
  local out rc
  set +e
  out="$(bash "$REPO_DIR/scripts/agy-bridge.sh" install 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo "[setup] agy bridge wired (idempotent). Verify with: ./run.sh doctor-agy-bridge"
    return 0
  fi
  # Keep setup alive for the remaining components, surface the reason honestly, and return 1
  # so the aggregate verdict records this component as FAIL (never a silent pass).
  # ORDER MATTERS: the permission failures carry the same words as the mcp_config ones ("refused
  # (symlink)", "invalid JSON") and MUST be matched first — otherwise a settings.json problem gets
  # reported as an mcp_config problem and sends the operator to repair the wrong file.
  case "$out" in
    *"permission refused (symlink)"*|*"permission invalid JSON"*|*"permission could not be granted"*)
      # The MCP server IS registered — only the allow rules failed. agy defaults every mcp action to
      # Ask, so the bridge works but stops for a y/n on EVERY entwurf tool call. Half-wired, and said
      # so: the explicit installer fails loud on this; setup only degrades it, never hides it.
      echo "[setup] WARN: agy settings.json could not take our permission rules — bridge REGISTERED but NOT GRANTED." >&2
      echo "[setup]       agy will prompt on every entwurf tool call until our narrow rules" >&2
      echo "[setup]       ($(python3 "$REPO_DIR/scripts/agy-bridge-config.py" permission-rules 2>/dev/null || echo 'mcp(entwurf-bridge/<tool>)'))" >&2
      echo "[setup]       are in its permissions.allow (see the line above for why). setup continues." >&2
      ;;
    *"refused (symlink)"*)
      echo "[setup] WARN: agy mcp_config is a symlink — someone else's SSOT (transitional)." >&2
      echo "[setup]       Bridge NOT wired; expected until install ownership moves to entwurf." >&2
      echo "[setup]       Re-run setup once the symlink is dropped. setup continues." >&2
      ;;
    *"invalid JSON"*)
      echo "[setup] WARN: your agy mcp_config is CORRUPT (invalid JSON) — bridge NOT wired." >&2
      echo "[setup]       doctor-agy-bridge will KEEP FAILING until you repair that file." >&2
      echo "[setup]       (Not a silent skip — fix the config, then re-run setup.) setup continues." >&2
      ;;
    *)
      echo "[setup] WARN: agy bridge install did not complete (rc=$rc; see the line above)." >&2
      echo "[setup]       Bridge NOT wired; verify with ./run.sh doctor-agy-bridge. setup continues." >&2
      ;;
  esac
  return 1
}

# wire_agy_statusline — detection-gated agy statusLine wiring, folded into setup (#46
# Task 1). Mirrors wire_agy_bridge: agy on PATH → idempotent install-agy-statusline; no agy →
# honest skip, NO state; a refused/corrupt settings keeps the rest of setup alive but returns 1
# for a named component FAIL (#86 C6/C7). The hard gate is doctor-agy-statusline. The renderer
# is the stable bin entwurf-agy-statusline, exposed by expose_dev_bin above.
wire_agy_statusline() {
  if ! command -v "${AGY_BIN:-agy}" >/dev/null 2>&1; then
    echo "[setup] no agy on PATH — skipping agy statusLine wiring (no state; this host runs no Antigravity)"
    return 0
  fi
  section "agy statusLine install (native harness detected: Antigravity)"
  local out rc
  set +e
  out="$(bash "$REPO_DIR/scripts/agy-statusline-bridge.sh" install 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo "[setup] agy statusLine wired (idempotent). Verify with: ./run.sh doctor-agy-statusline"
    return 0
  fi
  case "$out" in
    *"refused (symlink)"*)
      echo "[setup] WARN: agy settings.json is a symlink — someone else's SSOT (transitional)." >&2
      echo "[setup]       statusLine NOT wired; expected until install ownership moves to entwurf." >&2
      echo "[setup]       Re-run setup once the symlink is dropped. setup continues." >&2
      ;;
    *"invalid JSON"*)
      echo "[setup] WARN: your agy settings.json is CORRUPT (invalid JSON) — statusLine NOT wired." >&2
      echo "[setup]       doctor-agy-statusline will KEEP FAILING until you repair that file." >&2
      echo "[setup]       (Not a silent skip — fix the config, then re-run setup.) setup continues." >&2
      ;;
    *)
      echo "[setup] WARN: agy statusLine install did not complete (rc=$rc; see the line above)." >&2
      echo "[setup]       statusLine NOT wired; verify with ./run.sh doctor-agy-statusline. setup continues." >&2
      ;;
  esac
  return 1
}

# wire_agy_hooks — detection-gated agy PreInvocation imprint wiring. Same setup posture
# as the MCP/statusLine adapters (skip on absence, named FAIL on detected incompleteness), but
# this one is the birth writer that turns statusLine '?' into a garden id after the first
# invocation.
wire_agy_hooks() {
  if ! command -v "${AGY_BIN:-agy}" >/dev/null 2>&1; then
    echo "[setup] no agy on PATH — skipping agy hooks wiring (no state; this host runs no Antigravity)"
    return 0
  fi
  section "agy hooks install (native harness detected: Antigravity)"
  local out rc
  set +e
  out="$(bash "$REPO_DIR/scripts/agy-hooks-bridge.sh" install 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo "[setup] agy hooks wired (idempotent). Verify with: ./run.sh doctor-agy-hooks"
    return 0
  fi
  case "$out" in
    *"refused (symlink)"*)
      echo "[setup] WARN: agy hooks.json is a symlink — someone else's SSOT (transitional)." >&2
      echo "[setup]       birth imprint NOT wired; re-run setup once the symlink is dropped. setup continues." >&2
      ;;
    *"invalid JSON"*)
      echo "[setup] WARN: your agy hooks.json is CORRUPT (invalid JSON) — birth imprint NOT wired." >&2
      echo "[setup]       doctor-agy-hooks will KEEP FAILING until you repair that file. setup continues." >&2
      ;;
    *)
      echo "[setup] WARN: agy hooks install did not complete (rc=$rc; see the line above)." >&2
      echo "[setup]       Birth imprint NOT wired; verify with ./run.sh doctor-agy-hooks. setup continues." >&2
      ;;
  esac
  return 1
}

# expose_dev_bin — make the package's stable commands resolve for a DEV checkout (막힘 ②).
# setup IS the dev install command (consumers get these names from npm bin-linking), so setup owns
# managed ~/.local/bin symlinks into this checkout via scripts/dev-bin.sh, each recorded for an
# honest inverse. The set starts with `entwurf` → run.sh: Copilot fresh deliberately launches the
# managed `entwurf copilot`, never the raw vendor. That operator command is CORE and is certified
# after exposure by dev-bin.sh's own target authority: our symlink, our target, and the exact PATH
# winner. A foreign/off-PATH/shadowed operator therefore fails setup (return 1). Helper units are
# attempted INDEPENDENTLY by dev-bin.sh (#86 C10) and any refusal propagates as return 3 — the
# aggregate verdict records it as a named FAIL instead of the old WARN-then-green; the refused
# names are already printed truthfully by dev-bin's attempted/ok/refused summary.
expose_dev_bin() {
  section "dev bins: expose stable package commands on PATH (dev checkout)"
  local rc
  set +e
  bash "$REPO_DIR/scripts/dev-bin.sh" expose
  rc=$?
  set -e

  if ! bash "$REPO_DIR/scripts/dev-bin.sh" verify entwurf; then
    return 1
  fi

  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 3 ]; then
    echo "[setup] dev-bin: foreign helper bin path(s) refused, never clobbered — the refused names are in the summary above." >&2
    echo "[setup]       Every unit was attempted independently; the source operator itself is certified." >&2
  else
    echo "[setup] dev-bin: helper exposure did not complete (rc=$rc; see above)." >&2
  fi
  return "$rc"
}

# release-gate — the single command that, when GREEN, is sufficient to cut
# release cuts. Runs the full static floor (`pnpm run check:full`) followed by the
# v2-native live gates, then emits one PASS/FAIL/SKIP summary. Everything is
# invoked through run.sh subcommands — never a script in scripts/ directly.
#
# Design invariants (NEXT Step 1e + GPT-5.5 reviews):
#   - v2-native live floor: the MUST tier is the v2 dispatch substrate
#     (smoke-entwurf-v2-matrix-live, opt-in
#     LIVE), the MCP bridge (check-bridge), and the resident citizen guard
#     (smoke-resident-garden-guard).
#   - ACP plugin acceptance floor (S0~S2g): the 11 ACP LIVE smokes
#     (socket-citizen/raw-turn/overlay/provider/session-reuse/carrier-augment/
#     memory-containment/rgg + S2g mcp/skill config passthrough + S2g axis-3 bundled-mcp resident/RPC
#     + S2g axis-4 v2-send: an ACP model SENDS via entwurf_v2 and lands as itself)
#     are MUST, not BEHAVIOR — they prove programmatic transport/provider/backend
#     invariants of the ACP plugin on the v2 core, so a failure is a release
#     defect, not an advisory model-in-loop signal. Each is LIVE-gated honest-SKIP.
#   - v1 entwurf verbs are gone (v2 core): the old xt-tool-surface / session-messaging
#     / sentinel floor gates do not exist on this tree. --allow-skip-gemini is
#     accepted-but-ignored (back-compat).
#   - Final release authorization is GLG's, not this script's: a green
#     run is necessary, and the operator closes the decision.
release_gate() {
  entwurf_require_step_outcome
  local -a positional=()
  local a
  # --cut is the EXECUTABLE half of "a CUT needs LIVE=1, SKIP=0" (P1). Without it
  # this stays the unattended diagnostic it has always been: SKIPs are reported
  # and the run still exits 0. With it, any MUST SKIP is red — including the
  # LIVE!=1 case, which needs no separate assertion because every LIVE-gated step
  # then skips on its own and the skip counter blocks.
  local cut_mode=0
  for a in "$@"; do
    case "$a" in
      --cut) cut_mode=1 ;;
      --allow-skip-gemini) ;;  # accepted-but-ignored: gemini removed from the claude-only floor (back-compat for existing scripts)
      *) positional+=("$a") ;;
    esac
  done
  local project_dir
  project_dir=$(normalize_project_dir "${positional[0]:-$PROJECT_DIR_DEFAULT}")

  # Absolute path to this script — survives the `cd "$project_dir"` below. The
  # live gates derive their pi session dir from $PWD (tmux `-c "$PWD"`,
  # PROJECT_DIR_DEFAULT, and the bare `pi -p` invocations that don't `cd`
  # themselves). Some gates (e.g. check-bridge and the garden guard) take no
  # project arg, so if release-gate runs from the repo their sessions could land
  # in the repo's own session dir — polluting the very
  # tree we ship and breaking the "scratch full gate" evidence claim. Running
  # EVERY live gate with PWD=project_dir makes a single
  # `./run.sh release-gate <scratch>` invocation route all sessions to scratch
  # regardless of the operator's cwd. `-e "$REPO_DIR/..."` (extension load) and
  # every other path the gates touch are absolute, so the cd is safe.
  #
  # The identity gate (smoke-resident-garden-guard) also takes no project arg
  # but is exempt from the repo-pollution concern by construction: it is wired
  # here as the NEGATIVE path only — a 0-token fail-fast that writes no session
  # file at all.
  #
  # smoke-acp-bundled-mcp-live is a DELIBERATE exception to the PWD=project_dir
  # routing: it runs its resident with cwd=os.tmpdir() and relies on the
  # operator's INSTALLED bundled bridge (global ~/.pi/agent/settings.json
  # entwurfProvider.mcpServers.entwurf-bridge) — that IS the operator circuit
  # this axis restores, not a scratch-isolated probe (that is smoke-acp-mcp-live's
  # job). It writes only a tmpdir-cwd session (no repo pollution) and fails loud if
  # the operator has not wired the bundled bridge.
  local self="$REPO_DIR/run.sh"
  gate() { ( cd "$project_dir" && "$@" ); }

  local pass=0 failc=0 skip=0
  local -a results=()

  run_step() {
    local name="$1"; shift
    section "release-gate step: $name"
    if "$@"; then
      ok "$name: PASS"
      results+=("PASS  $name"); pass=$((pass + 1))
    else
      fail "$name: FAIL"
      results+=("FAIL  $name"); failc=$((failc + 1))
    fi
  }

  # LIVE-gated MUST step: a release-blocking gate that needs a real backend turn
  # (auth/model/credit). It is ALWAYS INVOKED and the step itself reports whether
  # it could run — that is the whole point of P1. The old shape asked `LIVE=1?`
  # here and skipped without calling, which meant the summary asserted a skip it
  # had never confirmed, while a step that WAS called could still exit 0 on a
  # missing prerequisite (Cortex without a connection) and be counted PASS.
  # Now one protocol decides: exit 0 = PASS, $ENTWURF_STEP_SKIP_EXIT = SKIP,
  # anything else = FAIL. A SKIP is never rounded up, and `--cut` refuses any.
  #
  # `LIVE` is NOT forced here — it rides the operator's environment into the
  # child, so `LIVE=1 ./run.sh release-gate` runs the step for real and a bare
  # invocation gets the step's own honest skip.
  run_live_step() {
    local name="$1"; shift
    section "release-gate step: $name"
    local rc=0
    "$@" || rc=$?
    case "$(entwurf_step_outcome "$rc")" in
      PASS)
        ok "$name: PASS"
        results+=("PASS  $name"); pass=$((pass + 1))
        ;;
      SKIP)
        warn "$name: SKIP — the step declined a prerequisite it does not have (see its [entwurf:skip] line above). NOT a live acceptance."
        results+=("SKIP  $name"); skip=$((skip + 1))
        ;;
      *)
        fail "$name: FAIL (exit $rc)"
        results+=("FAIL  $name"); failc=$((failc + 1))
        ;;
    esac
  }

  # BEHAVIOR lane (0.11.0, GLG+GPT+Opus): a SEPARATE advisory counter for
  # model-in-loop gates that probe whether the *model* autonomously selects the
  # MCP entwurf surface (vs. bypassing via Bash/Terminal/pi-CLI). Scope note
  # (2026-07-24): a gate that TELLS the model which tool to call does NOT belong
  # here. That was tried for smoke-acp-v2-send-live on a PASS/PASS/FAIL sample
  # read as instruction-following flake, and the reading was wrong — in both
  # failures the tool was simply ABSENT from the session's schema (one model called
  # it and the RUNTIME answered "No such tool available"; the other read the schema,
  # saw no such tool, and declined to invent a result). An MCP readiness defect of
  # ours, either way. Advisory is for what the model chooses, never for what our
  # wiring fails to deliver. These gates
  # are flaky by the model's nature (Claude Sonnet's MCP-vs-Bash choice is
  # non-deterministic on 0.79.4), so a single flake must NOT block the cut. They
  # are NEVER folded into `failc`/`pass` — exit authority below is `failc` only.
  # Honesty rails: (1) "non-blocking" is NOT "pass" — a BEHAVIOR-FAIL is surfaced
  # loudly in the summary with its artifact path, never buried; (2) a Bash-bypass
  # of the entwurf surface stays a hard FAIL *inside* this lane — a bypass is
  # never relabelled a pass; (3) the entwurf_v2 surface itself is proven by the
  # deterministic/programmatic must-pass gates above (check-entwurf-v2-*,
  # check-bridge) — this lane is autonomous-tool-selection *behavior*, not
  # *function*. Residual bypass → 0.11.x usability lane.
  # The lane speaks the same STEP OUTCOME protocol (P1) so a missing prerequisite
  # here is a BEHAVIOR-SKIP, not a fabricated BEHAVIOR-PASS or a misread
  # BEHAVIOR-FAIL. Advisory semantics are untouched: none of these counters ever
  # reaches `failc`, and `--cut` reads the MUST skip counter only.
  local behavior_pass=0 behavior_failc=0 behavior_skip=0
  local -a behavior_results=()

  run_behavior_step() {
    local name="$1"; shift
    section "release-gate BEHAVIOR step (advisory, non-blocking): $name"
    local rc=0
    "$@" || rc=$?
    case "$(entwurf_step_outcome "$rc")" in
      PASS)
        ok "$name: BEHAVIOR-PASS"
        behavior_results+=("BEHAVIOR-PASS  $name"); behavior_pass=$((behavior_pass + 1))
        ;;
      SKIP)
        warn "$name: BEHAVIOR-SKIP — prerequisite absent (advisory lane; not a signal either way)"
        behavior_results+=("BEHAVIOR-SKIP  $name"); behavior_skip=$((behavior_skip + 1))
        ;;
      *)
        warn "$name: BEHAVIOR-FAIL (advisory — model-in-loop signal; S7=Bash-bypass stays hard-fail here; NOT a cut blocker)"
        behavior_results+=("BEHAVIOR-FAIL  $name"); behavior_failc=$((behavior_failc + 1))
        ;;
    esac
  }

  # 1. Static floor (deterministic; the FULL tier — core plus hermetic/package —
  #    never the ≤60s everyday core alone).
  section "release-gate step: static (pnpm run check:full)"
  if (cd "$REPO_DIR" && pnpm run check:full); then
    ok "static (pnpm run check:full): PASS"
    results+=("PASS  static (pnpm run check:full)"); pass=$((pass + 1))
  else
    fail "static (pnpm run check:full): FAIL"
    results+=("FAIL  static (pnpm run check:full)"); failc=$((failc + 1))
  fi

  # 1b. Discriminating power of that floor. The mutant-EXECUTING body left the
  # default check chains (operator inner-loop cost) — only its head rides along,
  # as check-gate-manifests inside check:hermetic — so release acceptance carries
  # the body explicitly as its own MUST step: a cut must re-prove the gates still
  # kill what they claim to kill.
  section "release-gate step: check-gate-qualification"
  if (cd "$REPO_DIR" && bash "$self" check-gate-qualification); then
    ok "check-gate-qualification: PASS"
    results+=("PASS  check-gate-qualification"); pass=$((pass + 1))
  else
    fail "check-gate-qualification: FAIL"
    results+=("FAIL  check-gate-qualification"); failc=$((failc + 1))
  fi

  # 2. (gemini-availability step removed — claude-only floor; gemini CLI is
  #    deprecated, so the gate no longer asserts a three-backend claim.)

  # 3. Live per-invariant gates (each is a run.sh subcommand). Every one runs
  #    with PWD=project_dir (via gate()) so cwd-derived pi session dirs land in
  #    the scratch project, never the repo — see the note above.
  #
  #    The foundational identity gate runs first: the resident --entwurf-control
  #    citizen discipline (#50 C2: a raw resident becomes a record-backed citizen
  #    on a record-keyed socket, and a re-open attaches to the same address). If
  #    the identity foundation is broken, every Entwurf live gate below is
  #    meaningless, so fail fast here. (The old smoke-session-id-name substrate
  #    proof is gone with the substrate itself — #50 C3; smoke-pi-attach carries
  #    the deterministic half inside pnpm run check:full.)
  # RGG split: the 0-token half (BIRTH: record + record-keyed socket / ATTACH:
  # re-open keeps the address / REPLACEMENT: in-process /new is pi's again) is
  # release-blocking and stays here as a must-pass with SMOKE_RGG_POSITIVE=0. The
  # model-in-loop half (one turn completing transcriptPath + model on the record)
  # is gated behind SMOKE_RGG_POSITIVE=1 in the BEHAVIOR lane below.
  run_step "smoke-resident-garden-guard (3c citizen: record birth / record-keyed socket / attach-on-reopen, 0-token)" gate env SMOKE_RGG_POSITIVE=0 bash "$self" smoke-resident-garden-guard
  run_step "check-bridge"                   gate bash "$self" check-bridge
  # check-bridge booted the launcher THIS CHECKOUT ships; this boots the invocation the operator's
  # pi provider actually EXECS. Two different strings, and only the second one reaches a live ACP
  # session. 2026-08-19 measured the gap at full price: `~/.local/bin/entwurf-bridge` had been
  # relocated onto a pnpm cmd-shim (basedir derived from $0, so not relocatable), it exited 127, the
  # bundled bridge never booted, and the model had no `mcp__entwurf-bridge__*` tool — while
  # `command -v` answered yes throughout. #81's probe already settles that in under a second and
  # doctor-pi-provider consumes it; it was simply never a step, so the verdict first surfaced at
  # smoke-acp-bundled-mcp-live, sixteen LIVE steps and ~20 minutes of real model spend later.
  # `run_step`, not `run_live_step`: this doctor is not LIVE-gated and never emits 97, so it has no
  # prerequisite to decline. It exits 1 for a configured invocation that will not boot and for
  # state-owned drift; a host that never installed the circuit keeps its existing exit 0 note, and
  # the bundled smokes below still fail loud there. So this tightens nothing — it only moves an
  # existing red earlier. cwd is REPO_DIR regardless of `gate` (run_ts cds there), so the scope
  # judged is this checkout's `.pi/settings.json` shadowing the operator's global: deterministic,
  # but not in principle the smokes' global-only subject if the two ever diverge.
  # Position and classifier arm are pinned by [QK:PI-DOCTOR-IS-RELEASE-MUST].
  run_step "doctor-pi-provider (#81: the operator's CONFIGURED bridge invocation actually boots)" gate bash "$self" doctor-pi-provider
  # D4-c: the v2 dispatch substrate sentinel (5d-5). A SINGLE run (NOT backend-looped — it proves
  # production runEntwurfV2 deps + real pi control-socket RPC + real mailbox enqueue + v2 lock, not
  # per-backend model behavior). Placed right after check-bridge: the MCP/protocol substrate must be
  # green first so a matrix-live failure reads as "v2 transport/lock/enqueue", not bridge basics.
  # Opt-in LIVE: it spawns a real `pi --entwurf-control` (needs auth/model), so a missing
  # prerequisite is an HONEST SKIP (not a PASS) — an unattended release-gate stays runnable without
  # faking coverage. Independent of --allow-skip-gemini (now a no-op back-compat flag on the
  # claude-only floor; this gates substrate auth). It used to carry its own inline copy of the
  # PASS/FAIL/SKIP branch; P1 folded it onto `run_live_step` so there is exactly ONE classifier —
  # a second copy is how a lane silently keeps counting a skip as a pass.
  run_live_step "smoke-entwurf-v2-matrix-live (D4-c: v2 dispatch substrate sentinel)" gate bash "$self" smoke-entwurf-v2-matrix-live
  # The spawn-bg resident-lifecycle acceptance that used to sit here left with the transport in the
  # visible-first cut. A same-id resume lane will need its own acceptance step; it does not inherit
  # this one, because what that step proved was a HIDDEN child standing its socket up.

  # 3b. ACP plugin acceptance floor (S0~S2f live). These prove the ACP plugin's
  #     programmatic transport/provider/backend invariants on the v2 core — NOT
  #     model-in-loop autonomous tool-selection — so they belong in the MUST tier,
  #     not BEHAVIOR. Their deterministic counterparts (check-acp-*, check-auth-
  #     boundary, check-acp-overlay/tool-surface/event-mapper/prompt-builder/
  #     session-store/session-reuse/carrier-augment) already run inside `pnpm
  #     check` above; these are the LIVE acceptance halves. Ordered from the
  #     cheapest, most foundational invariant outward: turn-free citizenship →
  #     pinned ACP pipe/auth → overlay/tool meta → real pi provider path (+
  #     progress visibility / L3 marker) → process-scoped reuse + semantic recall
  #     → first-user augment delivery + empty-carrier billing-clean (핀1) →
  #     ACP-target garden guard (deterministic half). Opt-in LIVE: LIVE!=1 is an
  #     HONEST SKIP via run_live_step (see its note) — a CUT needs LIVE=1, SKIP=0.
  run_live_step "smoke-acp-socket-citizen-live (S1: turn-free socket citizenship)"        gate bash "$self" smoke-acp-socket-citizen-live
  run_live_step "smoke-acp-raw-turn-live (S2a: pinned ACP pipe + local auth)"             gate bash "$self" smoke-acp-raw-turn-live
  run_live_step "smoke-acp-overlay-live (S2b: config overlay + hooks:{} + tool meta)"     gate bash "$self" smoke-acp-overlay-live
  run_live_step "smoke-acp-provider-live (S2c/S2f: real pi provider path + progress/L3)"  gate bash "$self" smoke-acp-provider-live
  run_live_step "smoke-acp-session-reuse-live (S2d: process-scoped reuse + recall)"       gate bash "$self" smoke-acp-session-reuse-live
  run_live_step "smoke-acp-carrier-augment-live (S2e-1: augment delivery + 핀1 billing)"  gate bash "$self" smoke-acp-carrier-augment-live
  run_live_step "smoke-acp-memory-containment-live (Gate D: no overlay memory leak)"      gate bash "$self" smoke-acp-memory-containment-live
  run_live_step "smoke-acp-rgg-live (S2e-2: ACP-target garden guard, deterministic half)" gate bash "$self" smoke-acp-rgg-live
  run_live_step "smoke-acp-mcp-live (S2g: operator mcpServers reach the live ACP session)"  gate bash "$self" smoke-acp-mcp-live
  run_live_step "smoke-acp-skill-live (S2g: operator skillPlugins reach the live ACP session)" gate bash "$self" smoke-acp-skill-live
  run_live_step "smoke-acp-bundled-mcp-live (S2g axis 3: bundled entwurf-bridge via 0.11.0 resident/RPC circuit)" gate bash "$self" smoke-acp-bundled-mcp-live
  run_live_step "smoke-acp-v2-send-live (S2g axis 4: an ACP model SENDS via entwurf_v2, landing as itself)" gate bash "$self" smoke-acp-v2-send-live

  # 3c. The axes the aggregate used to leave out with no stated reason (P2,
  #     2026-07-31). Three LIVE smokes existed and were simply never wired, so a
  #     green cut said nothing about them. Under the P1 outcome protocol wiring
  #     them costs nothing on a host that cannot run them — they SKIP honestly and
  #     `--cut` names the missing prerequisite — while a host that CAN run them now
  #     must. Cortex is deliberately NOT here: its rail needs an external Snowflake
  #     connection the HOST owns, so wiring it would block every cut taken without
  #     that account; it stays a required DIRECT call for a Cortex-rail cut instead
  #     (VERIFY 「Cortex is an on-demand axis」). Same for `smoke-acp-long-turn-live`,
  #     `smoke-agy-native-push-live` and `smoke-acp-ordering-probe-live`: >12min by
  #     construction, no aggregate-owned agy conversation id, and an opt-in instrument
  #     rather than acceptance. check-release-gate-outcomes pins that every LIVE smoke
  #     is either wired here or excluded by a reason the docs still carry.
  run_live_step "smoke-claude-native-resume-live (native Claude Code resume + meta-bridge neutrality)" gate bash "$self" smoke-claude-native-resume-live
  run_live_step "smoke-entwurf-chain-live (P3: Claude Code -> pi GPT -> pi ACP Sonnet -> mailbox, identity + receipt)" gate bash "$self" smoke-entwurf-chain-live
  run_live_step "smoke-mux-lifecycle-live (mux public-harness lifecycle: fresh -> send -> dormant -> same-id visible resume -> recall)" gate bash "$self" smoke-mux-lifecycle-live
  # #87 bundle B: MUST, and since bundle B moved omp's wakeMode to self-fetch this is a
  # REAL demand under LIVE=1, not a standing SKIP — it reads the registry, so an honest
  # SKIP now only ever names a missing prerequisite, and a registry claiming a receive
  # rail with no acceptance body here is a FAIL.
  run_live_step "smoke-omp-receive-live (#87 bundle B: other harness -> open omp citizen, addressed receive + roundtrip)" gate bash "$self" smoke-omp-receive-live
  # #87 bundle C: the step 9 clause 7 receipt, wired as a MUST rather than left to an
  # operator's memory. A schema is not a product — omp's bootstrap-payload submission
  # PARSES correctly, and parsing is exactly what pi got right while submitting no message
  # at all, so a release whose fresh_call(omp) opens a window that never runs its turn
  # would pass every deterministic gate here. That is not hypothetical for this backend:
  # the retired positional candidate parsed perfectly and still answered `ACK` with zero
  # tool calls, because the turn began before the callback tool existed. New contract,
  # applied from omp onward; it does not retroactively redesign Copilot's operator-metered
  # exclusion.
  run_live_step "smoke-omp-fresh-live (#87 bundle C: entwurf_fresh_call opens omp, exact nonce callback, addressed receive)" gate bash "$self" smoke-omp-fresh-live

  # 4. BEHAVIOR lane (advisory, non-blocking). Model-in-loop gates that probe
  #     whether the model AUTONOMOUSLY drives the MCP entwurf surface. These never
  #     touch `failc`; the cut is decided by the MUST tier above.
  #
  #     Only genuinely flaky model-in-loop signals live here. Programmatic ACP
  #     plugin invariants are MUST (section 3b above), not BEHAVIOR — a failed
  #     transport/provider/backend smoke is a release defect, not advisory. The old
  #     v1 floor gates (session-messaging / xt-tool-surface / sentinel) do not exist
  #     on the v2 core — the v1 entwurf verbs they exercised are gone.
  # SMOKE_RGG_POSITIVE=1 re-runs the FULL guard with its positive enabled (not a
  # positive-only mode) — the 0-token cells run again here too, but the one
  # model-in-loop turn (turn_end completing the record's transcriptPath + model) is
  # the reason this run is advisory; the 0-token half is already release-blocking
  # via the POSITIVE=0 must-pass step above.
  run_behavior_step "smoke-resident-garden-guard (positive enabled: one turn completes the record's transcriptPath + model)" gate env SMOKE_RGG_POSITIVE=1 bash "$self" smoke-resident-garden-guard

  # 5. Summary — two tiers. MUST is release-blocking and owns the exit code; the
  #    word "green" is reserved for the MUST tier. BEHAVIOR is advisory and is
  #    surfaced (with per-step artifact paths above) but never blocks the cut.
  section "release-gate summary"
  echo "  MUST (release-blocking):"
  printf '    %s\n' "${results[@]}"
  echo "    MUST: PASS=$pass  FAIL=$failc  SKIP=$skip"
  echo ""
  echo "  BEHAVIOR (advisory, non-blocking — model-in-loop autonomous MCP tool-selection):"
  if [ "${#behavior_results[@]}" -gt 0 ]; then
    printf '    %s\n' "${behavior_results[@]}"
  fi
  echo "    BEHAVIOR: PASS=$behavior_pass  FAIL=$behavior_failc  SKIP=$behavior_skip"
  echo "  (per-step artifact paths are printed in each step's output above)"
  if [ "$behavior_failc" -gt 0 ]; then
    echo ""
    warn "BEHAVIOR FAIL present ($behavior_failc) — advisory model-in-loop signal (e.g. S7 Bash-bypass / entwurf_self not autonomously called). Tracked, NOT a cut blocker; see the 0.11.x usability lane."
  fi
  echo ""
  if [ "$cut_mode" = "1" ]; then
    echo "  mode: --cut (a MUST SKIP is a BLOCKER — this run is being read as release acceptance)"
  else
    echo "  mode: diagnostic (MUST SKIPs are reported, not blocking — re-run with --cut to read this as acceptance)"
  fi
  # The verdict as one greppable token, so release evidence can distinguish a
  # step that RAN AND BROKE from one that NEVER RAN without reading prose. The
  # counters above stay literal — a policy block is `FAIL=0 SKIP=n` plus
  # `BLOCKED (MUST SKIP)`, never a synthesized failure.
  echo "  $(entwurf_release_verdict "$failc" "$skip" "$cut_mode")"

  # Exit authority — MUST tier only, BEHAVIOR never blocks. The releasable
  # decision lives in scripts/lib/step-outcome.sh so it is one testable function
  # rather than a branch re-derived here (and re-derived wrong: the pre-P1 branch
  # read `failc` alone, so a run with 14 SKIPs still printed "all green").
  if ! entwurf_release_releasable "$failc" "$skip" "$cut_mode"; then
    echo ""
    if [ "$failc" -gt 0 ]; then
      fail "release-gate MUST NOT green — $failc release-blocking step(s) failed. Current release is NOT releasable."
    else
      fail "release-gate --cut REFUSED — $skip release-blocking step(s) SKIPPED, so this run does not prove they were called."
      echo "  A skipped step is not acceptance. Supply each missing prerequisite (usually LIVE=1 plus the"
      echo "  per-step env the [entwurf:skip] lines above name) and re-run, or drop --cut to keep this a diagnostic."
    fi
    echo "  A green MUST gate is necessary but not sufficient; GLG closes the call."
    return 1
  fi
  if [ "$skip" -gt 0 ]; then
    warn "release-gate MUST has no failures, but $skip step(s) SKIPPED — this is a DIAGNOSTIC run, not live acceptance. A cut needs \`LIVE=1 ./run.sh release-gate <scratch> --cut\` with SKIP=0."
  elif [ "$behavior_failc" -gt 0 ]; then
    ok "release-gate MUST PASS (all release-blocking steps ran and are green); BEHAVIOR FAIL present (advisory). Necessary condition met — GLG authorizes the cut."
  else
    ok "release-gate MUST PASS + BEHAVIOR PASS — all green. Necessary condition met — GLG authorizes the cut."
  fi
  return 0
}

cmd=${1:-}
case "$cmd" in
  setup)
    setup_all "$TARGET_PROJECT_DIR"
    ;;
  release-gate)
    shift || true
    release_gate "$@"
    ;;
  check-bridge)
    check_bridge
    ;;
  check-model-lock)
    check_model_lock
    ;;
  check-shell-quote)
    check_shell_quote
    ;;
  check-install-surface)
    # 0.12.7 — structural half of the node_modules strip-types fence: run_ts is the only
    # crossing, every operator subcommand has a compiled twin, bin wrappers branch, dev
    # gates stay out of the tarball, and offline smokes never touch the real $HOME.
    # check-pack-install owns the dynamic half (it drives the installed commands).
    run_ts scripts/check-install-surface.ts
    ;;
  check-entwurf-session-identity)
    check_entwurf_session_identity
    ;;
  check-meta-session)
    check_meta_session
    ;;
  check-meta-v3-record)
    check_meta_v3_record
    ;;
  check-mailbox-receipt-state)
    check_mailbox_receipt_state
    ;;
  check-entwurf-capabilities)
    check_entwurf_capabilities
    ;;
  check-harness-admission-parity)
    check_harness_admission_parity
    ;;
  check-omp-fresh-preflight)
    check_omp_fresh_preflight
    ;;
  smoke-omp-fresh-live)
    smoke_omp_fresh_live
    ;;
  check-capability-bundle-reach)
    check_capability_bundle_reach
    ;;
  check-bridge-delivery)
    check_bridge_delivery
    ;;
  smoke-pi-attach)
    smoke_pi_attach
    ;;
  check-meta-mailbox-state-write)
    check_meta_mailbox_state_write
    ;;
  check-meta-receiver-marker)
    check_meta_receiver_marker
    ;;
  check-meta-hook-session-switch)
    check_meta_hook_session_switch
    ;;
  check-meta-identity-consumers)
    check_meta_identity_consumers
    ;;
  check-hook-launch-topology)
    check_hook_launch_topology
    ;;
  check-copilot-birth-hook)
    check_copilot_birth_hook
    ;;
  check-omp-birth-hook)
    # #87 gate: the OMP BIRTH path without omp. Drives the real assembler into a temp dir,
    # then imports the ASSEMBLED index.ts into a mock omp host (mock ExtensionAPI + mock
    # ExtensionContext) and fires the two birth edges. Requires: a backend:"omp" v3 record
    # only under mode "tui"; NOTHING under print/rpc/json (a task subagent is not a citizen,
    # and hasUI is deliberately true on the rpc rows because it is true in the vendor too);
    # session_switch attaching on the same native id and minting the replacement on a new
    # one; a sender marker keyed to the HOST process's OWN pid (never its parent — the
    # one-process join) that the production resolver joins back to the record; the garden id
    # on the status line; and still zero mailbox/receiver marker. Hermetic; no omp, no model turn
    run_ts scripts/check-omp-birth-hook.ts
    ;;
  check-copilot-statusline)
    check_copilot_statusline
    ;;
  check-copilot-launch)
    check_copilot_launch
    ;;
  check-copilot-receive-arm)
    check_copilot_receive_arm
    ;;
  check-meta-capability-source)
    check_meta_capability_source
    ;;
  check-socket-probe)
    check_socket_probe
    ;;
  check-project-trust-handler)
    check_project_trust_handler
    ;;
  check-entwurf-v2-contract)
    check_entwurf_v2_contract
    ;;
  check-entwurf-v2-lock)
    check_entwurf_v2_lock
    ;;
  check-entwurf-v2-decider)
    check_entwurf_v2_decider
    ;;
  check-entwurf-v2-matrix)
    check_entwurf_v2_matrix
    ;;
  check-entwurf-v2-release)
    check_entwurf_v2_release
    ;;
  check-entwurf-v2-send)
    check_entwurf_v2_send
    ;;
  check-entwurf-v2-send-fallback)
    check_entwurf_v2_send_fallback
    ;;
  check-entwurf-v2-mailbox)
    check_entwurf_v2_mailbox
    ;;
  check-entwurf-v2-native-push)
    check_entwurf_v2_native_push
    ;;
  check-entwurf-v2-runner)
    check_entwurf_v2_runner
    ;;
  check-entwurf-control-rpc)
    check_entwurf_control_rpc
    ;;
  check-entwurf-v2-production)
    check_entwurf_v2_production
    ;;
  check-entwurf-v2-surface)
    check_entwurf_v2_surface
    ;;
  check-entwurf-bridge-boot)
    check_entwurf_bridge_boot
    ;;
  check-entwurf-bridge-pi-free)
    check_entwurf_bridge_pi_free
    ;;
  check-entwurf-resume-args)
    check_entwurf_resume_args
    ;;
  check-resume-launch-identity)
    check_resume_launch_identity
    ;;
  check-mux-placement)
    check_mux_placement
    ;;
  check-mux-placement-tmux)
    check_mux_placement_tmux
    ;;
  check-mux-launch)
    check_mux_launch
    ;;
  check-mux-fresh-call)
    check_mux_fresh_call
    ;;
  check-mux-resume-call)
    check_mux_resume_call
    ;;
  check-mux-parent-artifact)
    check_mux_parent_artifact
    ;;
  check-mux-launcher-fence)
    check_mux_launcher_fence
    ;;
  check-entwurf-v2-visible-resume)
    check_entwurf_v2_visible_resume
    ;;
  smoke-mux-fresh-call-live)
    smoke_mux_fresh_call_live
    ;;
  smoke-mux-lifecycle-live)
    smoke_mux_lifecycle_live
    ;;
  check-mux-launch-tmux)
    check_mux_launch_tmux
    ;;
  smoke-entwurf-v2-matrix-live)
    smoke_entwurf_v2_matrix_live
    ;;
  smoke-acp-raw-turn-live)
    smoke_acp_raw_turn_live
    ;;
  smoke-acp-overlay-live)
    smoke_acp_overlay_live
    ;;
  smoke-acp-memory-containment-live)
    smoke_acp_memory_containment_live
    ;;
  smoke-acp-provider-live)
    smoke_acp_provider_live
    ;;
  smoke-acp-long-turn-live)
    smoke_acp_long_turn_live
    ;;
  smoke-acp-session-reuse-live)
    smoke_acp_session_reuse_live
    ;;
  smoke-acp-mcp-live)
    smoke_acp_mcp_live
    ;;
  smoke-acp-skill-live)
    smoke_acp_skill_live
    ;;
  smoke-acp-bundled-mcp-live)
    smoke_acp_bundled_mcp_live
    ;;
  smoke-omp-receive-live)
    # #87 bundle B — the acceptance that makes omp's one-way garden executable.
    # Reads the capability registry and reports its own PASS/SKIP/FAIL; see the
    # header of the script for the three branches.
    run_ts scripts/smoke-omp-receive-live.ts
    ;;
  smoke-entwurf-chain-live)
    # P3 — the cross-harness delivery CHAIN on real authenticated rails:
    # native Claude Code -> pi GPT -> pi ACP Claude Sonnet -> mailbox terminus,
    # with sender identity at every hop and a read receipt at the end. Needs
    # `claude` on PATH plus pi credentials for both pi backends; each missing
    # prerequisite is an honest protocol SKIP, never a pass.
    #   LIVE=1 ./run.sh smoke-entwurf-chain-live
    run_ts scripts/smoke-entwurf-chain-live.ts
    ;;
  smoke-acp-v2-send-live)
    smoke_acp_v2_send_live
    ;;
  smoke-acp-carrier-augment-live)
    smoke_acp_carrier_augment_live
    ;;
  smoke-acp-rgg-live)
    smoke_acp_rgg_live
    ;;
  smoke-acp-cortex-live)
    smoke_acp_cortex_live
    ;;
  smoke-acp-socket-citizen-live)
    smoke_acp_socket_citizen_live
    ;;
  check-entwurf-facts)
    check_entwurf_facts
    ;;
  check-control-socket-path)
    check_control_socket_path
    ;;
  check-socket-discovery)
    check_socket_discovery
    ;;
  check-meta-listing)
    check_meta_listing
    ;;
  check-meta-facts)
    check_meta_facts
    ;;
  check-entwurf-fact-provider)
    check_entwurf_fact_provider
    ;;
  check-entwurf-peers-surface)
    check_entwurf_peers_surface
    ;;
  check-entwurf-self-address)
    check_entwurf_self_address
    ;;
  check-entwurf-deliverability)
    check_entwurf_deliverability
    ;;
  check-native-push-adapter)
    check_native_push_adapter
    ;;
  check-native-push-register)
    check_native_push_register
    ;;
  check-agy-sender-identity)
    check_agy_sender_identity
    ;;
  new-session-id)
    # Print one fresh garden sessionId (SSOT: generateSessionId). #50 C2 retired
    # the operator-launcher --session-id injection; the record layer is the
    # consumer that mints garden addresses. Stdout = the id only.
    run_ts scripts/new-session-id.ts
    ;;
  smoke-resident-garden-guard)
    # LIVE negative (0 tokens) + opt-in positive gate for the resident
    # --entwurf-control garden-native enforcement. NEGATIVE: raw uuid session
    # must blow up before any turn. POSITIVE (SMOKE_RGG_POSITIVE=1): garden id
    # passes + control-tagged name.
    (cd "$REPO_DIR" && bash scripts/smoke-resident-garden-guard.sh)
    ;;
  smoke-meta-async-drift)
    # 1.0.0 meta-bridge step 1 (#30): drift sentinel + capability gate. DEFAULT is
    # deterministic/offline — version pins (Claude/codex/agy) + Claude-binary
    # undocumented-behavior marker cross-validation; SCREAMS on drift. LIVE=1 adds
    # the plugin SessionStart watch-arm probe (spawns one metered claude -p).
    (cd "$REPO_DIR" && bash scripts/smoke-meta-async-drift.sh)
    ;;
  smoke-meta-honesty)
    # 1.0.0 meta-bridge HONESTY regression gate (#30 bbot release blockers): the
    # doorbell must count EVERY queued message honestly (blocker #1), and the
    # runtime hook must log a silent registration miss as ` ERROR ` for the doctor
    # to catch while staying best-effort (blocker #2). Offline + deterministic (no
    # claude binary; deps bash+node+python3), so unlike the drift sentinel it is
    # CI/pnpm-check safe.
    (cd "$REPO_DIR" && bash scripts/smoke-meta-honesty.sh)
    ;;
  smoke-meta-prune)
    # 1.0.0 meta-bridge Phase 4 regression gate: synthetic store covering every
    # class (keep/orphan/stale/duplicate/corrupt/drift) proves meta-bridge-prune
    # classifies correctly, exits 0, and deletes NOTHING (listing-only invariant).
    # Offline/deterministic (deps: bash+node).
    (cd "$REPO_DIR" && bash scripts/smoke-meta-prune.sh)
    ;;
  smoke-meta-keyset-guard)
    # 0.10.0 meta-bridge regression gate: the PREVENTIVE keyset guard
    # (check-keyset-overlap) + managed-keys SSOT. Synthetic fragments prove a
    # disjoint consumer passes and exact/array/parent-child collisions fail loud.
    # Offline/hermetic (deps: bash+python3).
    (cd "$REPO_DIR" && bash scripts/smoke-meta-keyset-guard.sh)
    ;;
  check-meta-manifest-schema)
    # 0.12.2 meta-bridge: deterministic, CLI-version-INDEPENDENT guard. `claude plugin
    # validate` is a CLOSED schema whose allowed keyset differs by version, so a
    # decorative key (0.12.1's root `description`) passed on the dev box but broke
    # install on the floor Claude. This pins the committed manifests to the minimal
    # validated keyset and asserts desired_mcp()'s installed-vs-clone dual-mode.
    # Offline/hermetic (deps: python3).
    (cd "$REPO_DIR" && python3 scripts/check-meta-manifest-schema.py)
    ;;
  smoke-meta-install-state)
    # 1.0.0 meta-bridge Phase 2 regression gate: state file captures pre-install
    # values, install/uninstall touches only the managed keyset, uninstall refuses
    # to guess without state, and the doctor store scan fails on corrupt/
    # duplicate/drift records. Offline + deterministic (deps bash+node+python3).
    (cd "$REPO_DIR" && bash scripts/smoke-meta-install-state.sh)
    ;;
  check-meta-doctor-oracle)
    # 0.12.8 (#51): detection-power gate for the release ORACLE itself. doctor-meta-bridge
    # decides whether a host is certified, yet its GREEN path had no coverage — the two
    # existing doctor drives both expect exit 1 and neither has a plugin cache, so the
    # installed-form classification and synthetic owner join never ran under any gate.
    # This stands up a healthy fixture (real assembly + planted cache + live owner +
    # fake bridge), proves PASS, then plants 21 defects that must each turn it red WITH
    # THE MESSAGE THAT NAMES THEM. Offline + deterministic (deps bash+node+python3).
    (cd "$REPO_DIR" && bash scripts/check-meta-doctor-oracle.sh)
    ;;
  smoke-agy-install-state)
    # 봉인 8 regression gate for the agy MCP install adapter: install→doctor→uninstall in an
    # ISOLATED HOME+XDG with a fake stable bin + fake pgrep/ss — adopt (preserve unrelated) +
    # state, doctor static-clean/live-SKIP (+live-PASS with a fake agy), honest-inverse
    # uninstall, symlink refuse, dangling FAIL, create-new inverse, and ⓪ checkout impurity 0.
    # Offline + deterministic (deps: bash+python3).
    (cd "$REPO_DIR" && bash scripts/smoke-agy-install-state.sh)
    ;;
  smoke-setup-verdict)
    # #86 C1 aggregate setup verdict fixture — the first automated consumer of
    # `entwurf setup` itself: all-absent SKIP/green, pi below-floor detected FAIL
    # (never SKIP), pi-present wiring PASS, agy detected+corrupt named FAIL with
    # NON-GREEN nonzero exit, installed-mode named branch before the bootstrap,
    # and the credential store byte-identical in every cell. Sandboxed HOME/XDG/
    # agent/dev-bin roots; presence pinned via PI_BIN/CLAUDE_BIN/AGY_BIN.
    # Offline + deterministic (deps: bash+node+python3+pnpm).
    (cd "$REPO_DIR" && bash scripts/smoke-setup-verdict.sh)
    ;;
  check-agy-permission-matrix)
    # The agy permission engine's CONTRACT SPACE as a literal table (55 cells + stated
    # exclusions R2/R4-R7): parser-state × operation × settings × ownership × precedence.
    # Every recent permission defect was an unenumerated cell of this matrix; this gate
    # states the axes and exhausts the meaningful product, with hand-written literal
    # expectations (oracle independence — nothing is read back from the SUT). Sandbox
    # per cell; offline + deterministic (deps: python3).
    (cd "$REPO_DIR" && python3 scripts/check-agy-permission-matrix.py)
    ;;
  check-gate-manifests)
    # The HEAD of check-gate-qualification, exposed on its own so the deterministic
    # floor can pay for it: the runner self-test (classifier truth table + synthetic
    # negatives) plus the REAL manifests — schema, global claim uniqueness, subjects
    # tracked and lstat-regular in the origin index, claim tokens exactly once in their
    # gate sources — plus the declared lane inventory. It executes ZERO mutants and
    # makes NO snapshot of this repo; the body (check-gate-qualification) owns that and
    # is unchanged. Cheap enough for check:hermetic (~8s).
    run_ts scripts/check-gate-qualification.ts --manifests-only
    ;;
  check-gate-qualification)
    # Kill-proof qualification — the gate-of-gates. Proves the committed defect mutants
    # (scripts/mutants/*.json) make their gates fail BOUNDED and FOR THE CLAIMED REASON
    # ([QK:<claim>] token on a failure line), inside an isolated snapshot repo under the
    # control→mutant→restore→control state machine; the real checkout is never written
    # (HEAD + work-surface content hash asserted identical before/after). The runner is negative-controlled
    # first: zero-match/multi-match/survived/wrong-reason/hang(+pgroup grandchild kill)/
    # control-red/impurity all must classify red before any real manifest counts.
    run_ts scripts/check-gate-qualification.ts
    ;;
  check-probe-ordering)
    # §11-7 ordering-probe gate (docs/acp-backend-rail.md §11-7): the raw-client seam is
    # only admissible "bound by a gate asserting it issues the same calls, arguments, and
    # order as the backend's real sequence" — this is that gate. Sameness over a recording
    # fake + backend.ts SOURCE pins (order/clientInfo/timeouts/permission policy), phase
    # attribution (set-model included), the probe-mode fixture's wire instrumentation
    # (real child, raw JSON-RPC, no API), the shared log's contract at its door — envelope
    # (the evidence line's own runId/marker/sort axis cannot be rewritten by a payload) AND
    # payload (every field the classifier judges on is typed there) — and the PURE
    # paired-verdict truth table.
    run_ts scripts/check-probe-ordering.ts
    ;;
  check-probe-cli-shim)
    # §11-7-c producer gate (docs/acp-backend-rail.md §11-7-c condition 5: "Byte-transparency,
    # backpressure, and exit/signal propagation are proved by a fake-CLI deterministic gate").
    # The shim sits on the production spawn path of a paid LIVE turn, so this drives it as a
    # REAL process against fake CLIs and asks what each defect would buy: fabricated absence
    # evidence (a malformed init reported as an empty name set, a boot report that does not
    # name what was actually exec'd), a destroyed turn (mangled bytes, a swallowed signal, a
    # crash reported as exit 0), or leaked operator state (a prefix env scrub, argv/env/prompt
    # body in the shared log). No API, no network, no cost.
    run_ts scripts/check-probe-cli-shim.ts
    ;;
  smoke-acp-ordering-probe-live)
    # §11-7 ordering probe — LIVE paired-run instrument, OUT of pnpm check. Control
    # (delay=0, must be visible AND callable) + interventions D1/D2 against the SAME
    # pins/config/fixture; classifies A/A-withheld/B/C/D-<phase> or P0/I0, preserves
    # the shared NDJSON log + classification under .probe-artifacts/ (gitignored).
    #   LIVE=1 ./run.sh smoke-acp-ordering-probe-live
    run_ts scripts/smoke-acp-ordering-probe-live.ts
    ;;
  smoke-agy-statusline-state)
    # #46 Task 1 regression gate for the agy statusLine install adapter: install→doctor→uninstall
    # in an ISOLATED HOME+XDG with a fake stable bin (entwurf-agy-statusline) + fake pgrep —
    # own the statusLine subtree WHOLE (preserve unrelated keys) + state (stable command, prior
    # subtree as preimage), doctor static-clean/live-SKIP (+live-consistent with a fake agy) /
    # drift-FAIL / dangling-command-FAIL / not-ours note, honest-inverse uninstall, symlink +
    # dangling-symlink refuse, create-new inverse, the truthful wire wrapper (detected refusal
    # → nonzero, #86 C6/C7), and checkout impurity 0. Offline + deterministic (deps: bash+python3).
    (cd "$REPO_DIR" && bash scripts/smoke-agy-statusline-state.sh)
    ;;
  smoke-agy-hooks-state)
    # #46 birth imprint regression gate: hooks.json named hook ownership + direct
    # PreInvocation stdin → upsertMetaSession antigravity record, isolated HOME/XDG/PI agent.
    (cd "$REPO_DIR" && bash scripts/smoke-agy-hooks-state.sh)
    ;;
  smoke-pi-provider-state)
    # #46 Task 2 regression gate for the pi provider install adapter: register-pi-provider.py
    # (ownership-classified install/remove, user+project scopes) + read-only doctor-pi-provider.ts
    # (effective shadow view). ISOLATED HOME+XDG + fake stable bin — user ownership matrix
    # (absent/managed-legacy/managed-current/user-override), state honest-inverse (legacy NOT
    # restored), sibling + legacy prune, project no-state strip, doctor effective/drift/dangling/
    # malformed/project-stale/'?', symlink refuse, and checkout impurity 0. Offline (bash+python3+node).
    (cd "$REPO_DIR" && bash scripts/smoke-pi-provider-state.sh)
    ;;
  smoke-agy-native-push-live)
    # 봉인 8 LIVE acceptance gate for the native-push (agy) delivery rail. Drives the REAL
    # antigravity adapter + register core + runEntwurfV2 (production deps) against a live agy
    # conversation (AGY_CONVERSATION_ID): probe route, register create/attach idempotency,
    # fire→native-push delivered, bogus-conv probe-indeterminate reject.
    # Meta-store is isolated to a temp dir (only the agy round-trip is real); honest SKIP when
    # LIVE!=1. doctor-static preflight FAILs before the agy bridge is wired (③).
    run_ts scripts/smoke-agy-native-push-live.ts
    ;;
  smoke-user-scope-citizen)
    # 0.12.6 install-boundary gate: register-pi-package.py is the shared
    # packages[] SSOT for project/user install and remove; user scope makes
    # --entwurf-control load from any cwd. Idempotent, preserves unrelated
    # packages/keys, remove is symmetric, corrupt settings fail loud; project
    # scope normalizes ITS OWN stale entries while user scope carries the #86 C2
    # explicit ownership contract (other owners refuse; takeover-user-scope moves).
    # The tripwire the 2026-07-03 `pi install` removal lacked.
    (cd "$REPO_DIR" && bash scripts/smoke-user-scope-citizen.sh)
    ;;
  smoke-claude-native-resume-live)
    # LIVE-only Detour A probe: two real Claude Code native turns (fresh +
    # --resume) in a scratch cwd. Verifies native resume works while the
    # meta-bridge only records backend=claude-code/nativeSessionId/transcriptPath
    # once. Not in pnpm check; does not use the ACP provider.
    (cd "$REPO_DIR" && bash scripts/smoke-claude-native-resume-live.sh)
    ;;
  install-meta-bridge)
    # 1.0.0 meta-bridge step 5: operator-grade GLOBAL install of the garden-native
    # receive plugin. Assembles a self-contained, node-path-baked copy under the
    # XDG data dir ($XDG_DATA_HOME/entwurf/meta-bridge/.assembled — dev clone and
    # installed package alike, never the checkout) and runs marketplace add +
    # install --scope user, so every native Claude Code session auto-loads it.
    # Idempotent; Linux is the only currently certified axis for the #51 repair cut.
    # Darwin fails loud as not-yet-verified because the strict doctor cannot currently
    # certify its live owner join; future validation may reopen it. Uninstall permits Darwin
    # so an older macOS install is not stranded without an honest inverse.
    (cd "$REPO_DIR" && bash scripts/meta-bridge-install.sh "$@")
    ;;
  uninstall-meta-bridge)
    # 1.0.0 meta-bridge Phase 2: honest inverse of install-meta-bridge. Uses the
    # install-state file to restore original scalar/map values and remove only the
    # permission-array entries entwurf added; without state it refuses to guess.
    (cd "$REPO_DIR" && bash scripts/meta-bridge-uninstall.sh "$@")
    ;;
  doctor-meta-bridge)
    # 1.0.0 meta-bridge Phase 2: the FAIL-LOUD surface. Proves toolchain (incl.
    # python3), stateful managed config, baked node path (NixOS store-churn guard),
    # global plugin install, USER MCP reach, meta-record store integrity, hook log
    # no-ERROR, and actual SessionStart creation evidence. A plugin present with
    # zero claude-code meta-records is a SILENT MISS -> non-zero exit.
    (cd "$REPO_DIR" && bash scripts/meta-bridge-doctor.sh "$@")
    ;;
  install-copilot-bridge)
    # #82: the Copilot BIRTH install. Deliberately not a mode of install-meta-bridge —
    # it assembles its OWN marketplace root (the Claude assembler copies one plugin out
    # of one root, so a shared marketplace.json would publish a missing `source`), it
    # bakes node+entry into the launcher rather than into the manifest (Copilot's exec
    # form is a single string with no argv beside it), and it wires NO MCP: a drain tool
    # for a mailbox nothing rings would advertise delivery this backend does not have.
    shift || true
    (cd "$REPO_DIR" && bash scripts/copilot-bridge-install.sh "$@")
    ;;
  uninstall-copilot-bridge)
    # #86 C3a: the package-owned inverse of install-copilot-bridge. The ownership state
    # is the sole removal authority (exact qualified id, exact marketplace name+path,
    # recorded assembly only); a failing vendor list is UNKNOWN and refuses; state is
    # deleted LAST so any partial failure keeps a rerun-repair authority. Never touches
    # the stale Claude unit and never uses --force.
    shift || true
    (cd "$REPO_DIR" && bash scripts/copilot-bridge-uninstall.sh "$@")
    ;;
  doctor-copilot-bridge)
    # #82: the fail-loud surface for the Copilot unit. Its red conditions differ from
    # the Claude doctor's on purpose: a Copilot session mints on its FIRST PROMPT, not
    # at session open, so "installed with zero records" is reported as NOT-YET rather
    # than as a silent miss. Red is a hook that RAN and failed.
    shift || true
    (cd "$REPO_DIR" && bash scripts/copilot-bridge-doctor.sh "$@")
    ;;
  install-copilot-statusline)
    (cd "$REPO_DIR" && bash scripts/copilot-statusline-bridge.sh install "$@")
    ;;
  uninstall-copilot-statusline)
    (cd "$REPO_DIR" && bash scripts/copilot-statusline-bridge.sh uninstall "$@")
    ;;
  doctor-copilot-statusline)
    (cd "$REPO_DIR" && bash scripts/copilot-statusline-bridge.sh doctor "$@")
    ;;
  smoke-copilot-statusline-state)
    (cd "$REPO_DIR" && bash scripts/smoke-copilot-statusline-state.sh)
    ;;
  install-copilot-mcp)
    (cd "$REPO_DIR" && bash scripts/copilot-mcp-bridge.sh install "$@")
    ;;
  uninstall-copilot-mcp)
    (cd "$REPO_DIR" && bash scripts/copilot-mcp-bridge.sh uninstall "$@")
    ;;
  doctor-copilot-mcp)
    (cd "$REPO_DIR" && bash scripts/copilot-mcp-bridge.sh doctor "$@")
    ;;
  smoke-copilot-mcp-state)
    (cd "$REPO_DIR" && bash scripts/smoke-copilot-mcp-state.sh)
    ;;
  smoke-omp-bridge-state)
    (cd "$REPO_DIR" && bash scripts/smoke-omp-bridge-state.sh)
    ;;
  install-omp-mcp)
    (cd "$REPO_DIR" && bash scripts/omp-mcp-bridge.sh install "$@")
    ;;
  uninstall-omp-mcp)
    (cd "$REPO_DIR" && bash scripts/omp-mcp-bridge.sh uninstall "$@")
    ;;
  doctor-omp-mcp)
    (cd "$REPO_DIR" && bash scripts/omp-mcp-bridge.sh doctor "$@")
    ;;
  smoke-omp-mcp-state)
    (cd "$REPO_DIR" && bash scripts/smoke-omp-mcp-state.sh)
    ;;
  install-omp-config)
    # #87 follow-on: the ONE operator setting omp's tool hand requires (`tools.xdev: false`).
    # A separate unit from install-omp-mcp because it answers a different question — the MCP
    # hand registers the server, this decides whether the registered tools are REACHABLE. It
    # owns exactly the line it adds and refuses an explicit operator `xdev: true` by name.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-config-xdev.sh install "$@")
    ;;
  uninstall-omp-config)
    # honest inverse from install-state: takes back exactly the recorded line(s), removes the
    # file only when entwurf created it, and REFUSES when the config changed since install.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-config-xdev.sh uninstall "$@")
    ;;
  install-omp-bridge)
    # #87: the OMP BIRTH install. Not a mode of the Claude or Copilot installer, and for a
    # structural reason rather than a stylistic one: an omp "hook" IS an in-process
    # extension, so there is no launcher to bake a node path into and no hook manifest to
    # declare events in — the vendor imports the module itself. What this owns is one
    # directory under the omp agent dir; the MCP hand is install-omp-mcp.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-bridge-install.sh "$@")
    ;;
  uninstall-omp-bridge)
    # The package-owned inverse: the ownership state is the sole removal authority (exact
    # unit dir, recorded entry name, recorded assembly), a no-state host REFUSES instead of
    # cleaning up what it cannot prove is ours, and the state is deleted LAST.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-bridge-uninstall.sh "$@")
    ;;
  doctor-omp-bridge)
    # #87: the fail-loud surface for the OMP unit. Red is a unit omp cannot import, a STALE
    # deployed writer, an unrecovered mint ERROR, a failed sender-marker write, or a live omp
    # process carrying inherited PI_SESSION_ID/PI_AGENT_ID. "Installed with zero records" is
    # NOT-YET, not red.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-bridge-doctor.sh "$@")
    ;;
  install-omp-receive)
    # #87 bundle B: install the OMP RECEIVER extension into
    # <omp agent dir>/extensions/entwurf-receive-omp. Its own unit, install-state, doctor and
    # inverse — birth says who sends, this says a reply can land, and neither grants the other.
    # Same ownership discipline as the birth installer: no adoption of an artifact entwurf holds
    # no state for, no writing through a symlink, refusal when the agent dir is ambiguous.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-receive-install.sh "$@")
    ;;
  uninstall-omp-receive)
    # honest inverse from install-state (exact unit dir + recorded entry; no-state host REFUSES;
    # state deleted LAST). Records, sender identity and any ALREADY-armed live session are
    # untouched — an omp TUI that armed before this ran stays addressable until it exits.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-receive-uninstall.sh "$@")
    ;;
  doctor-omp-receive)
    # #87 bundle B: runtime axis (importable unit, writer parity, arm vs doorbell failures on
    # SEPARATE axes, and WHO IS ARMED right now read through the PRODUCTION marker reader via
    # omp-receive-facts — never a filename) + ownership axis. Zero armed receivers is NOT-YET.
    # It reports a marker for exactly what a marker proves: a live owner reached the arm emit.
    # It never claims the vendor's watch is still registered — see the header.
    shift || true
    (cd "$REPO_DIR" && bash scripts/omp-receive-doctor.sh "$@")
    ;;
  smoke-omp-receive-state)
    # #87 bundle B: OMP RECEIVER install/doctor/inverse regression — placement, stale-writer
    # detection, honest inverse, no-state refusal (structurally VALID as well as foreign),
    # symlink refusal, ambiguous-agent-dir refusal, a poisoned PI_CODING_AGENT_DIR that
    # attracts no artifact, plus the two this surface owns: installing a doorbell ARMS
    # NOTHING, and a host with no birth unit is a green doctor with a NAMED dependency note
    # rather than a red one. Fully sandboxed HOME/PI/XDG. Offline/deterministic
    shift || true
    (cd "$REPO_DIR" && bash scripts/smoke-omp-receive-state.sh "$@")
    ;;
  check-omp-receive-arm)
    # #87 bundle B gate: drives the REAL receive assembler into a temp dir, imports the
    # ASSEMBLED index.ts into a MOCK omp host and proves everything on entwurf's side of the
    # vendor boundary — the tui-only scope fence, deferral before birth and the BOUNDED retry
    # that arms once the sender marker appears, the refusal to start a timer this build cannot
    # cancel, the refusal to arm when the wake surface is missing, id-drift refusal, the /new
    # unarm that the start-key guard structurally cannot catch, no-watch-no-marker ordering,
    # an announce-only doorbell that never carries the body, a vanished signal giving the
    # marker back, and an identity-guarded teardown. Hermetic; no omp, no model turn. What it
    # deliberately cannot prove — that the vendor really wakes an idle host — is
    # smoke-omp-receive-live's job, and neither receipt substitutes for the other
    shift || true
    run_ts scripts/check-omp-receive-arm.ts "$@"
    ;;
  omp-receive-facts)
    # #87 bundle B: read-only JSON projection of the omp receive rail — every receiver marker
    # read through readMetaReceiverMarker in BOTH readings (live / as-written), plus the mailbox
    # counts behind each. The shared oracle for doctor-omp-receive, the state smoke and the LIVE
    # acceptance, so none of them answers "is a doorbell held?" from a filename.
    shift || true
    run_ts scripts/omp-receive-facts.ts "$@"
    ;;
  copilot)
    # #82 RAIL 7: the managed launch. `exec` and NO subshell/cd on purpose — the vendor
    # must inherit this terminal exactly: the caller's cwd, this pid, this tty, and its own
    # exit status. The sibling install/doctor verbs wrap themselves in `(cd "$REPO_DIR" && …)`
    # because they operate on the repo; this one operates on the operator's session, and a
    # subshell would make run.sh a parent that outlives nothing and owns nothing.
    #
    # `shift` is load-bearing here, not cosmetic: this dispatcher keeps the verb in "$@"
    # and each branch drops it for itself. The neighbouring install/doctor verbs get away
    # without one because their bridge scripts take a leading subcommand and ignore the
    # trailing noise; this branch forwards straight into the VENDOR's argv, where a stray
    # "copilot" would arrive as a prompt argument.
    shift || true
    exec bash "$REPO_DIR/scripts/copilot-launch.sh" "$@"
    ;;
  install-copilot-receive)
    # #82 RAIL 5: install the RECEIVER extension into the Copilot USER extensions dir.
    # Artifact ownership only — it sets no launch flag (`run.sh copilot` owns one
    # invocation's environment; this owns the unit on disk), and it arms
    # nothing by itself: a session arms after birth, on a CLI launched with
    # COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS.
    (cd "$REPO_DIR" && bash scripts/copilot-receive-bridge.sh install "$@")
    ;;
  uninstall-copilot-receive)
    (cd "$REPO_DIR" && bash scripts/copilot-receive-bridge.sh uninstall "$@")
    ;;
  doctor-copilot-receive)
    (cd "$REPO_DIR" && bash scripts/copilot-receive-bridge.sh doctor "$@")
    ;;
  install-agy-bridge)
    # 봉인 7: the agy (Antigravity) MCP install ADAPTER (SEPARATE from the Claude
    # marketplace install — only runner/reporting is shared). Registers ONE entwurf-bridge
    # server entry in the agy mcp_config: adopt a regular file / create a new one / REFUSE a
    # symlink (someone else's SSOT). Records an install-state under $XDG_DATA_HOME/entwurf/
    # agy-bridge/ for an honest inverse. The command written is a STABLE bin (entwurf-bridge),
    # never a repo/git-hash path (the oracle dangling lesson).
    (cd "$REPO_DIR" && bash scripts/agy-bridge.sh install "$@")
    ;;
  uninstall-agy-bridge)
    # 봉인 7: honest inverse of install-agy-bridge from the install-state (restore the
    # captured preimage / remove our key; remove the file if we created it empty). Refuses if
    # the managed config became a symlink since install; no state → nothing to undo.
    (cd "$REPO_DIR" && bash scripts/agy-bridge.sh uninstall "$@")
    ;;
  doctor-agy-bridge)
    # 봉인 7: 2-tier fail-loud doctor. STATIC proves both candidate configs (global
    # ~/.gemini/config/mcp_config.json — the file live agy actually reads — + legacy
    # ~/.gemini/antigravity-cli which install now cleans) resolve, parse, and carry a
    # RESOLVABLE command (a dangling command FAILS). LIVE proves runtime-effectiveness only
    # when an agy process exists; with no agy it is an honest SKIP (never a PASS in disguise).
    (cd "$REPO_DIR" && bash scripts/agy-bridge.sh doctor "$@")
    ;;
  wire-agy-bridge)
    # 막힘 ①: the detection-gated, truthful setup wrapper around install-agy-bridge (agy on
    # PATH → idempotent install; no agy → honest skip, no state; detected refusal/corrupt →
    # reason-specific WARN + nonzero so the aggregate records a named component FAIL while later
    # components stay attempted, #86 C6/C7). HIDDEN/internal — setup calls this; it is exposed
    # as a subcommand only so smoke-agy-install-state can drive it deterministically. The hard
    # per-leaf gate stays doctor-agy-bridge (issue #45).
    wire_agy_bridge
    ;;
  install-agy-statusline)
    # #46 Task 1: own the WHOLE statusLine subtree of agy settings.json → the stable-bin renderer
    # entwurf-agy-statusline (driver + garden id), the claude meta-bridge statusLine symmetry.
    # Adopt a regular file / create / REFUSE a symlink. install-state under $XDG_DATA_HOME/
    # entwurf/agy-statusline/ for an honest inverse. The command is a BARE stable bin — dev AND
    # installed (the checkout path lives only in the dev-bin symlink state, never in settings).
    (cd "$REPO_DIR" && bash scripts/agy-statusline-bridge.sh install "$@")
    ;;
  uninstall-agy-statusline)
    # #46 Task 1: honest inverse of install-agy-statusline — restore the captured statusLine
    # subtree preimage (remove the key if absent, else set it back; remove the file if we created
    # it empty). Refuses if settings.json became a symlink since install; no state → nothing.
    (cd "$REPO_DIR" && bash scripts/agy-statusline-bridge.sh uninstall "$@")
    ;;
  doctor-agy-statusline)
    # #46 Task 1: fail-loud doctor. STATIC proves the SINGLE settings root agy reads statusLine
    # from (~/.gemini/antigravity-cli/settings.json — Task-1 capture, not the 2-candidate mcp
    # root) parses and carries OUR RESOLVABLE command (dangling FAILs, state drift FAILs). LIVE
    # proves runtime-effectiveness only with an agy process; else an honest SKIP.
    (cd "$REPO_DIR" && bash scripts/agy-statusline-bridge.sh doctor "$@")
    ;;
  install-agy-hooks)
    # #46 birth writer: install the Antigravity PreInvocation named hook that runs
    # entwurf-agy-imprint and returns {"injectSteps":[]}.
    (cd "$REPO_DIR" && bash scripts/agy-hooks-bridge.sh install "$@")
    ;;
  uninstall-agy-hooks)
    # Honest inverse of install-agy-hooks: restore/remove only our named hook.
    (cd "$REPO_DIR" && bash scripts/agy-hooks-bridge.sh uninstall "$@")
    ;;
  doctor-agy-hooks)
    # Fail-loud doctor for agy hooks.json imprint wiring.
    (cd "$REPO_DIR" && bash scripts/agy-hooks-bridge.sh doctor "$@")
    ;;
  check-probe-bridge-command)
    # #81: contract gate for the boot probe both doctors stake their verdict on — the reason
    # taxonomy (each value = a different operator repair) plus the one side effect the probe owns,
    # reaping the child it spawned. Hermetic stubs only; boots no bridge of ours.
    run_ts scripts/check-probe-bridge-command.ts
    ;;
  probe-bridge-command)
    # #81: does a configured bridge command actually BOOT and serve MCP? `command -v` answering
    # yes is not that claim — a relocated launcher can resolve and still exit 127, which is how a
    # host ran with NO bridge in its ACP turns while every doctor printed ok. It waits for the
    # initialize RESPONSE before it sends notifications/initialized + `tools/list` (no tools/call),
    # so it takes no lock, writes no record, and delivers nothing. Both doctors route their boot
    # cell here so one leaf owns the verdict — agy for every configured {command,args,env}, pi for
    # every effective stdio invocation.
    shift || true
    run_ts scripts/probe-bridge-command.ts "$@"
    ;;
  doctor-pi-provider)
    # #46 Task 2 + #81: fail-loud doctor for the pi provider ownership (entwurfProvider.
    # mcpServers.entwurf-bridge). Uses the config.ts SSOT for the EFFECTIVE (project-shadows-user)
    # entry — per-name merge then ONE normalize, exactly as resolveProviderConfig does; never a
    # re-implemented merge. Reports user/project/effective and distinguishes state-owned drift
    # (FAIL) from an unowned user override (honest note).
    # This doctor no longer merely reads files: it BOOTS every effective stdio invocation and
    # requires the entwurf verb set back, because `command -v` succeeding was never evidence that
    # pi gets a bridge. Runtime evidence and ownership are separate: an unowned override is not
    # repaired, but a dead one is still red. It writes no operator state, but it does exec the
    # configured command on this host. No agy/pi process is needed.
    run_ts scripts/doctor-pi-provider.ts "$@"
    ;;
  wire-agy-statusline)
    # #46 Task 1: the detection-gated, truthful setup wrapper around install-agy-statusline
    # (detected refusal/corrupt → WARN + nonzero, named component FAIL in the aggregate, #86
    # C6/C7). HIDDEN/internal — setup calls this; exposed so smoke-agy-statusline-state can
    # drive it deterministically. The hard per-leaf gate stays doctor-agy-statusline.
    wire_agy_statusline
    ;;
  wire-agy-hooks)
    # #46 birth writer setup wrapper around install-agy-hooks.
    wire_agy_hooks
    ;;
  expose-dev-bin)
    # 막힘 ②: expose the stable package commands on PATH for a DEV checkout, including the
    # `entwurf` operator command Copilot fresh resolves. HIDDEN/internal — setup requires the
    # core operator certification and attempts every helper unit independently; a foreign helper
    # propagates rc=3 as a named bins FAIL (#86 C10). Exposed here so the install smoke can
    # drive ownership/refusal.
    # The exposure logic lives in scripts/dev-bin.sh.
    expose_dev_bin
    ;;
  remove-dev-bin)
    # 막힘 ②: honest inverse of expose-dev-bin — remove ONLY our managed links + states (REFUSE if
    # it became foreign). The raw script (no wrapper) so an operator sees a loud failure.
    shift || true
    (cd "$REPO_DIR" && bash scripts/dev-bin.sh remove "$@")
    ;;
  meta-bridge-fresh-cut)
    # The generation verb (operator command only, never hook-automated). Every
    # v3-only rejection surface (parse/birth/peers/self/v2/inbox/store-doctor)
    # names this verb as the fix. Quiesce gate first (a live/uncertain socket or
    # a live-owner marker refuses the cut), then meta-sessions/ + meta-mailbox/
    # move atomically to `<dir>.archive-<ts>` siblings, dead transport residue is
    # cleared, and an empty v3 generation opens. No migration and no restore —
    # the archive is forensic bytes only; transcripts and the andenken memory
    # axes are untouched. Store resolution is env+default only — it targets THE
    # live store.
    shift || true
    run_ts scripts/meta-bridge-fresh-cut.ts "$@"
    ;;
  meta-bridge-prune)
    # 1.0.0 meta-bridge Phase 4: LISTING-ONLY janitor for the meta-session store.
    # doctor reds on corrupt/duplicate/drift but intentionally does NOT fail on
    # transcript-gone records, so a green store can silently bloat with abandoned
    # records. This surface CLASSIFIES (orphan/stale/ambiguous/keep) and prints
    # the exact manual rm commands. It deletes NOTHING — no --apply in 1.0.0;
    # ambiguous (corrupt/duplicate/drift) stays manual-only (operator picks the
    # surviving authority). Default store = defaultMetaSessionsDir(); pass [dir]
    # + [--ttl-days N] to override.
    shift || true
    run_ts scripts/meta-bridge-prune.ts "$@"
    ;;
  meta-facts)
    # #65 owner-normalized READ-ONLY projection of the meta-record store: the
    # (gardenId, nativeSessionId, transcriptPath) join as deterministic JSON,
    # emitted by THE listing contract (listAllMetaIdentities) so consumers stop
    # carrying a decaying copy of the certification. Defects ride in-band with
    # exit 0; an unreadable store is exit 3 and never looks empty. No liveness,
    # no socket paths, no transcript contents, no state.
    shift || true
    run_ts scripts/meta-facts.ts "$@"
    ;;
  meta-bridge-managed-keys)
    # 0.10.0 meta-bridge: emit the SSOT of settings.json/~/.claude.json keys that
    # entwurf's install OWNS. Consumers (agent-config fragment, future
    # harnesses) read this to set only their OWN keys — the keyset-owner invariant.
    (cd "$REPO_DIR" && python3 scripts/meta-bridge-state.py managed-keys)
    ;;
  check-keyset-overlap)
    # 0.10.0 meta-bridge: PREVENTIVE half of the keyset guard. Fails loud if a
    # consumer fragment sets a key entwurf owns (exact or ancestor/descendant).
    # Cross-repo + non-hermetic (fragment path is an arg) → NOT in pnpm check;
    # its own logic is regression-tested hermetically by smoke-meta-keyset-guard.
    shift || true
    (cd "$REPO_DIR" && python3 scripts/check-keyset-overlap.py "$@")
    ;;
  check-package-source-routing)
    check_package_source_routing
    ;;
  check-dep-versions)
    check_dep_versions
    ;;
  check-node-floor-coherence)
    check_node_floor_coherence
    ;;
  check-claude-floor-coherence)
    check_claude_floor_coherence
    ;;
  check-install-preflight)
    check_install_preflight
    ;;
  check-pi-import-surface)
    check_pi_import_surface
    ;;
  check-env-namespace)
    check_env_namespace
    ;;
  check-pi-runtime-version)
    check_pi_runtime_version
    ;;
  check-pi-preflight)
    check_pi_preflight
    ;;
  check-auth-boundary)
    check_auth_boundary
    ;;
  check-acp-provider-surface)
    check_acp_provider_surface
    ;;
  check-acp-sdk-surface)
    check_acp_sdk_surface
    ;;
  check-acp-overlay)
    check_acp_overlay
    ;;
  check-acp-tool-surface)
    check_acp_tool_surface
    ;;
  check-acp-event-mapper)
    check_acp_event_mapper
    ;;
  check-acp-usage-accounting)
    check_acp_usage_accounting
    ;;
  check-acp-stop-reason)
    check_acp_stop_reason
    ;;
  check-acp-prompt-lifecycle)
    check_acp_prompt_lifecycle
    ;;
  check-acp-launch-namespace)
    check_acp_launch_namespace
    ;;
  check-acp-stream-hooks)
    check_acp_stream_hooks
    ;;
  check-acp-prompt-builder)
    check_acp_prompt_builder
    ;;
  check-acp-config)
    check_acp_config
    ;;
  check-acp-session-store)
    check_acp_session_store
    ;;
  check-acp-backend-preflight)
    check_acp_backend_preflight
    ;;
  check-acp-session-reuse)
    check_acp_session_reuse
    ;;
  check-release-gate-outcomes)
    run_ts scripts/check-release-gate-outcomes.ts
    ;;
  check-acp-carrier-augment)
    check_acp_carrier_augment
    ;;
  check-acp-cortex)
    check_acp_cortex
    ;;
  check-fresh-cut-gate)
    # SOURCE cell of the generation-boundary proof: a host whose store the live
    # schema cannot read must be refused BEFORE any write, told the fresh-cut
    # verb in both invocation forms, and then succeed on the retry after the cut.
    # Hermetic (mkdtemp worlds + the store env seam); no model, no network.
    (cd "$REPO_DIR" && bash scripts/check-fresh-cut-gate.sh "$@")
    ;;
  check-pack)
    check_pack
    ;;
  check-pack-pin-matcher)
    check_pack_pin_matcher
    ;;
  check-pack-install)
    check_pack_install
    ;;
  check-install-container)
    # 0.12.8 (#51 gate C): the Linux artifact-CONSUMER lane. check-pack-install is
    # the strongest HOST gate and still only ever proves this machine's shape —
    # checkout present, every tree operator-owned, project-local install. This
    # hands ONE candidate tarball, read-only, to a container that has never seen
    # the repo, installs it globally as a non-root user, freezes the package, and
    # then consumes it. Dev-clone-only (hard rule 10): the script itself REFUSES
    # from under node_modules rather than re-packing the installed copy.
    (cd "$REPO_DIR" && bash scripts/check-install-container.sh "$@")
    ;;
  install)
    install_local_package "$TARGET_PROJECT_DIR"
    ;;
  remove)
    remove_local_package "$TARGET_PROJECT_DIR"
    ;;
  remove-user-scope)
    remove_user_scope_citizen
    ;;
  takeover-user-scope)
    # #86 C2: operator-explicit ownership move — the ONLY writer allowed to replace
    # another root's user-scope registration (normal install/setup/remove refuse).
    takeover_user_scope
    ;;
  doctor-pi-package)
    # #86 C2: package-side ownership verdict (unregistered/owned/owned-by-other/
    # legacy-no-state/mismatch/missing-owner). Provider runtime stays with
    # doctor-pi-provider — the two doctors are deliberately not mixed.
    doctor_pi_package
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
