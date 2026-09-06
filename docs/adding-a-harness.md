# Adding a harness to the garden

The order a new harness is actually walked in, and what each step owes before the next
one may start. This is the **first entry point** for "we want harness X in the garden";
every other document here owns one slice of it and is linked from the step that needs it.

This is a route, not a promise. Every step below was walked for at least one shipped
backend, and the steps a given backend has NOT walked are named as such — an unwalked
step is a boundary, never a gap to paper over. Nothing here grants a capability: the
gates and doctors named in each step are the truth, and prose that disagrees with them
is the thing to repair.

**Vocabulary.** *Harness* = the vendor product (Claude Code, Antigravity, Copilot CLI,
Codex, pi). *Backend* = the identifier that harness carries inside entwurf. *Citizen* =
a session of that harness that owns a V3 meta-record and therefore a garden id. *Managed*
describes entwurf ownership of a concrete invocation/install/config surface; it is not an
admission grade. *Supported* means the end-to-end native-harness contract in this document has
been accepted.

## The shipped map — five backends, one gauge

Steps 1–9 below are one fixed gauge, and five backends now ride it. Every new harness feels like
a special case while you are inside it; read this table first so the VARIETY is expected rather
than alarming. Cells summarize facts whose receipts live in `DELIVERY.md`'s matrix and in this
document's worked examples — do not re-derive them, reopen them there.

| backend | lineage | receive rail — how a message lands | callback spelling (one tool, per-harness dialect) | fresh launch (step 9) |
|---|---|---|---|---|
| `pi` | the host adapter itself | control socket: record-keyed UDS; a send steers or follows up the live turn | `entwurf_v2` (native tool) | positional prompt + `--entwurf-control --model` |
| `claude-code` | independent vendor | self-fetch mailbox: exec-form `FileChanged` doorbell + `asyncRewake`; the model drains with `entwurf_inbox_read`. The watch owner is the CLI process itself, which can switch sessions in place, so the receiver marker is only live while that pid's sender marker still names the same garden (#101) | `mcp__entwurf-bridge__entwurf_v2` | positional prompt + `--allowedTools=…` + `--model=` |
| `copilot` | independent vendor | self-fetch mailbox: the watch lives in a FORKED first-party extension child; the receiver marker names the extension pid | `entwurf-bridge-entwurf_v2` — plus a SECOND permission dialect, `entwurf-bridge(entwurf_v2)` | managed verb `entwurf copilot`, `--interactive … --model … --yolo` |
| `agy` | independent vendor | native-push: record + probe-alive gRPC `send-message`; no mailbox, no receiver marker | n/a — push rail | not openable; the declared pre-#82 legacy exception |
| `omp` | **a pi fork** — inherits pi's env vocabulary (step 1(6)) | self-fetch mailbox: Claude's SHAPE, but the watch runs IN-PROCESS in the operator's TUI; announce-only doorbell via the vendor's own `sendUserMessage` | `mcp__entwurf_bridge_entwurf_v` — the sanitizer eats the digit | bare `omp`, NO positional prompt: the two-stage `--entwurf-bootstrap` payload |

(Codex has a verified delivery probe and a deliberate decision against a native lane — pi already
supplies the official GPT route. It is a row in `DELIVERY.md`, not a sixth gauge.)

Two facts this table exists to make obvious:

- **Lineage does not choose the rail.** omp is pi underneath and rides Claude's mailbox shape,
  because the rail is chosen by the harness's MEASURED wake surface (step 1), never by its
  ancestry. What ancestry does instead is concentrate the danger: the shared env vocabulary is
  exactly where a fork silently splits a store (step 1(6), step 3; `[측정]` #87 B1).
- **One tool, three spellings — and that is the smallest of the differences.** Every column
  varies per harness, every cell was measured, and the next harness will disagree with all five
  rows somewhere. The gauge holds because the STEPS are fixed while their ANSWERS are not.
- **A version floor is earned, not standard issue.** Node, pi and Claude Code each have an
  enforcement point; OMP deliberately has none, and carries a documented **weak floor** — the
  last version with a LIVE receipt — instead. The rule and its reasoning live in
  [docs/setup-clean-host.md](./setup-clean-host.md) §4b (#91). Read it before giving a new
  harness a floor: the question is whether that vendor can fail SILENTLY, not how fast it ships.

**Why the doorbell is worth this much work** (GLG doctrine, 2026-08-31). Every row keeps its own
runtime, auth and transcript; entwurf refuses prompt reconstruction, transcript hydration and
harness emulation (Hard Rule 9), so the only way to reach a sibling is the doorbell its own
vendor actually ships — and the table above is the price of that refusal, paid five times over.
The price is the point. A creation surface that made every harness cheap to open and drive would
produce disposable workers wearing five logos. The bridge being hard — measured dialects,
explicit doorbells, honest rejects — is what makes the thing on the other side a peer whose
cooperation means something: you do not command it, you ring, and it answers as itself. The
gauge is narrow so that what rides it is a citizen.

---

## 0. Which lane — onboarding is two different jobs

Before anything else, decide which of the two you are doing. They share almost nothing.

|  | **Native citizen onboarding** | **ACP backend adapter** |
|---|---|---|
| The session | already running, opened by the operator | a child entwurf's pi adapter launches |
| Owns its auth/transcript | yes — entwurf never touches them | yes — inside an isolated overlay |
| What entwurf adds | a meta-record, a garden id, and whatever rails the vendor actually supports | a provider/model route and a turn loop |
| Where the contract lives | **this document**, steps 1–9 | [`acp-backend-rail.md`](./acp-backend-rail.md) |

- (a) Source: native lane → `pi-extensions/lib/meta-session.ts` + a per-backend hook unit
  under `pi/`. ACP lane → `pi-extensions/lib/acp/` and `pi-extensions/acp-provider.ts`.
- (b) Acceptance: the two lanes have separate gates and neither substitutes for the other.
- (c) Skip this choice and you build an ACP adapter for a harness the operator already has
  open (duplicating a session it owns), or a citizen lane for a process nobody launched.

**Opening a NEW sibling or reopening a dormant one is neither implementation lane.** That is
lifecycle and it has its own contract in [`mux-launch-rail.md`](./mux-launch-rail.md); do not put
tmux placement or launch code inside a birth/receive adapter. But separation is not deferral:
a native harness is not DONE until step 9 proves the required visible lifecycle parity. If the
vendor cannot support the required top-level birth, identity, receive and visible-fresh contract
without invented authority, do not admit it and leave a permanently partial harness behind.
Same-id resume remains capability-specific because it requires record-authoritative transcript
reopening; visible fresh is the required common creation surface.

---

## 1. Measure the vendor

Everything downstream is a bet on what the vendor actually does. Take these five
measurements first, from the vendor's own artifacts and processes.

1. **Hook vocabulary and firing time.** Which events exist, and *when* they fire.
2. **Launch form and envelope.** How a hook command is declared, and what arrives on stdin.
3. **Config writer.** Which file the vendor's own CLI writes, and in what shape.
4. **Statusline / receive surfaces.** What the vendor offers for display and for waking,
   including bundled SDKs, extension APIs, and the feature gates that make them load.
5. **Parent process topology.** Whether the hook process and the MCP child share one
   ancestor — the join key step 6 depends on.
6. **The environment vocabulary it inherits.** Which variable names the vendor reads, and
   whether any of them is a name *entwurf already owns*. A harness that is a FORK of another
   one keeps its parent's spelling, so a single variable ends up with two owners and two
   meanings, and the collision is invisible until a record lands in the wrong store.

- (a) Source: the vendor's shipped bundle, its `--help`, its own CLI writer, and a live
  process tree. Not our assembler, and not a schema file that turns out to describe a
  different layer.
- (b) Acceptance: each measurement is written down with the artifact path or the receipt it
  came from, so a later reader can reopen it instead of re-deriving it.
- (c) Skip it and you encode a guess. Two shapes account for most of them:
  - **A vendor ships several layers that describe the same thing differently** — the file its
    own CLI writes, the wire schema its API validates, the types its SDK exports. They
    disagree on key names and required fields. Follow the layer you are actually writing to;
    the other two produce a config the vendor silently ignores.
  - **A lifecycle event's NAME does not tell you when it fires.** Measure the firing, not the
    documentation, or a design assuming birth-at-open renders a citizen that does not exist.
  - **One familiar doorbell's absence does not prove the harness cannot wake.** Search the
    vendor's bundled SDK, extension bootstrap, and examples before declaring D4 impossible.
    `[측정]` Copilot CLI 1.0.80 has none of Claude's `FileChanged` / `asyncRewake` /
    `watchPaths`, yet its bundled first-party extension SDK documents `fs.watch` followed by
    `session.send()`. With `COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS`, that route woke an
    idle native session and returned an exact marker on 2026-08-23. The decisive receipt and
    reproduction live in `scripts/raw-async-delivery/README.md`.

**The oracle is the vendor artifact or the vendor process — never our own assembler.**
A gate that drives our installer proves our installer; only the vendor proves the vendor.

**And never the resolver under test.** When two halves of a backend are supposed to agree by
sharing one function, `halfA === halfB === sharedResolver()` proves nothing: a wrong answer in
the shared function balances that equation perfectly. The expected value has to be an
independent literal the test derives itself. `[측정]` #87's four-root binding was first
proposed with the production resolver as its own oracle; the mutant that reinstates the defect
survives that shape semantically green, so both halves are compared against test-built paths.

---

## 2. Register the backend

The backend id must exist before any record carrying it can be written or read.

- (a) Source, all in one change:
  - `META_BACKENDS` (`pi-extensions/lib/meta-session.ts:84`) — backends that mint records
    through a native bridge.
  - `META_CITIZEN_BACKENDS` (`pi-extensions/lib/meta-session.ts:237`) — every backend a
    record may name, `pi` included.
  - `META_BACKEND_DESCRIPTORS` (`pi-extensions/lib/meta-session.ts:113`).
  - the capability registry `pi/entwurf-capabilities.json`, whose keys must be exactly
    `META_CITIZEN_BACKENDS`.
- (b) Gates: `check-meta-session`, `check-entwurf-capabilities`. The capability gate derives
  its drift scope from the constant, not from a literal list — a hand-typed scope is how a
  new backend's descriptor once shipped without ever being compared.
- (c) **Skip the deployment half and you stop a sibling rail from writing.** A new backend id
  changes what every *deployed* reader must accept, and identity writers certify the **whole
  active store** before writing — so a sibling still carrying the old list cannot authenticate
  the new backend's records, and therefore refuses to write **its own**. The order is not
  optional:

  > source + gates → build → **redeploy every shared-reader sibling, then run its doctor** →
  > only then let the new backend mint its first record.

  **A running MCP bridge child is a shared reader that no redeploy can reach.** It holds the
  old backend list in memory and re-reads the capability registry from disk on each call, so
  the strict coverage guard fires and every `entwurf_v2` send from that process is refused
  until its owning session restarts. `[측정]` 2026-08-27, adding `omp`: four live bridge
  children on one host all refused with `capability registry must cover exactly … (got …,
  omp, pi)` while a freshly spawned bridge was green. That is the designed stale-reader
  refusal doing its job, not a defect — but plan the restart, and do not read the refusal as
  a rotten generation.

  **An unknown-backend refusal is a stale deployed reader — redeploy it.** It is *not* a
  rotten generation, and the fresh-cut verb is the wrong tool there: it would archive healthy
  records. Only a genuinely unreadable generation goes to
  [`fresh-cut-policy.md`](./fresh-cut-policy.md). `doctor-meta-bridge` names the difference;
  run it after any `META_BACKENDS` change.

---

## 3. Birth

A trusted lifecycle event of the harness turns a session into a record.

- (a) Source: a per-backend hook unit under `pi/` (manifest + launcher) plus its payload
  under `pi-extensions/`. The payload's whole job is `upsertMetaSession` — idempotent, so
  whichever wired event fires first mints and the rest attach. The launcher `exec`s the
  payload, so the payload keeps the launcher's pid and its parent is the harness itself.
  Reference pair: `pi/meta-bridge-copilot/entwurf-meta-receive-copilot/` +
  `pi-extensions/meta-bridge-hook-copilot.ts`.
- (b) Two acceptances that must stay separate:
  - **mechanism** — a hermetic gate fires the shipped launcher with a synthetic envelope and
    asserts a record (`check-copilot-birth-hook`; no vendor binary, no model turn);
  - **real native admission** — an actual session of the harness mints a record. Only the
    second proves the vendor fires our unit at all.
- (c) Skip the split and a green gate reads as a live harness. Four things belong in the
  payload and its doctor, not in prose:
  - **Refuse a degraded envelope; never guess a field.** A record minted from a guessed id
    is a citizen no live session can be joined back to.
  - **Say when birth happens.** `[측정]` A Copilot citizen is born when it is first spoken
    to, not when its window opens.
  - **When step 1(6) found a shared variable, give the backend an explicit root policy —
    all of it, as one bundle.** Do not change the shared defaults every other backend uses;
    add a per-backend resolver, and let BOTH halves (the in-process/hook payload and its MCP
    child) read that one leaf so their agreement is by construction. The bundle is
    indivisible: sessions, mailbox, senders and receivers move together, because splitting
    mailbox from receivers is FALSE DELIVERABILITY — dispatch trusts an armed receiver marker
    in one root and enqueues into the mailbox of the other while the real watcher drains the
    first. An in-process extension cannot be repaired at exec, so its half must pass explicit
    directories in code; a child process may scrub the foreign variable in ITSELF, never in
    the host, where it is the vendor's own meaning. `[측정]` OMP is a pi fork that reads
    `PI_CODING_AGENT_DIR`, and `setProfile` exports it for every named profile — so a plain
    `omp --profile work` was enough to split the store (#87 B1).
  - **Every input to that policy must be unambiguous ACROSS PROCESSES, so fail closed on the
    ones that are not.** The halves do not share a working directory — one runs wherever the
    operator launched the harness, the doctor runs wherever its own dispatcher `cd`s to — so
    resolving a relative override quietly makes cwd a garden-root authority and the two halves
    address different stores while both look correct. Accept absolute and `~`-rooted values,
    refuse the rest BY NAME, and let both halves take the refusal from the same leaf. Then
    check that the refusal is still legible: a policy that also silences its own diagnostic
    log is worse than the split it prevents. `[측정]` one `ENTWURF_META_SESSIONS_DIR=relative-records`
    resolved to two different stores, and the doctor would have reported NOT-YET off the empty
    one (#87 A2).
  - **Select a per-backend policy on the EXACT label its writer emits.** A courtesy `trim()`
    (or a case-fold) makes a drifted value foreign to the doctor and ours to the runtime, so
    an entry the doctor calls red still mutates that process. Writer, doctor and consumer must
    compare the same literal. `[측정]` #87 A3.
  - **A doctor may not claim admission from a text match.** "This host has a citizen" is a
    claim on the record-authority axis, and the writer earns it by certifying the whole active
    store. Ask through the same certified surface. `[측정]` A `grep '"backend": "omp"'` printed
    PASS for a file containing nothing but `{ "backend": "omp" }` (#87 B3).

---

## 3.5 Citizen scope — one visible host, not every session it creates

A harness process may create several internal sessions or agents. That does not make each one a
garden citizen. Before writing the birth hook, identify a **vendor-authoritative top-level
predicate** and allowlist only the operator-visible host. Every other mode must refuse and log;
absence or ambiguity is an admission blocker, not a reason to infer from cwd, process age, or the
latest session id.

- (a) Source: the vendor's actual lifecycle context plus its parent/internal-agent creation path.
  Read both. An event named `session_start` proves nothing about scope.
- (b) Acceptance: a real top-level session births exactly one record while one real internal agent
  births no record, sender marker, or receiver marker. Internal agents may borrow the host's tools
  and act under the host garden id; they must never acquire a second garden address.
- (c) Worked warning: OMP v18.0.0 creates subagents in-process, but each subagent rebinds inherited
  extension paths to its own session API and emits its own `session_start`. “Same OS pid” therefore
  does **not** prevent record minting. Its measured discriminator is extension `mode === "tui"`
  for the visible host — and `mode` **alone**: `hasUI` is not a fence, because rpc/rpc-ui/ACP
  contexts also report `hasUI:true` while task agents run `"print"` (source-audited 2026-08-27,
  `scripts/raw-omp-measure/source-audit.md` A1–A4). The runtime distinction still needs a LIVE
  receipt and must be remeasured at vendor upgrades. If it flips, stop and reassess rather than
  growing a pile of heuristic predicates.

**The principal doctrine, stated once and general.** The visible host citizen is the garden
**principal**. Delegation inside it — subagents, internal teams, task children — and the
responsibility for what they do belong to that citizen and to the vendor that built the delegation
mechanism. Entwurf does not build an internal ACL, does not track subagent provenance, and does not
introduce an authority axis below the citizen: an internal agent that borrows the host's tools is
acting AS the host, which is the honest description and also the only one the record can carry.

This is not an OMP note. It is why (b) above asks for exactly one record rather than a permission
model, and it is what closes the open question a borrowed-identity measurement always raises. `[측정]`
#87 L8: an OMP task child's `entwurf_self` returns the PARENT's garden id — no second address, the
requirement met — and it can call `entwurf_v2` and `entwurf_fresh_call` with that borrowed identity.
Under this doctrine that is the contract working, not a hole: the principal dispatched, through a
delegate it chose. A harness whose internal delegation is unacceptable to an operator is a decision
for that operator and that vendor's own controls, not a reason for entwurf to grow a second
authority surface it would then have to keep true across every backend.

---

## 4. Statusline / visible identity

For native-harness support declarations made under this contract, a dedicated statusline adapter
is optional; **visible identity is not**. If the harness has a status/footer surface, the citizen
shows its own garden id there. If it does not, prove an equivalent persistent operator-visible
identity surface owned by that runtime. If neither exists, do not declare that harness supported —
an address visible only by scraping records is not lifecycle parity. Historical/probe registry rows
that predate this rule are preserved evidence coordinates, not proof that those backends already
satisfy this support contract.

- (a) Source: a renderer plus a config writer that owns exactly its own keys. Reference:
  `scripts/copilot-statusline.sh`, `scripts/copilot-statusline-config.py`,
  `scripts/copilot-statusline-bridge.sh`.
- (b) Acceptance: install / uninstall / doctor and a state smoke
  (`smoke-copilot-statusline-state`). Four properties carry it — the id renders, a
  **preimage** of the pre-install value is captured once, uninstall is an honest **inverse**,
  and a **symlinked config is refused** rather than written through.
- (c) Two rules the inverse depends on:
  - **A status contract is usually tiny and unforgiving**, and a renderer that exits nonzero
    can blank the slot with no error anywhere. Make the renderer fail quiet, and never let
    the doctor claim a render receipt it cannot actually see.
  - **The preimage is the current value on disk**, even when that value is byte-identical to
    what we would write. Every rail does it this way; inventing a "there was nothing here
    before" case for one backend is the special-casing this document exists to prevent.
  - **A shape is never a proof of ownership.** Ownership STATE is the only licence for a
    destructive step. A structural oracle answers "is this a complete unit", not "is this
    ours": it compares no bytes, rejects no extra files, and establishes no provenance. Adopt
    on that answer and the installer moves a stranger's artifact aside, publishes over it and
    deletes the preimage — and the inverse then removes the path on the same unproven claim.
    A no-state artifact at our path REFUSES. `[측정]` #87 B2, where the destroyed candidate
    was any hand-made extension carrying four expected filenames.

---

## 5. The MCP hand — the citizen can call out

Registration puts `entwurf_*` in the harness's hands. That is *all* it does.

- (a) Source: a config writer for the vendor's own MCP file, following the **file writer**
  layer measured in step 1. Reference: `scripts/copilot-mcp-config.py` +
  `scripts/copilot-mcp-bridge.sh`; the precedent it was ported from is
  `scripts/agy-bridge-config.py` + `scripts/agy-bridge.sh`.
- (b) Acceptance: `install|uninstall|doctor-copilot-mcp` plus `smoke-copilot-mcp-state`, and
  a real chain — the bridge command answers (`run.sh probe-bridge-command entwurf-bridge`),
  the vendor's own `mcp get` reports the server enabled, and the harness log shows the
  client initialize.
- (c) **Read [`external-mcp-host.md`](./external-mcp-host.md) before designing this step.**
  It owns the distinction this step is constantly mistaken for:

  > a *plain external MCP host* has no meta-record and no sender marker. It can call the
  > read surfaces (`entwurf_peers`, `entwurf_inbox_read`), but `entwurf_v2` **sends are
  > refused by default**. A *garden-native native session* is one whose trusted lifecycle
  > hook minted a garden id **and a sender marker**.

  A newly-registered harness lands in the first row even when step 3 already gave it a
  record: **registration is tools, not identity.** Sending is step 6. `[측정]` A Copilot
  session with the hand installed called `entwurf_peers` and read the roster, while
  `entwurf_v2` refused — designed behavior, not a defect.
  - **Imported config is borrowed, not owned.** If a harness already translates another tool's
    MCP config, do not create a second writer merely to copy it. But discovery is not readiness:
    prove the effective source, precedence/shadowing, live connection, expected tools and the
    harness's actual public tool-name dialect. A best-effort importer that silently skips a bad
    server is useful interoperability, not an entwurf doctor.
  - **Confine the writer to the target it owns, and let one state own one target.** The
    product target is computed from the vendor's own resolution — `<resolved agent dir>/<the
    vendor's file>` — never taken from a free-form path variable. An explicit env seam lowers
    the odds of an accident; it grants no ownership, and an "X-only" writer that accepts an
    arbitrary path can be aimed at another harness's config. Sandbox at the layer the vendor
    resolves from instead. And when the target moves (a profile switch), REFUSE: overwriting
    the single ownership state strands the previous target's managed entry with no inverse.
    `[측정]` #87 D1.
  - **Runtime truth and ownership truth are separate axes, in the doctor's code as well as in
    its prose** (Hard Rule 13). A malformed entry under our key is broken for the vendor
    whether or not we installed anything there — and it still claims the dedupe slot, so it
    suppresses the import too. Coupling redness to the presence of install-state turns exactly
    that state into a PASS. `[측정]` #87 B4: `mcpServers.entwurf-bridge = null` printed
    `native-wins` and exited 0.
  - **Callback tool names are harness dialect.** Derive and measure the name the harness exposes;
    never copy a sibling's spelling. OMP v18.0.0, for example, lowercases and replaces every
    `[^a-z_]+` run with `_`, collapses underscore runs, then trims edge underscores; source
    inspection therefore computes terminal `entwurf_v2` as `mcp__entwurf_bridge_entwurf_v`
    rather than Claude Code's `mcp__entwurf-bridge__entwurf_v2`. Digits in the middle become an
    underscore rather than simply disappearing. The live OMP tool list remains the acceptance
    oracle.
  - **And the name is not the INVOCATION.** A harness may not expose MCP tools as callable
    functions at all, so the spelling can be right while the calling convention is something
    else entirely — a token-saving default is the usual reason. `[측정]` omp 18.0.0 mounts MCP
    tools as `xd://<tool>` virtual devices (`tools.xdev`, default on) that are READ for the
    schema and WRITTEN to for execution, and its `tools.xdevDocs` default keeps those schemas
    out of the prompt entirely; under that default a plain-language send listed peers and then
    falsely reported delivery, with nothing enqueued (#87). Measure the invocation form, name
    the setting that governs it, and put the required value in the operator doc. A tool surface
    that is only correct under a non-default setting is not admitted by its name.

  That document also holds the anonymous hatch and the PATH/env boundary. Bookmark it; a
  lane that could not find it burned three sessions re-deriving what it already said.

---

## 6. Sender identity — "who sent this?"

The bridge is a child process. It must be able to name the citizen that owns it.

- (a) Source: `pi-extensions/lib/meta-sender-identity.ts` (`META_SENDER_BACKENDS` and the
  resolver) plus a `writeMetaSenderMarker` call in the backend's birth payload. The join is:
  **the hook writes a marker keyed by ITS parent pid; the MCP child looks a marker up under
  its own parent.** The shared ancestor is the join key — not cwd, not a wire field.
- (b) Order, and it is not negotiable:
  1. **Measure the join first.** Confirm `hook.ppid == mcp.ppid == the harness host pid`,
     with the same start-key, on this vendor. If that is false, a marker will be written
     where nothing looks for it and the whole step is dead code.
  2. Then write the marker, behind the same three guards every other writer uses — a
     plausible owner pid, a pid+start-key liveness key, and the backing meta-record as the
     authority.
  3. Then open the reader by adding the backend to `META_SENDER_BACKENDS`. **Both halves are
     required**: a marker nobody reads and a reader with no marker fail identically.
  - Gate: extend the backend's own birth gate rather than minting a second one. It runs the
    real launcher as a child, so the marker's `ownerPid` is the gate's own pid — the same
    parent-pid join production performs, with an oracle independent of the writer.
    Precedent: `scripts/check-agy-sender-identity.ts`.
  - Fail closed, and keep the two failures apart in the log. *Refused* (no launch
    provenance, or an implausible parent) is the designed answer, not a fault — an already
    open session that predates the install reaches the payload through an unstamped path
    and correctly claims no owner; restarting it arms who-sent. *Failed* (the write itself
    broke) is a real fault. Both leave a citizen that still exists and can still be
    addressed by others; only its own outbound sends fall back to the default refusal.
  - Then teach the backend's doctor the difference. `[측정]` Adding a marker write to a
    birth payload puts an ERROR *after* the successful mint line, and a doctor whose
    recovery rule is "an error with no successful mint after it" will read that as a birth
    failure and print a sentence that is false. Judge mint errors and marker errors on
    separate axes.
  - **Sanitize inherited identity carriers in every new or amended native managed launch.** The
    MCP bridge reads a complete `PI_SESSION_ID` + `PI_AGENT_ID` pair before it tries a native
    sender marker. A non-pi harness started from a pi citizen's bash can therefore inherit and
    impersonate the parent pi garden id unless its launcher removes both variables before exec.
    This is a shared external-host boundary, not an OMP-specific patch: #82's remaining Copilot
    fresh work and every later native admission must clear foreign identity carriers, then let
    that harness's own trusted birth marker establish identity. Bundle C answered it at the
    seam rather than per launcher: `PI_SESSION_ID` and `PI_AGENT_ID` are scrubbed for EVERY
    backend before exec (`5bb1d50`), so a new launcher inherits the clearing instead of owing
    its own certification.
- (c) Two confusions this step exists to prevent:
  - **who-sent ≠ replyable.** They are different facts on different rails. A sender marker
    proves identity; whether a reply can *land* is answered by the receive rail of step 7 —
    a receiver marker for a self-fetch backend, an adapter probe for a native-push one. A
    backend can legitimately be `identity: garden-id` and `replyable: false` at the same
    time, and forcing the second to `true` is a lie the receiver acts on.
  - **The anonymous hatch is not a substitute for this step.**
    `ENTWURF_BRIDGE_ALLOW_ANONYMOUS_SENDER=1` opens sending at the price of identity: the
    message lands as `external-mcp`, non-replyable, and the receiver never learns who wrote
    it. It is a documented operator escape for a host with no citizen lifecycle — not a
    cheaper version of step 6.

---

## 7. Receive / notification

Only what the vendor actually ships. This is the step where imagination is most expensive.

- (a) Source: whatever real surface the measurement in step 1 found. For Claude Code that is
  a per-session mailbox armed by a receiver marker, with `FileChanged` as the doorbell and
  `asyncRewake` for the idle wake. For Antigravity it is native-push through the adapter and
  a live probe — **no mailbox and no receiver marker at all.** For Copilot CLI 1.0.80 it is
  the bundled first-party extension SDK: the CLI forks the extension, speaks JSON-RPC over
  the child's stdio, `joinSession()` binds the foreground native session, and the documented
  `fs.watch` → `session.send({mode:"enqueue"})` pattern supplies the idle wake. This is not
  the rejected hidden `--ui-server` loopback route.
  - **Who holds the watch decides who owns the marker.** Claude's CLI arms its own watch, so
    the marker names the CLI pid. Copilot's watch lives in a forked child, so the marker
    names the EXTENSION pid and carries `ownerKind: "copilot-extension"` with
    `armProvenance: "extension-join"`. Get this backwards and a crashed receiver stays
    "armed" for as long as the host process lives — the citizen reads deliverable with
    nothing watching its mailbox. Ask: which process would stop existing if the doorbell
    stopped working? That one owns the marker.
  - **A second process means a second install surface.** Copilot's receiver is not part of
    the birth plugin: `run.sh install-copilot-receive` owns its own artifact, install-state,
    doctor and inverse. Four Copilot surfaces (birth, statusline, MCP, receive), four
    installers, four failure modes.
- (b) Acceptance is a live receipt on the real harness, never an inference. `[측정]` On
  2026-08-23 an extension-armed idle Copilot session woke with zero typing, received a unique
  marker, replied with that marker in the same native session, and returned to `session.idle`.
  Evidence is L4 on one Linux workstation. A second armed process was observed to remain
  untouched, but its decisive log was not preserved before scratch cleanup; D3 isolation
  therefore remains a rerun. The travelling receipt is in
  `scripts/raw-async-delivery/README.md`.
  - A hermetic gate is the OTHER half, and it is not a substitute. `check-copilot-receive-arm`
    forks the shipped `extension.mjs` with the SDK specifier resolved by a loader hook — the
    vendor's own mechanism — so everything on entwurf's side of the fork (which id it binds,
    which pid owns the marker, what the doorbell says, when it refuses) is proved without a
    model turn. What it cannot prove is that a real turn starts on the other side. Keep the
    two receipts separate, and never let the green one stand in for the missing one.
- (c) The rules that keep this step honest:
  - **Never infer a receiver from a sender.** They are separate markers with separate
    meanings. Copilot outbound identity was accepted before its receive transport was found;
    neither fact grants the other.
  - **Use a vendor-owned wake mechanism; do not invent an external watcher, delivery adapter,
    or polling supervisor.** A watcher *inside* the vendor's documented extension lifecycle
    is different from an entwurf sidecar pretending to own that lifecycle. `entwurf_v2`
    still starts no process.
  - **Transport proof is not product admission.** The Copilot extension receipt removed the
    transport objection; admission was the separate work of owning installation and the
    feature flag, joining the armed receiver to the V3 record, refusing stale/crashed/drifted
    receivers, and routing dispatch. That landed in RAIL 5 — and the raw probe's `ready.json`
    did NOT: a file the receiver writes about itself is discovery evidence, so the product
    replaced it with a record-bound marker whose owner pid is verifiable. When a probe's
    convenience artifact survives into the product, that is the smell to look for.
  - **Keep experimental availability visible — and check it where it is decided.** Copilot
    scans extensions only when `COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS` is present;
    without it the scan is silently skipped. No installer can set that flag — it belongs to
    the launch, not to anything on disk — so ownership here splits in two. **A launch you own
    can set it:** `entwurf copilot` execs the vendor CLI with the flag for that one
    invocation and refuses if the receiver it is promising is not installed. **Every other
    launch you can only DETECT:** `doctor-copilot-receive` identifies the live CLI processes
    from their argv — the vendor entry they were exec'd with, never their command name, which
    the shim's own `exec` makes unusable — reads `/proc/<pid>/environ`, and goes red when the
    receiver is installed and a running session could never arm. Take both halves: a managed
    launch is not a substitute for the doctor, because operators start sessions their own way,
    and a vendor silence you cannot remove is a doctor's job rather than a reason to promise
    the capability anyway. The flag's durability across
    releases stays an open risk, not a reason to erase the demonstrated transport.
  - **A watch INSIDE the long-lived host is a different marker than a watch in a child,
    and the difference is one specific cell.** `[측정]` OMP's extension runs in the
    operator's own TUI process, so its receiver marker names that process — which means
    pid + start-key can prove the HOST is alive and can never prove the WATCH still works,
    and it cannot see the citizen change underneath a living process at all. `/new` mints a
    replacement citizen on the SAME pid with the SAME start key, so a receiver that did not
    explicitly unarm would leave the previous garden id reading deliverable forever while
    dispatch enqueued into a mailbox nobody watches. Nothing upstream can catch it: from
    outside, the process really is alive. Ask, for any in-process watch: *what changes
    underneath this marker without the process dying?* Each answer is a cell you must
    unarm by hand (here: `/new`, a watcher error, our own close, and a mailbox archived out
    from under a live inode). What remains — a wedged event loop — is the residual this
    rail INHERITS from Claude's, and the honest move is to say so in the same words the
    Claude unit already uses, not to claim it closed.
  - **The vendor's call sites are measurements, not details, and they are not consistent
    with each other.** `[측정]` on omp 18.0.0 `setStatus` is on the event `ctx.ui` while
    `sendUserMessage` is on the FACTORY `pi` object; and the repeating timer's canceller is
    `ctx.clearTimer` with no `ctx.clearInterval` at all — so `ctx.clearInterval?.(handle)`
    is a silent no-op that leaves an uncancellable poll running inside the operator's TUI.
    Probe the canceller BY NAME and refuse to start a timer you cannot stop.
  - **An acceptance must not require the model to disobey your own doorbell.** `[측정]` an
    acceptance that asked the model to echo a nonce from a mailbox body failed: the model
    drained the inbox, recorded the receipt, and declined the instruction because the
    doorbell had told it the body was untrusted. It was right. Accept the READ — the thing
    the self-fetch contract actually promises — and join it to the session through the
    vendor's own transcript, since `entwurf_inbox_read` takes a caller-supplied garden id
    and `lastReadAt` alone cannot say WHO read it.
  - Note where notification actually goes. `[번들]` Copilot's separate `agentStop` output
    contract is `{decision?:"block", reason?:string}` and a blocked reason becomes a follow-up
    user message. That turn-boundary hook is not the idle-wake transport above and must not be
    used as its substitute.

---

## 8. Grade

Only after acceptance, and both places move together.

- (a) Source: the `DELIVERY.md` current matrix **and** `pi/entwurf-capabilities.json`
  (`wakeMode`, `deliveryLevel`).
- (b) Gate: `check-entwurf-capabilities` holds the registry against the backend constant.
- (c) A grade is a claim about evidence, so it moves when the evidence moves — not when the
  code lands. Two failure shapes to avoid: a registry that promises a `wakeMode` with no
  channel behind it, and a matrix row still describing a lane that has since been walked.
  `[측정]` Copilot is the worked example of that rule running in BOTH directions. It walked
  all of steps 1–7 as a branch product — receiver installed, record-bound, liveness-guarded,
  on the mailbox rail, hermetic gate green — and its registry grade stayed `D0` through all
  of it, because no green gate is a wake. The grade moved only when the evidence did: on
  2026-08-23 a managed LIVE acceptance ran on garden `20260823T181316-d9f6ba` (CLI 1.0.80)
  and left a joined→armed→doorbell→rang receive log, a mailbox stamped
  `lastEnqueuedAt 09:23:41.235Z` / `lastReadAt 09:23:56.480Z`, and a model reply on the same
  record/native/gid chain. That — not the landing of the code — is what made it `D6`.
  The same discipline caps it: D7 stays PARTIAL (reply and read receipt observed; completion
  taxonomy and long-haul operation not), D3 is PENDING because its decisive log was lost to a
  scratch cleanup before anyone copied it out, and D8 is unproven. Grade the product, not the
  prototype, and keep the raw probe's own D-levels recorded separately in `DELIVERY.md`
  rather than hiding either fact. If you take one habit from this row, take the boring one:
  **move the receipt out of scratch before you close the terminal.**

---

## 9. Visible lifecycle parity — onboarding is not finished at birth

The adapter work above and the lifecycle implementation remain separate modules, but product
admission joins their evidence. Starting with native-harness admissions made under this #82
contract, a backend may be declared **supported** only when it can be opened as one visible fresh
sibling through `entwurf_fresh_call` with the same operator contract as every other supported fresh
backend. This rule does not delete historical records or retroactively reinterpret preserved
registry grades: a pre-contract backend that has not walked this step remains legacy/probe evidence
and must not be described as supported until it is re-evaluated here.

1. one fixed managed runtime path — never an arbitrary command or raw tmux workaround;
2. an explicit model and an explicit permission policy in the vendor's measured argv dialect.
   The policy has a **width**, not just a spelling: say whether the grant is callback-only or
   task-wide, and carry the chosen width as an explicit argv token rather than relying on a
   launcher's injected default. A callback-only sibling will reliably name itself and may then
   stop at the first tool its TASK needs — that prompt is that policy working, not a launch
   defect — while a task-wide grant hands an agent-opened sibling every permission the managed
   profile carries. Either width is a decision the OPERATOR makes explicitly, never a default
   that drifts in;
3. a pre-mutation, fail-closed preflight for the **four** static capabilities the fresh prompt
   needs — birth, MCP hand, receive, and visible identity — decided before the tmux mutation
   so a missing unit is a named refusal, not a dead window plus a launch receipt. Receive must
   use the same env seam the managed launcher will scan (a unit that exists in a different
   extensions root is not ready);
4. a garden id shown on the harness's own persistent visible identity surface. The fact is the
   **effective configuration** the vendor will read, not entwurf's ownership receipt, and not a
   LIVE render: those are three different proofs. A receipt may contradict; its absence alone
   does not;
5. callback as the first action, using that harness's measured tool name;
6. exact nonce correlation from the callback sender envelope, with launch and callback receipts
   kept separate;
7. one real visible LIVE receipt through callback and addressed receive.

A backend the composition can open must appear as the same fixed set on every public surface
that offers `entwurf_fresh_call` — native pi, the MCP bridge, and the operator skill. A backend
added to the module but not to a surface is unreachable there; one added to a surface but not
the module is a schema that admits a value the composition cannot open. All three are now
observed by `test/fresh-call-surfaces.contract.test.ts`: the two schema surfaces from a real boot
and a real registration, the skill from its own contract line. The skill was the one that had no
gate at all until #87 Bundle C, which is worth remembering when a rule names surfaces in prose —
the enumeration is not the enforcement.

If one of these cannot be implemented from vendor-owned surfaces, the outcome is **do not admit
that harness**, not “citizen but you cannot open/call it.” Same-id resume is a separate optional
capability: add it only when a record can authoritatively recover the vendor's transcript/model/cwd
without guessing. Internal subagents stay inside the top-level citizen throughout lifecycle work;
do not connect a vendor's internal hub/team protocol to entwurf merely to expose its private hops.

### The release stop — partial evidence is a BRANCH state, never a shipped one

Steps 1–8 can be walked incrementally, and a branch carrying a harness that has reached step 7 and
no further is a normal, healthy state. **A release package is not.** A release that introduces a
new native harness may not be cut until that harness has closed step 9, and the two halves of that
rule are both executable rather than remembered:

- **Deterministic:** `check-harness-admission-parity` (in `pnpm run check:full`) requires every
  backend in `META_CITIZEN_BACKENDS` to be in `FRESH_CALL_BACKENDS` or to be a declared pre-#82
  legacy admission whose exception a reader can find in `DELIVERY.md`. A post-contract harness that
  mints records but cannot be opened turns the floor red.
- **LIVE:** the first release of a harness admitted under this contract owes the clause 7 receipt as
  a release-gate MUST step, because a schema is not a product. `smoke-omp-fresh-live` is the worked
  instance. This applies from OMP onward; it does not retroactively redesign the operator-metered
  exclusion Copilot's visible fresh was accepted under.
- **LIVE, the cross-harness leg (GLG directive, 2026-08-31):** clause 7 proves the new harness
  against the bridge caller; it does not prove one live model turn CROSSING harnesses in either
  direction. And the fixed delivery chain does not grow at admission — `[측정]`
  `smoke-entwurf-chain-live` still walks the three hops it was born with (`429d5c3`, 2026-07-31);
  neither #82 nor #87 touched it, and the v1 mutual-call matrices (`session-messaging-smoke.sh`,
  `sentinel-runner.sh`) left the release gate at `d7783d4` and were deleted at `fbcbdbc` with a
  v2 follow-up that never returned on the harness-PAIR axis. So the first release of a newly
  admitted harness also owes TWO cross-harness dispatch receipts: an existing citizen's live turn
  delivered into the new citizen, and the new citizen's live turn delivered into an existing one,
  each on the rail the registry claims for that direction. The chain stays fixed and the leg is
  per-admission, so the aggregate's standing cost does not grow (the Cortex exclusion lesson,
  `run.sh` release-gate notes). The deterministic half — every post-contract citizen backend has
  a wired cross-harness LIVE step or a declared metered exception a reader can find — belongs
  beside `check-harness-admission-parity` and is an owed follow-up (see NEXT): until that gate
  lands, this bullet is prose, and the block below says exactly what prose is worth without one.

**An `unsupported` note is not a partial-release permit.** `[측정]` #87 is where that was learned at
full price: the Bundle A+B candidate carried a fully honest sentence in the delivery matrix —
"Visible fresh is NOT implemented, so OMP is not a supported harness under step 9" — and shipped
toward a cut anyway, because no executable path consumed that sentence. Writing down what a harness
cannot do is necessary and is not sufficient; the gate is what makes the sentence load-bearing.

Two closed parity loops with nothing between them is the shape to watch for generally. The registry
gate held registry ≡ citizens, the surfaces contract held surfaces ≡ fresh set, both were green, and
no file read both constants. When two gates each guard one half of a claim, ask which one owns the
edge — and if the answer is neither, that edge is where the next release will leak.

### Worked example — Copilot CLI 1.0.80, the first admission under this contract (#82 RAIL 9)

Read this for the SHAPE of the evidence, not to copy its strings; every one of them is a measured
vendor fact with an expiry date at the next CLI upgrade.

| clause | what it turned out to be | where the fact came from |
|---|---|---|
| 1 managed runtime | runtime is `entwurf`, first forwarded token `copilot` — never the bare vendor, which starts without `COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS` and skips the extension scan SILENTLY | `mux-fresh-call.ts` `FRESH_CALL_RUNTIME`, `scripts/copilot-launch.sh` |
| 2 model + permission | `--interactive <prompt>` (NOT `-p`, which runs the turn and exits), `--model`, value as two tokens, and the explicit `--yolo` policy token. The width is a GLG decision (2026-08-25): the first cut's callback-only `--allow-tool=entwurf-bridge(entwurf_v2)` grant was measured LIVE to stop the sibling on a confirmation prompt at every task tool, so fresh now carries the same task-wide profile as a human-typed `entwurf copilot`. The measured grammar stays on record: `--allow-tool` takes `<server>(<tool>)` and is variadic, so its equals form is mandatory | `copilot --help`, `copilot help permissions`, GLG operator LIVE 2026-08-25 |
| 3 preflight | birth + MCP hand + receiver + visible footer, all decided before the tmux mutation | `pi-extensions/lib/copilot-fresh-preflight.ts` |
| 4 visible identity | the custom footer: `statusLine.command` + `footer.showCustom` in the settings the vendor reads, with the command resolvable | `scripts/copilot-statusline-*` |
| 5 callback name | `entwurf-bridge-entwurf_v2` — `<mcpServerName>-<mcpToolName>`, NOT Claude Code's `mcp__server__tool` | two sessions' own `~/.copilot/session-state/<id>/events.jsonl` |
| 6 correlation | unchanged: the nonce callback's sender envelope | `mux-launch-rail.md` §6-a |
| 7 LIVE | one visible window, one callback, one addressed receive | 2026-08-25: launch `@89`/`%89` nonce `mux-fresh-call-690529ae99f99faa2252aefb`; callback garden `20260825T085721-f68be0`; mailbox enqueue; `lastReadAt 2026-08-24T23:57:47.784Z`; same-gid reply; GLG footer visible. Rows stay unmerged. Operator-metered; not a release MUST |

Three lessons generalise past Copilot:

- **A harness can speak two dialects for one tool.** Copilot's model-facing name
  (`entwurf-bridge-entwurf_v2`) and its permission pattern (`entwurf-bridge(entwurf_v2)`) are
  different strings for the same capability. Measure the one each argv position actually wants;
  a single "the tool is called X" note will be wrong in one of the two places.
- **Clause 3's "pre-mutation" is load-bearing, not stylistic.** The managed launcher already
  refused on a missing receiver — but it runs inside the window that was just opened, so its
  refusal produces a dead window plus a launch receipt. A capability check the fresh lane can
  trust has to be decidable one layer above the mutation.
- **A capability's ownership receipt is not the capability.** The acceptance host had a correct,
  resolvable footer configuration and NO statusline install-state. Gating clause 4 on the receipt
  would have refused a working visible identity; the effective configuration is the fact, and the
  receipt is only checked for what it can still contradict.

### Worked example — OMP 18.0.0, the second admission (#87 Bundle C)

Read it against Copilot's, because the instructive part is where the two DIVERGE. Every clause is
the same; not one of its answers is.

| clause | OMP's answer | why it differs from Copilot's |
|---|---|---|
| 1 managed runtime | the BARE vendor, `omp` | Copilot needs `entwurf copilot` because the bare CLI silently skips its extension scan without a launcher-set flag. omp always scans, and the one thing it needs (`tools.xdev: false`) lives in the operator config — a PREFLIGHT fact, not something a launcher could supply. A managed verb here would have had nothing to manage |
| 2 model + permission | NO positional prompt: `--entwurf-bootstrap`, payload, then `--model`, value, then `--approval-mode`, `yolo`. `-p/--print` is still the forbidden flag — it runs the turn and EXITS | the width is the same GLG task-wide decision, but for the opposite reason: omp offers no argv grammar for a narrower grant at all (`tools.approval.<tool>` is a config axis). And the trap is inverted — omp's schema default is ALREADY `yolo`, so dropping the token changes nothing observable and the drift would be invisible to every behavioural test. The PROMPT half diverges hardest of all: Copilot's argv carries the whole first turn, omp's carries none of it — see "When argv cannot carry the first turn" below |
| 3 preflight | FIVE axes: birth, MCP hand, receive, visible identity, and **callback callable** (`tools.xdev !== true`) | the fifth is omp-specific and load-bearing for clause 5: the vendor default mounts MCP tools as `xd://` devices whose schemas never reach the prompt, so the sibling could be launched, be delivered to, and still never call anything |
| 4 visible identity | `ctx.ui.setStatus` inside the birth extension, gated by `statusLine.showHookStatus` (default true) | there is NO statusline command to resolve — v18's built-in segment set is a closed enum. Copilot's "is the command executable" predicate does not exist here, so the axis is derived rather than copied |
| 5 callback name | `mcp__entwurf_bridge_entwurf_v` | the sanitizer charset `[a-z_]` EATS the digit in `entwurf_v2`. Three harnesses, three spellings of one tool, and this is the one a careful reader still gets wrong by assuming the name survives |
| 6 correlation | unchanged: the nonce callback's sender envelope | — |
| 7 LIVE | `smoke-omp-fresh-live`, wired as a release-gate MUST — **green 2026-08-30, 21 assertions** (garden `20260830T192913-df52b9`, receipts in `DELIVERY.md`) | Copilot's was operator-metered and outside the aggregate. The rule changed here, forward-only: see "The release stop" above. It also took TWO runs — the first went red on stage-two delivery alone, which is the whole argument for a MUST |

The generalisable lesson is the fifth axis. Copilot's four axes looked like the shape of a preflight;
they were the shape of ONE vendor's preflight. Derive the axes from what the fresh contract needs on
THIS harness — for omp, "the callback tool is callable" turned out to be a configuration question
that no amount of correct installation could answer.

### When argv cannot carry the first turn — the two-stage bootstrap (#87 Bundle C)

Clause 1's "hand the sibling its task in the launch argv" is a DEFAULT, not a law, and omp is
where it broke. Read this before assuming the next harness can be opened with a prompt.

`[LIVE 2026-08-30]` the first public `entwurf_fresh_call(omp)` passed the standard framing as a
bare positional. Everything a gate can see went right: the window opened, the record minted
(garden `20260830T181342-452167`), the prompt arrived byte-identical as a user message at
`09:13:42.413Z`. The model answered the literal text `ACK` at `09:13:47.105Z` with **zero tool
calls**, and the caller timed out at 240s.

The cause is structural and it is in the vendor, not in the model or the host. `[source]` the
interactive UI DEFERS MCP discovery — `deferMCPDiscoveryForUI` starts `discoverAndConnect()`
fire-and-forget and only calls `refreshMCPTools()` once it settles (`sdk.ts:1847-1855`,
`:1881-1905`) — while the positional `initialMessage` prompts immediately after `await
mode.init()` (`main.ts:540-565`, `595-610`). `[측정]` an observer on the same runtime: `turn_start`
at +654ms with the entwurf tools ABSENT, callback tool present only at +1484ms. **The first turn
began ~830ms before the tool it was told to call existed**, and no argv can close that gap.

So the launch carries a PAYLOAD and the in-process extension owns the first two messages:

1. **A fixed registered flag, never a carrier.** `--entwurf-bootstrap <json>` with a closed
   `{v,target,nonce,task}` grammar; an unknown key is a refusal. `[측정]` a normal discovered
   extension that calls `registerFlag` at factory time receives the argv value byte-identical
   (quotes, `$VAR`, backticks, `;` all survived), because extensions load BEFORE argv
   classification and the reparse fills the registered map (`main.ts:1799-1810`,
   `cli/extension-flags.ts:36-43`). Register at factory time or never: a flag registered after
   that reparse is never filled.
2. **Bounded readiness on TWO snapshots.** There is no public MCP-ready event in v18.0.0 — the
   only mechanisms are private (`mcp/manager.ts:296-306`) or for extension-registered tools
   (`runner.ts:907-978`). Poll `getAllTools()` for the exact name with `sourceInfo.source ===
   "mcp"` AND `getActiveTools()` for the same name; registered-but-not-enabled is not callable.
   A FIXED DELAY is wrong: the gap is a race, not a constant.
3. **A callback-ONLY prompt.** No task, no ACK, no competing goal. `[측정 2026-08-30]` this is
   the half that was proven: model `openai-codex/gpt-5.6-sol`, tool live at +1105ms, prompt at
   +1107ms, sibling calls `mcp__entwurf_bridge_entwurf_v` with the exact nonce.
4. **The task ARMED by a tool RESULT, never a call.** `tool_call` fires before scheduling and
   before approval (`agent-session.ts:3431-3467`), so it proves only an attempt. Store the
   matching call's `toolCallId`; arm only when the `tool_result` carries that same id, the same
   tool/target/nonce, and `isError === false` (`extensions/types.ts:966-1017`; MCP protocol
   errors set it, `mcp/tool-bridge.ts:230-275`).
5. **The task SENT at the next `turn_end`, with no delivery option — and this is the step that
   cost a second LIVE.** `[LIVE 2026-08-30]` the first attempt sent from inside the `tool_result`
   handler with an explicit `deliverAs: "followUp"`. The whole chain logged correctly
   (`bootstrap-armed` → `bootstrap-ready` +440ms → `bootstrap-callback-observed` →
   `bootstrap-released`) and the task **never appeared in the session at all**. `[source]` the
   vendor says why in one sentence: "Omitted `deliverAs` starts a turn when idle and queues as a
   steer while streaming. Explicit `deliverAs` queues WITHOUT starting a turn in either state."
   (`agent-session.ts:6511-6513`). Inside a `tool_result` handler the callback turn is still
   streaming, so BOTH options are wrong there — explicit queues into a turn nobody starts, and
   omitted steers the callback turn. The same transcript proved the working form three seconds
   later: the receiver's doorbell used the omitted-option send on the now-idle session and it
   landed as a real user message that started a turn. So arm in `tool_result`, send at
   `turn_end` (`shared-events.ts:211-217`), latch before sending, and never pass a delivery
   option. **The generalisable trap: a `sendUserMessage` that returns void and logs nothing is
   indistinguishable from a delivered one — only the session's own transcript can tell you.**
6. **One launch, one bootstrap.** `getFlag` reads a per-process map that is not consumed by
   reading, so `/new`, fork and resume would re-arm it and send the caller's task into a session
   the caller never opened. Latch it.

The generalisable rule: **clause 1 owes the sibling a first turn, not an argv.** Before choosing
a positional prompt, ask whether the harness can guarantee its MCP tools are callable when that
turn starts. If the answer is "it connects them in the background", argv is the wrong carrier and
the in-process unit is the right one — and the failure mode you avoid is the worst kind, because
the window opens, the record mints, and every deterministic gate stays green.

---

## 10. One command — an onboarding is not finished until `setup` composes it

Every unit above is an operator-selectable verb with its own install-state, doctor and inverse.
That is the right decomposition and it is not the deliverable. The deliverable is that a fresh
host reaches the same place by running `entwurf setup` once. A harness whose units exist but are
not composed there is not installed — it is installable, which is a different claim and a much
weaker one.

`[측정]` OMP is the worked example, and it is the expensive kind. v0.16.0 shipped OMP as a D6
citizen with birth, MCP hand and receiver installers, four doctors, four inverses, a LIVE fresh
receipt and a cross-harness leg — and `setup_all` had no `omp` branch at all. On an operator host
running the released package, `entwurf setup` printed **green** while OMP had nothing installed:
no extension, no `mcp.json` entry, no visible garden id. Every gate agreed, because every gate
asked about the units and none asked whether the one-command surface reached them. The same host
also had no `tools.xdev: false`, since that was a documented hand-edit in `setup-clean-host.md`
rather than a writer — so even a hand-run verb list left the citizen holding tools the model
could not call.

So the step is: **add the harness to `setup_all` in `run.sh`, presence-driven, one named
component per unit, and pin its probe in the aggregate gate.** Concretely:

1. **Presence is the only trigger.** The vendor binary on PATH composes; absent is exactly one
   zero-state SKIP row. Setup never installs a harness, a subscription or a credential.
2. **One component row per unit, decided independently.** A failed unit is a named FAIL that
   keeps the other units and the rest of setup alive and owns a nonzero final exit. Never a WARN,
   never a cosmetic PASS, never a SKIP that stands for "detected but broken".
3. **Compose only lifecycles you can also undo.** A unit belongs in `setup` once its
   package-owned inverse exists — otherwise the one command writes state the operator cannot
   take back.
4. **Operator SETTINGS are units too, not documentation.** If the harness needs a value in a
   vendor config for entwurf's tools to be reachable, it needs a writer that owns exactly the
   lines it adds, refuses a config it cannot parse, refuses to write through a symlink, and
   refuses to overwrite an explicit contrary operator value **by name** — a disagreement between
   two authorities is a FAIL the operator resolves, never a silent overwrite.
   `scripts/omp-config-xdev.py` is the reference shape.
5. **Pin the probe seam and add an aggregate cell.** `smoke-setup-verdict` defaults every
   harness probe to a definitely-absent path (`PI_BIN` / `CLAUDE_BIN` / `AGY_BIN` /
   `COPILOT_BIN` / `OMP_BIN`), so a new harness owes both an absent row in S-1 and a
   present-harness cell that drives the real composition against a stub vendor and asserts every
   install-state, the artifacts in the sandbox agent dir, and idempotence on a second run.
   Without the pin, the developer's own host leaks into the fixture.
6. **Then update [`setup-clean-host.md`](./setup-clean-host.md)** so the hand-run verb list
   becomes what it should be — a repair path, not the install.

The general shape, once more: two closed loops with nothing between them. The unit gates held
unit ≡ doctor ≡ inverse, the admission gates held registry ≡ citizens ≡ fresh set, and no gate
owned the edge from *the units exist* to *the one command reaches them*. Ask which gate owns that
edge before the cut, not after an operator's clean host comes up green and empty.

---

## The five documents this one points at

| Document | Owns | Reached from |
|---|---|---|
| [`acp-backend-rail.md`](./acp-backend-rail.md) | the ACP adapter lane end to end | step 0, the other side of the fork |
| [`fresh-cut-policy.md`](./fresh-cut-policy.md) | recovery when a record generation is genuinely unreadable | step 2 — and only after redeploy has been ruled out |
| [`external-mcp-host.md`](./external-mcp-host.md) | per-harness bridge registration, external vs garden-native semantics, the anonymous hatch, the PATH/env boundary | steps 5 and 6, as required detail |
| [`setup-clean-host.md`](./setup-clean-host.md) | operator reproduction of the whole install on a fresh host | after any step that adds an installer or doctor — and step 10, which decides what stays a hand-run verb |
| [`mux-launch-rail.md`](./mux-launch-rail.md) | opening a fresh sibling and reopening a dormant one | step 9 — separate implementation, required admission evidence |

Verification protocol and evidence levels stay in [`../VERIFY.md`](../VERIFY.md); recorded
host evidence in [`../BASELINE.md`](../BASELINE.md); the invariants every step above must
respect in [`../AGENTS.md`](../AGENTS.md) — in particular Hard Rule 7, which remains the
authority on the meta-record store contract that step 2 touches.
