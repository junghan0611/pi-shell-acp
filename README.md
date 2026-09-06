# entwurf

`entwurf` is a garden-citizen dispatch substrate: a thin bridge that lets already-existing agent harnesses address one another by **garden id** without pretending to own each other's transcript, auth, or runtime.

![entwurf — a forged screwdriver for garden-citizen dispatch](docs/assets/entwurf-hero.jpg)

[![npm](https://img.shields.io/npm/v/@junghanacs/entwurf?logo=npm)](https://www.npmjs.com/package/@junghanacs/entwurf) · maintained by [junghanacs.com](https://junghanacs.com/)

npm package: <https://www.npmjs.com/package/@junghanacs/entwurf>

Legacy package: [`@junghanacs/pi-shell-acp`](https://www.npmjs.com/package/@junghanacs/pi-shell-acp). `entwurf` is its 0.12+ successor line: the same work renamed around the garden-citizen dispatch substrate rather than the pi adapter.

> **Repository shape.** This repo is **entwurf-core (v2 dispatch) + native-harness bridges + a pi adapter + an ACP plugin**. Pi is one supported harness adapter — important because it supplies control sockets and hosts the ACP plugin today — but it is not the project subject. Claude Code and GitHub Copilot CLI are shipped as mailbox-backed self-fetch meta-sessions; Antigravity (`agy`) is shipped as a native-push citizen with automatic `PreInvocation` birth, ambient garden-id status, and a managed MCP/permission install surface. OMP (`omp`) is a self-fetch citizen on the same rail as Claude and Copilot, opened by `entwurf_fresh_call` and accepted under the step 9 visible-fresh contract on 2026-08-30 — its first turn is a two-stage in-process bootstrap rather than an argv prompt, because the vendor connects its MCP tools in the background after the session starts. Codex has a launch-mode-specific verified delivery probe documented in [DELIVERY.md](./DELIVERY.md), but no managed native-citizen install lane yet. The ACP plugin ships two backends through one adapter rail: Claude (the reference) and Snowflake Cortex Code (landed in 0.13.0 under the measured contract in [docs/acp-backend-rail.md](./docs/acp-backend-rail.md#cortex-code-audit-d1d10)).

```text
Claude Code / Copilot / Codex / agy / omp / pi
  → garden id
    → entwurf_v2
      → control-socket | meta-mailbox | native-push
```

[`entwurf_v2`](#entwurf_v2--canonical-dispatch-verb) is the canonical dispatch surface over *existing* garden citizens — live control-socket send, meta-mailbox enqueue, and native-push into a live Antigravity conversation. It starts no process on any rail: the hidden background resume that used to answer a dormant target was withdrawn under the visible-first rule, so a dormant citizen rejects honestly here and is reopened by a separate lifecycle verb, `entwurf_resume_call`. The meta-record is the sole address authority (#50 C4): a record-less control socket is refused as a `record-less-socket` diagnostic, never dispatched. The v1 entwurf verbs are gone. Fresh siblings and resumes are separate verbs — `entwurf_fresh_call` opens a NEW sibling in the operator's own tmux session and learns its garden id from the callback it makes, while `entwurf_resume_call` reopens a DORMANT pi citizen under its own garden id in a visible window without running a turn; the non-Claude ACP lane landed earlier — Snowflake Cortex Code became the second backend in 0.13.0.

**Garden id is deliberate vocabulary.** It is not a decorative synonym for session id, worker, delegate, or subagent. The unfamiliar word is a guard: each harness keeps its own identity and transcript, while `entwurf` supplies a narrow addressable surface between siblings.

**A narrow harness tool surface is discipline, not a missing feature.** When entwurf drives a backend the way pi taught — the ACP Claude session, a pi-native sibling — it runs without a sub-agent tool or a todo tool, on a narrow tool surface in auto-approve (`yolo`) mode (the ACP backend yolo-runs inside its isolated overlay). That restraint is the point: it keeps the one forged screwdriver from drifting into a second orchestrator, and keeps the operator's own driver — not a hidden agent swarm — the thing actually steering. See [AGENTS.md](./AGENTS.md) North Star.

**The ACP plugin is one ingress, not the boundary.** It re-enters as a pi provider/model on a host `--entwurf-control` session that is *already* a v2 socket-citizen; it does not mint its own socket / peers / citizen layer (see [AGENTS.md](./AGENTS.md) §ACP Plugin Boundary). No OAuth proxy, no subscription bypass, no CLI transcript scraping, no Claude Code emulation.

```text
pi --entwurf-control
  → entwurf ACP plugin
    → claude-agent-acp
      → Claude backend under the operator's local auth
```

**Native bridges reach beyond ACP transport.** A global `SessionStart` hook registers native Claude Code sessions as **garden-native meta-sessions** with a garden id, a mailbox, and a trusted sender marker. That makes an already-running Claude Code terminal addressable through `entwurf_v2` (the mailbox path), self-identifying through `entwurf_self`, and replyable by garden id — without turning pi into a second harness or importing Claude's transcript.

```text
native Claude Code
  → SessionStart hook
    → mailbox-backed meta-session <garden-id>
      → entwurf-bridge MCP
        → entwurf_self | entwurf_v2 | entwurf_inbox_read
```

Copilot uses another self-fetch rail. Its birth hook mints the V3 record on the first prompt,
the MCP hand supplies `entwurf_inbox_read`, and a first-party extension arms the receiver marker
and rings a doorbell for queued bodies. Supported launch is `entwurf copilot`; visible fresh uses
that same managed invocation so extension scan, receiver preconditions, model, and permission
policy are present before the sibling calls back with its garden id.

Antigravity uses a separate shipped rail. Its `PreInvocation` hook births or re-attaches the conversation by native `conversationId`, writes a record-backed sender marker, and leaves delivery to the live native LS gRPC route. There is no mailbox or receiver marker on this rail: `entwurf_v2` probes the conversation and direct-injects with native-push.

```text
native Antigravity / agy
  → PreInvocation imprint → meta-session <garden-id>
  → entwurf-bridge MCP sender identity
  ↔ entwurf_v2 native-push
```

Claude's `install-meta-bridge`, Copilot's four `install-copilot-*` surfaces, agy's
`install-agy-{bridge,statusline,hooks}` and OMP's four `install-omp-{bridge,mcp,config,receive}`
units are distinct because their lifecycle and delivery transports are
genuinely different. Codex remains verified probe evidence, not a shipped managed native-citizen
lane; see [DELIVERY.md](./DELIVERY.md).

> **Direction.** Inverse of [`pi-acp`](https://github.com/svkozak/pi-acp). `pi-acp` lets external ACP clients talk *to* pi; `entwurf` lets garden citizens talk across harness boundaries — with pi as one adapter, not the center.

## Concept primer

A few words that look unusual for a coding tool.

- **Entwurf** (기투, projection-of-self) — sibling sessions with their own runtime boundary. Not "delegate," not "worker," not "sub-agent." Opening a visible sibling (`entwurf_fresh_call`), live peer messaging (`entwurf_v2`) and reopening a dormant one (`entwurf_resume_call`) are first-class; the hidden background resume that preceded the last of those was withdrawn under the visible-first rule.
- **Garden / garden id** — the garden is the shared address space where independent harness sessions become citizens without losing their own runtime or transcript. A garden id is the stable address of one such citizen (for pi, a garden-native session id like `YYYYMMDDTHHMMSS-<6hex>`; for native harnesses, a meta-session id minted from an authoritative lifecycle hook — Claude `SessionStart`, Copilot's first-prompt birth hook, agy `PreInvocation`, and for OMP an in-process extension bound to both session edges that mints only the visible `mode === "tui"` host). It is not a worker name and not proof that pi owns the session. The same-looking id may name a live control socket, a dormant pi record, a mailbox-backed native session, or a native-push conversation, so callers discover facts with `entwurf_peers` and deliver with `entwurf_v2` instead of choosing a transport by hand.
- **Engraving** — optional short operator text delivered through each backend's native identity carrier. Not a giant hidden prompt, not a tool catalog.
- **MCP** — in this repo, MCP is just the transport by which ACP-backed sessions receive pi capabilities that native pi exposes directly as extensions. It is not a general MCP platform. Explicit `entwurfProvider.mcpServers` only; no ambient `~/.mcp.json` scanning, no automatic retrieval. The same `entwurf-bridge` entry can also be wired into another host's MCP catalog (Claude Code, Copilot, Codex, Antigravity, OMP, …) when the operator chooses. `entwurf_self` returns an authoritative pi-session or trusted meta-session identity envelope; `entwurf_v2` requires an authoritative sender by default (#50 C4) — a plain external MCP host with no identity lane is refused unless the operator explicitly wires the documented anonymous hatch, and even then it is never replyable.
- **Session persistence** — re-attaches pi to the same remote ACP session. Does not hydrate backend transcripts into pi history.

## Install

`entwurf` is a neutral npm package first. Get the package, then run **`entwurf setup
<project>`** — one command, the same front door from an npm global install, an npm
project-local install, or a source checkout. It composes every harness it finds on the
host and reports each one PASS / SKIP / FAIL. You are not meant to assemble the parts by
hand; the per-harness installers further down are the repair surface for when one unit
needs to be redone alone. Pi is still the adapter that hosts the ACP plugin and live
control-socket surface, but the base install is **not** `pi install npm:...` anymore.

The package exposes six bins:

- `entwurf` → `run.sh` (installer, checks, native-bridge doctors/installers)
- `entwurf-bridge` → the MCP stdio launcher (`mcp/entwurf-bridge/start.sh`)
- `entwurf-statusline` → the Claude Code statusline renderer (`scripts/meta-bridge-statusline.sh`)
- `entwurf-agy-statusline` → the Antigravity garden-id statusline renderer (`scripts/agy-statusline.sh`)
- `entwurf-agy-imprint` → the Antigravity `PreInvocation` birth/sender hook (`scripts/agy-imprint.sh`)
- `entwurf-copilot-statusline` → the Copilot CLI garden-id footer renderer (`scripts/copilot-statusline.sh`)

The bridge/renderers/hook use stable bin names so package upgrades do not bake versioned package-store paths into native-harness settings.

Installing Entwurf installs **Entwurf only**: its package bytes, six bins, bridge, and
integration artifacts. It does not install `pi`, Claude Code, Copilot CLI, Codex, agy, omp, Cortex,
or any other harness runtime. Those are operator choices and may all be absent. The bridge also
does not provide credentials, tokens, subscription access, or an auth bypass; whatever an
operator-installed harness already trusts is what Entwurf can use. `setup` is composition, not
recruitment: it may wire a harness that is present, but never downloads one to make a matrix cell
look complete.

### From npm — user/global install

```bash
npm install -g @junghanacs/entwurf

entwurf setup /path/to/your-project
entwurf check-bridge
```

`setup` wires the target project for the pi adapter / ACP plugin lane and composes
whatever native harnesses are present. The global install is the easiest path when
Claude Code's USER-scope MCP registration should work from every cwd.

### From npm — project-local install

```bash
cd /path/to/your-project
npm install --save-dev @junghanacs/entwurf

npx entwurf setup .
npx entwurf check-bridge
```

For an npm upgrade, rerun `setup` in the same scope (use
`@junghanacs/entwurf@latest` when you want the registry's stable line explicitly),
then make the first check from that same scope: `entwurf check-bridge` for a global
install or `npx entwurf check-bridge` for a project-local install. Native-harness
repair and process restarts remain a separate post-upgrade step below.

`entwurf install <project>` is the narrower repair leaf: it writes only
`.pi/settings.json` in the target project, with the absolute path to the installed
`entwurf-bridge` launcher, and composes no harness. Reach for it when the pi wiring
alone needs redoing. (The old `~/.pi/agent/` target-registry link is gone — #50 C3;
nothing reads it.)

To register the bridge in an MCP host by hand from a project-local install, point it at
`node_modules/.bin/entwurf-bridge` — see
[External MCP registration](#external-mcp-registration).

### From source — development clone

```bash
git clone https://github.com/junghan0611/entwurf ~/repos/gh/entwurf
cd ~/repos/gh/entwurf

./run.sh setup /path/to/your-project
./run.sh check-bridge
```

The full source setup requires Node 24, pnpm, and Python 3 on PATH. Harnesses are
optional-by-presence: `setup` runs the frozen dependency install, then composes what the operator
already installed — a compatible `pi` (`>=0.85.1 <0.86`), Claude Code, agy, and the Copilot CLI
each get their wiring completed when detected, an absent harness is an explicit zero-state SKIP,
and a detected harness that cannot be completed (including a below-floor `pi`) is a named FAIL
that makes setup exit nonzero. `setup` never installs a harness binary or touches a credential
store. It also exposes stable commands under `~/.local/bin`, including `entwurf` → this
checkout's `run.sh`, so managed Copilot fresh does not depend on an unrelated global npm/pnpm
installation. A detected `copilot` composes all four of its native units (birth → MCP →
receiver → visible footer) in one go. Package consumers
run the same `entwurf setup <project>` through their npm-provided bin: installed mode is decided
by name first, skips the source-only pnpm bootstrap entirely, and reports the stable commands as
already provided by npm bin linking.

The pi user-scope registration is ONE shared entry with a recorded owner (#86 C2): installing
from a second checkout or npm root does not silently steal it — normal `install`/`setup` refuse
with zero settings bytes written, `entwurf takeover-user-scope` is the operator-explicit move,
`entwurf doctor-pi-package` names the ownership verdict, and `entwurf remove-user-scope` is
same-owner-only. The full contract — atomicity across the package and provider halves, the
split verdict over an operator's own override, legacy adoption, and the `managedSettingsPath`
binding — is [docs/setup-clean-host.md §1.1](./docs/setup-clean-host.md#11-user-scope-ownership-one-shared-registration-one-recorded-owner).

A development clone runs the bridge source through Node's strip-types path;
an npm-installed package runs the prebuilt JS under `mcp/entwurf-bridge/dist/`
because Node refuses to strip `.ts` files under `node_modules`. The dev launcher's
source path means `./run.sh check-bridge` needs no build. After `git pull`, however,
run `pnpm install` when the lockfile changed and run `pnpm run build-bridge` before
artifact-consuming checks such as `./run.sh check-bridge-delivery`: `dist/` is
gitignored and may be absent or stale immediately after a checkout or pull.

### Pi adapter / ACP plugin lane

To use the `entwurf` provider inside pi, install a compatible pi binary
separately (`@earendil-works/pi-coding-agent >=0.85.1 <0.86`). Then point pi at
the npm-installed package or development clone:

```bash
# global npm install path
pi -e "$(npm root -g)/@junghanacs/entwurf" --list-models entwurf

# project-local install path
pi -e ./node_modules/@junghanacs/entwurf --list-models entwurf
```

For daily operator sessions, launch pi with `--entwurf-control` — no id
injection; the meta-record mints the garden address (see [Garden launcher](#garden-launcher)). Older pi
versions may silently miss the provider/extension surface, so treat the pi floor
as release-critical for the ACP/plugin lane. A host that only uses
`entwurf-bridge` from Claude Code / Copilot / Codex / Antigravity / OMP does not need pi at all for
delivery: no `entwurf_v2` rail launches a pi process. OMP is a pi fork, but it is its own binary and
resolves its own agent directory, so that lineage does not reintroduce a `pi` requirement either. That external-only shape works with the same
`setup` command: pi is optional-by-presence there, so a pi-less host simply gets an explicit pi
SKIP while the detected harnesses are composed.

### Native harness repair and doctors

A plain MCP registration exposes the bridge tools; a **garden-native** session also
needs entwurf's lifecycle hook and identity marker. `setup` already composes all of that
for every harness it detects — you do not paste this list to install. This is the repair
surface: each unit has its own installer, its own doctor with a named refusal, and its own
inverse, so a single broken unit can be redone without touching the rest.

- **Claude Code** (Linux-certified axis) — `install-meta-bridge`, `doctor-meta-bridge`.
- **Antigravity / agy** — `install-agy-bridge`, `install-agy-statusline`, `install-agy-hooks`, each with a matching `doctor-agy-*`.
- **GitHub Copilot CLI** — four independent units, four independent failure modes: `install-copilot-bridge` (birth: garden id + who-sent, on the first prompt), `install-copilot-mcp` (the entwurf tool hand, where `entwurf_inbox_read` lives), `install-copilot-receive` (the receiver extension: doorbell + receiver marker), `install-copilot-statusline` (optional for a manual citizen, required for supported fresh) — each with a matching `doctor-copilot-*` and `uninstall-copilot-*`.
- **OMP (`omp`)** — four units, in-process extensions rather than launchers: `install-omp-bridge` (birth: the `mode === "tui"` visible host, its garden id on the status line, and who-sent), `install-omp-mcp` (the omp-native `entwurf-bridge` entry), `install-omp-config` (the one operator setting `tools: xdev: false`, without which the vendor mounts MCP tools as `xd://` devices the model cannot call), `install-omp-receive` (the receiver extension: mailbox watch + announce-only doorbell) — each with a matching `uninstall-omp-*`, and a `doctor-omp-*` for all but the setting, whose runtime axis `doctor-omp-mcp` owns. The setting writer owns exactly the lines it adds and refuses an explicit operator `tools: xdev: true` by name rather than overwriting it.

Run them as `entwurf <command>`. Which unit a doctor's refusal names, and the clean-host
walk-through for each harness, live in [docs/setup-clean-host.md](./docs/setup-clean-host.md).

#### Launching Copilot as a garden citizen — `entwurf copilot`

Copilot only scans for extensions when its CLI is started with
`COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS`, and when that flag is absent it skips the
scan **silently** — no error, no log line, no receiver. entwurf does not own your shell
and writes nothing to your rc files, so it owns one invocation instead:

```bash
entwurf copilot                 # managed launch, in this terminal
entwurf copilot -p "…" --model gpt-5.4
copilot                         # the plain vendor CLI, untouched
```

`entwurf copilot` execs the vendor CLI in your current terminal — same cwd, same pid,
same exit status, no tmux window and no new citizen (a Copilot session is still born on
its first prompt). Before it launches it verifies that the receiver unit it is about to
promise is actually installed, and refuses with `entwurf install-copilot-receive` if it
is not, rather than starting a session that can never be delivered to.

**Running it is your consent to its profile.** For that one invocation it adds:

| Injected | When |
|---|---|
| `COPILOT_CLI_ENABLED_FEATURE_FLAGS=EXTENSIONS` | always — your other feature-flag tokens are preserved, in order, deduplicated |
| `--model auto` | only when you passed no `--model` |
| `--yolo` | only when you passed no explicit permission or surface policy flag |

The escape hatch is simply to state your own policy: any of `--yolo`, `--allow-all`,
`--allow-all-tools`, `--allow-all-paths`, `--allow-all-urls`, `--allow-tool`,
`--deny-tool`, `--allow-url`, `--deny-url`, `--available-tools` or `--excluded-tools`
suppresses the injected `--yolo`. The narrowing flags are in that list on purpose — adding
`--yolo` beside your `--allow-url=…` would silently widen exactly what you were
restricting. `--allow-all-mcp-server-instructions` (prompt content, not authorization) and
`--autopilot` (a mode) are deliberately not policy flags. Everything you pass is forwarded
byte-identically, injected defaults land before any `--` terminator, and nothing after the
terminator is read as policy. Nothing is written to disk; run plain `copilot` and none of
this applies.

Why `--yolo` is the default: the managed lane exists so a sibling can wake an idle session,
and draining the mailbox with `entwurf_inbox_read` costs two interactive approvals under
the default permission prompts — which an idle, unattended session is not there to answer.

Claude Code uses the supported floor `>=2.1.217`; older versions silently discard the
exec-hook `args`, so install and doctor fail loud rather than falling back. After any
upgrade, rerun `entwurf setup <project>` — it re-composes every detected harness, all four
Copilot units included — and restart its existing processes; reach for a single
`install-*` only when one unit needs repair on its own. A claimed Claude host is certified
only when a **new** session using the
installed artifact makes `doctor-meta-bridge` exit 0 with the live owner join.

Linux is the only currently certified Claude meta-bridge axis. New macOS wiring is
refused because the strict live-owner doctor depends on `/proc`; Darwin uninstall
remains available for legacy cleanup, and the neutral package itself has no `os`
restriction. Detailed diagnosis and clean-host steps live in
[docs/setup-clean-host.md](./docs/setup-clean-host.md).

The active citizen store is V3-only. A store that fails certification is never
silently migrated: quiesce the native sessions, run `entwurf meta-bridge-fresh-cut`,
then reinstall. The cut archives routing records only—never native transcripts or
external memory—and no runtime reads the archive. Exit meanings and the complete
operator contract are in [docs/fresh-cut-policy.md](./docs/fresh-cut-policy.md).

`entwurf check-bridge` proves the MCP surface boots without backend auth. A real ACP
turn requires `LIVE=1 entwurf smoke-acp-provider-live`; the full release protocol and
host evidence boundaries are [VERIFY.md](./VERIFY.md) and [BASELINE.md](./BASELINE.md).

> **Extension set — do not filter.** The ACP provider, `entwurf-control`, and
> `model-lock` extensions ship as one set. Disable the package as a whole rather than
> filtering individual entries into a partially wired state.

### Backend prerequisites

**Claude is the reference ACP backend.** The Claude ACP server package (`@agentclientprotocol/claude-agent-acp`, pinned with `@agentclientprotocol/sdk`) ships as a pinned `dependency` of `entwurf`; backend authentication still belongs to the operator's local `claude` CLI / runtime. Once the bridge is installed, the resolver picks the ACP server in this order:

1. **`CLAUDE_AGENT_ACP_COMMAND` env override** — explicit override for an alternative binary or a wrapper command.
2. **`require.resolve(...)` against the bundled package dependency** (`@agentclientprotocol/claude-agent-acp`). This is the default path; no extra global install needed.
3. **`PATH:claude-agent-acp` fallback** — used when the package resolution fails (e.g. a hand-edited `node_modules`).

The curated model registry exposes unprefixed Claude ids plus `cortex-` rows.
Codex is not an ACP backend or a shipped managed citizen lane: it has verified
native-delivery probe evidence only. No managed Codex support is claimed; lifecycle,
identity, installation, and doctors remain prerequisites for any such lane.

**Snowflake Cortex Code is the second ACP backend** (contract and audit:
[docs/acp-backend-rail.md](./docs/acp-backend-rail.md#cortex-code-audit-d1d10)). Curated ids are
`cortex-auto`, `cortex-claude-opus-5`, `cortex-claude-sonnet-5`, and
`cortex-openai-gpt-5.4`.

The operator supplies an authenticated `cortex` CLI and selects a connection with
`entwurfProvider.cortexConnection` or `ENTWURF_ACP_CORTEX_CONNECTION`. `CORTEX_HOME`
must be absent: the adapter refuses it because it would bypass the session-scoped
HOME containment. Explicit MCP servers are projected into the overlay-private
`cortex/mcp.json`; only the bridge receives the real operator HOME needed for the
garden store.

`check-acp-cortex` runs in `pnpm run check:full`. Real acceptance is deliberately on demand:

```bash
LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> entwurf smoke-acp-cortex-live
```

The aggregate Claude floor does not run this smoke, so silence is not a Cortex PASS.

### Emacs frontends

Works from terminals and from Emacs frontends that launch [pi-coding-agent](https://github.com/dnouri/pi-coding-agent).

<details>
<summary>Watch entwurf in Doom Emacs (1104×627 GIF, click to expand)</summary>

![entwurf in Doom Emacs](docs/assets/entwurf-doomemacs.gif)

</details>

For a dedicated agent socket, pass the socket name:

```elisp
(setq pi-coding-agent-extra-args
      '("--entwurf-control" "--emacs-agent-socket" "pi"))
```

The bridge exports the socket name to ACP children as `PI_EMACS_AGENT_SOCKET`, so skills call Emacs without hardcoding:

```bash
emacsclient -s "${PI_EMACS_AGENT_SOCKET:-server}" --eval '(...)'
```

## Settings

Reference shape lives in [`pi/settings.reference.json`](./pi/settings.reference.json). Minimum:

```json
{
  "compaction": { "enabled": false },
  "entwurfProvider": {
    "appendSystemPrompt": false,
    "settingSources": [],
    "strictMcpConfig": true,
    "showToolNotifications": true,
    "tools": ["Read", "Bash", "Edit", "Write"],
    "skillPlugins": [],
    "permissionAllow": ["Read(*)", "Bash(*)", "Edit(*)", "Write(*)", "mcp__*"],
    "mcpServers": {
      "entwurf-bridge": {
        "command": "/path/to/entwurf/mcp/entwurf-bridge/start.sh",
        "args": []
      }
    }
  }
}
```

`mcpServers` is the only ACP MCP injection path. In practice this repo is about the bundled `entwurf-bridge`, which carries pi capabilities into ACP-backed sessions — not about being a general MCP catalog. Invalid entries throw `McpServerConfigError` — broken tool state surfaces as broken tool state. `./run.sh install` writes the bundled `entwurf-bridge` entry and prunes the legacy bundled `session-bridge` entry from older installs.

`appendSystemPrompt: false` is intentional. Pi / AGENTS context rides the first-user augment; putting it into the Claude `_meta.systemPrompt` carrier can route OAuth sessions to metered "extra usage" billing.

**Which keys reach which backend.** `entwurfProvider` is one block for both backends, but its keys are not universal. `tools` / `permissionAllow` / `disallowedTools` / `settingSources` / `skillPlugins` / `appendSystemPrompt` are Claude's declaration surface: they do not shape a cortex session, which runs its own native tools and reaches MCP through the overlay-private `mcp.json` projection instead. They are not inert, though — the bridge still reads `tools` for its backend-invariant exclude-tools preflight and folds all of them into the config signature, so editing one still forces a fresh cortex session. `cortexConnection` is cortex-only. `mcpServers` is the one declaration surface that reaches both, each through its own transport. (`compaction` is a *top-level* pi key, not an `entwurfProvider` one — it is pi's own transcript policy and is not a backend knob at all; see §Compaction.) Unknown and retired keys are ignored rather than rejected, so a key aimed at the wrong backend fails silently: if a cortex session does not show the surface you configured, check that the key is one cortex actually consumes before suspecting the bridge.

### External MCP registration

`entwurf-bridge` can also be registered in a separate MCP-aware harness (Claude Code,
Copilot CLI, Codex CLI, Antigravity, OMP). Two shapes exist and they are not interchangeable:

- **plain external MCP host** — no garden meta-record or sender marker. It can read the
  surfaces, but `entwurf_v2` is **refused by default**: there is no authoritative sender.
- **garden-native session** — a trusted lifecycle hook minted a garden id, so it is
  addressable and replyable by that id.

```bash
claude mcp add --scope user entwurf-bridge entwurf-bridge
```

Per-harness registration (Claude Code `~/.mcp.json`, Codex `~/.codex/config.toml`, the
managed `install-agy-*` surfaces, and OMP's managed `install-omp-mcp` into `<omp agent dir>/mcp.json`
— whose pinned server key is what shadows a borrowed Claude import, see
[docs/external-mcp-host.md](./docs/external-mcp-host.md) §OMP), the PATH/env boundary for
GUI-launched MCP servers, the
anonymous-sender hatch, and the full external/meta-session semantics are in
[docs/external-mcp-host.md](./docs/external-mcp-host.md).
For the maintained multi-harness setup and skill/command packaging details, see `agent-config`. See also the MCP entry in [Concept primer](#concept-primer), the sender envelope contract in [AGENTS.md](./AGENTS.md), and [Custom skills](#custom-skills) for the in-pi ACP skill surface.

## Per-backend operating surface

The Claude ACP backend keeps its native model / API / tools; entwurf shapes only what enters from pi. Claude honors an explicit `CLAUDE_CONFIG_DIR` export when set by the operator.

**Claude** uses `_meta.systemPrompt` for the engraving carrier (kept short and pure — billing-safe; rich operator context rides the first user message instead, see [Context carriers](#context-carriers)) and `CLAUDE_CONFIG_DIR` for a whitelist overlay so auth/runtime entries stay available while operator memory, hooks, agents, history, local settings, and project memory remain hidden. The overlay writes an explicit empty `hooks: {}` because Claude SDK organic compaction needs the configured-empty shape; no operator hook definitions are inherited. It also pins `permissions.defaultMode: "bypassPermissions"` so an unattended ACP turn cannot suspend on an interactive permission prompt; explicit `tools` / `disallowedTools` still constrain the callable surface and backend authentication remains the operator's. The four-tool baseline is `Read`, `Bash`, `Edit`, and `Write`; `permissionAllow` carries their allow declarations, and `Skill` is added automatically when `skillPlugins` is non-empty. Operator context cap override: `ENTWURF_ACP_CLAUDE_CONTEXT=<int>`.

Codex is not an ACP backend here. Its native delivery probe remains separate from
the governed ACP adapter rail and does not yet constitute a managed garden citizen.

Antigravity is also not an ACP backend. It is a native-push citizen: `PreInvocation` supplies birth/sender identity, `entwurf_v2` probes and direct-injects replies into the live conversation, and no mailbox/receiver marker is involved.

entwurf owns **no** memory layer at all — the ACP plugin's boundary explicitly excludes a memory DB (see `AGENTS.md` §ACP Plugin Boundary), and no backend is a memory authority for another. What this overlay does is narrower: Claude's native memory layer is pinned off so operator memory, project state, and history never leak into an ACP session. Whatever semantic-memory / Denote tooling an operator runs is their own skill surface on whichever harness hosts it — deliberately kept out of the MCP bridge, and not a pi privilege.

## Smoke commands

```bash
pnpm check                              # everyday core (prints wall time; <=60s on the reference host)
pnpm run check:full                     # full deterministic floor (adds the hermetic + package/install tiers)
./run.sh check-bridge                   # entwurf-bridge direct MCP smoke (no backend auth)
./run.sh smoke-agy-install-state        # agy MCP + exact permission ownership lifecycle (install/uninstall/doctor/inverse)
./run.sh smoke-agy-statusline-state     # agy ambient garden-id install surface
./run.sh smoke-agy-hooks-state          # agy PreInvocation birth hook
./run.sh check-agy-sender-identity      # record-backed pid/start-key sender identity

# source-maintainer only — qualification snapshots the git work surface, and both
# commands are source-contract gates rather than installed operator checks:
./run.sh check-agy-permission-matrix    # AGY permission contract space as a literal table (declared cells + stated exclusions)
./run.sh check-gate-manifests           # the qualification HEAD alone: self-test + manifest-set validation + declared lane inventory, zero mutants run (in check:hermetic)
./run.sh check-gate-qualification       # kill-proof: committed defect mutants must turn their gates red for the claimed reason

# agy LIVE acceptance — requires an already-running conversation:
LIVE=1 AGY_CONVERSATION_ID=<id> ./run.sh smoke-agy-native-push-live

# ACP plugin LIVE acceptance — need the operator's local Claude auth/credit:
LIVE=1 ./run.sh smoke-acp-socket-citizen-live   # turn-free socket citizenship (S1)
LIVE=1 ./run.sh smoke-acp-raw-turn-live         # pinned ACP pipe + raw 1 turn (S2a)
LIVE=1 ./run.sh smoke-acp-overlay-live          # config overlay + hooks:{} + tool meta (S2b)
LIVE=1 ./run.sh smoke-acp-provider-live         # real pi provider path + progress/L3 (S2c/S2f)
LIVE=1 ./run.sh smoke-acp-session-reuse-live    # process-scoped reuse + codeword recall (S2d)
LIVE=1 ./run.sh smoke-acp-carrier-augment-live  # augment delivery + empty-carrier billing clean (S2e-1)

LIVE=1 ./run.sh release-gate /tmp/scratch --cut # the single cut gate (MUST + BEHAVIOR; --cut refuses any MUST SKIP)
LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> ./run.sh smoke-acp-cortex-live  # Cortex is on-demand: the aggregate does not re-certify it
```

`pnpm run check:full` includes the AGY permission contract matrix and the qualification
HEAD (`check-gate-manifests` — runner self-test, manifest-set validation, declared lane
inventory, zero mutants executed); the committed-mutant EXECUTION is scheduled separately
(`./run.sh check-gate-qualification` — the CI `check` job runs it on a branch push that touched the qualification surface,
and release-gate carries it as a MUST step; a tag push runs no CI, since the same SHA's
branch run already carries every job). A gate a
release touches must kill its known defect for the claimed `[QK:<claim>]` reason —
the descriptions above name what each smoke covers, and no check count is quality
evidence on its own. Gate qualification needs the git work surface, while the matrix
is the source permission-contract gate; both run from a clone, never as a post-install
operator step.

## Custom skills

Claude sessions accept custom skills through `skillPlugins` — an array of absolute paths to directories matching the Claude Agent SDK plugin layout:

```
<your-plugin-root>/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    └── <skill-name>/
        └── SKILL.md
```

A self-contained example lives at [`pi/skill-plugin-example/`](./pi/skill-plugin-example/). Put plugin roots anywhere on disk except under `~/.pi/agent/` (pi's internal cache).

```json
{
  "entwurfProvider": {
    "skillPlugins": ["/absolute/path/to/your-plugin-root"]
  }
}
```

`Skill` is auto-added to `tools` and `Skill(*)` to `permissionAllow` whenever `skillPlugins` is non-empty. Each entry is validated at settings parse time and throws when the path is missing, not absolute, not a directory, or missing `.claude-plugin/plugin.json`. The Claude session does not start until the violation is fixed. The bridge does not validate `plugin.json` contents or `SKILL.md` bodies — that is the Claude Agent SDK's contract.

To verify, start a fresh Claude session and ask the model to list its skills; the names declared in your `SKILL.md` frontmatter should appear among the visible skills. The operator-driven version of this check is `Q-SKILL-CALLABLE` in [VERIFY.md](./VERIFY.md).

`skillPlugins` is a Claude-backend-only install surface. Codex exposes skills through native `~/.codex/skills/` passthrough.

For a real consumer arranging many skills, see [agent-config](https://github.com/junghan0611/agent-config).

## Entwurf orchestration

**Entwurf is one dispatch capability with native-pi and MCP surfaces.** Native pi exposes it directly as extension tools; ACP-backed and external native-harness sessions reach it through `entwurf-bridge`. The purpose is not to invent a different sub-agent system, but to preserve the same sibling-based model across harnesses.

A sibling has its own runtime boundary and its own provider/model identity — not a worker, delegate, or sub-agent. Today every transport targets an *existing* garden citizen, and none of them starts a process. `entwurf_v2` routes from rail-specific liveness: live pi fire-and-forget → control socket; dormant pi → an honest reject; active self-fetch → meta-mailbox; probe-alive agy → native-push. A **control-socket-domain** dispatch takes the per-target lock, which now serializes concurrent live sends at one garden id; mailbox and native-push use their own deliverability evidence and remain lock-free.

A two-pane recording covers the pre-0.12 v1 surface end-to-end — sibling resume, cross-process MCP dispatch across a different cwd, and a live peer greeting. It is **archived evidence**: it shows a resume verb this repo no longer has (see `demo/README.md`).

<details>
<summary>Watch (2131×1142 GIF, click to expand)</summary>

![entwurf demo](./docs/assets/entwurf-entwurf.gif)

</details>

Live peer messaging carries a sender envelope `{ sessionId, agentId, cwd, timestamp, origin?, replyable? }`; `entwurf_self` returns that authoritative envelope for the current pi session or trusted meta-session. Plain external MCP hosts are non-replyable. A garden-native meta-session carries a trusted `meta-session` envelope, but **`replyable` is a fact its own rail decides, not a consequence of being trusted** — a self-fetch citizen needs a live armed receiver, a native-push citizen needs an alive adapter probe, and a pi session needs its control socket. `entwurf_self` also reports which rail a meta-session reply would ride, because a native-push citizen has no mailbox to name. `wants_reply` is an etiquette marker rendered as a `(wants reply)` badge — not a transport contract, no wait, no polling. **v2 never gates on it:** a `wants_reply` from an external/non-replyable caller is passed through and surfaced honestly beside that sender's `replyable: false`, not rejected — the decider routes on target + intent, never on sender replyability. (The retired v1 `entwurf_send` did reject it; that behaviour went with the verb.)

In ACP-backed and external native-harness sessions, `entwurf-bridge` exposes seven tools: `entwurf_v2`, `entwurf_peers`, `entwurf_fresh_call`, `entwurf_resume_call`, `entwurf_self`, `entwurf_inbox_read`, and the explicit/manual `entwurf_register_native` fallback. Native pi exposes the shared capability directly through the extension surface (`entwurf_v2`, `entwurf_peers`, `entwurf_fresh_call`, `entwurf_resume_call` tools; the socket-scan `/entwurf-sessions` command is gone — #50 C4). **For garden-id delivery/reply use `entwurf_v2`** — the canonical surface that classifies the target and routes to live-pi / self-fetch meta-mailbox (Claude Code, Copilot, OMP) / Antigravity-native-push, and refuses a dormant target instead of waking it. **To open a sibling that does not exist yet use `entwurf_fresh_call`** — it launches one fixed backend (`pi`, `claude-code`, `copilot`, or `omp`) as a visible window in the operator's own tmux session, requires an explicit model, accepts one optional literal absolute `cwd` (omit it or pass `""` to use the caller's cwd), passes the model and selected directory through the runtime's visible launch path, and hands it a first task; a `copilot` launch goes through entwurf's own managed invocation and is refused before any window opens if this host lacks the Copilot birth, MCP, receiver or visible-footer units, and an `omp` launch carries its task in the `--entwurf-bootstrap` payload instead of an argv prompt because that vendor connects its MCP tools after the session has already started. The sibling's first action is a nonce callback whose sender envelope carries its garden id. The launch receipt records the requested model/cwd plus tmux coordinates and never claims that the runtime accepted them or completed delivery. (The v1 verbs `entwurf` / `entwurf_resume` / `entwurf_send` are gone.) Garden-native operator commands require `--entwurf-control`. There is no spawn target allowlist — the target registry is gone (#50 C3): `entwurf_v2` and `entwurf_resume_call` address an existing record-backed citizen, while `entwurf_fresh_call` takes its explicit backend/model/task and optional cwd directly rather than resolving a model tuple from a registry file. **To reopen a DORMANT pi citizen use `entwurf_resume_call {target}`** — the record supplies transcript, model, provider and cwd, so it takes no prompt, no task and no model override; it runs no turn, returns a LAUNCH receipt and a separate OBSERVATION receipt (only the second says the citizen is back), refuses a non-pi target as `target-not-pi`, and on an unobserved socket leaves the visible window open and releases its lock rather than retrying.

### `entwurf_v2` — canonical dispatch verb

`entwurf_v2` / `runEntwurfV2` is the canonical v2 dispatch verb over **existing** garden targets — record-backed citizens only (#50 C4: the record is the sole address authority; a record-less control socket rejects pre-probe as `record-less-socket`, a diagnostic state, never a delivery target). You give a target garden id plus an intent (`fire-and-forget` — the axis is single-valued since the visible-first cut); one decider reads the target's liveness as a fact and picks the transport from a frozen table keyed on **both** the target's state **and** the intent — never on state alone — then reports one outcome under the v2 lock policy. A **control-socket-domain** dispatch takes a per-target lock; mailbox and native-push are lock-free, with deliverability guarded by their own receiver/probe evidence:

| target state | intent | transport |
|---|---|---|
| live pi | fire-and-forget | control-socket send |
| dormant pi | fire-and-forget | **reject** (`dormant-fire-forget-unsupported` — nothing is launched) |
| any pi | indeterminate probe | **reject** (`indeterminate-no-spawn` — an unestablished probe is not a measured death) |
| active self-fetch receiver | fire-and-forget | meta-mailbox enqueue + doorbell |
| inactive / terminated self-fetch receiver | fire-and-forget | **reject** (`mailbox-undeliverable` — no `.msg`, no doorbell) |
| live native-push conversation | fire-and-forget | native-push direct injection |
| dead / indeterminate native-push conversation | fire-and-forget | **reject** (`native-push-target-dead` / `native-push-probe-indeterminate`) |
| record-less control socket (no meta-record) | any | **reject** (`record-less-socket` — pre-probe; diagnostic state, #50 C4) |

**`entwurf_v2` is the canonical surface for garden-id delivery.** When you have a garden id and want to reach whoever it names — message, reply, or hand-off — `entwurf_v2` is the one surface that reads whether the target is live pi, dormant pi, mailbox-backed Claude Code, Copilot or OMP, or native-push Antigravity and routes correctly; *when unsure which transport, use `entwurf_v2`*. This prevents callers from guessing a rail from the shape of an id.

What v2 provides is a **deterministic dispatch substrate** that moves the "which transport?" decision out of the fallible caller/model and into the decider, with transport-appropriate locking and an honest reject (no `✓ delivered`, no `.msg` garbage) when a target cannot receive. It still does **not** mint siblings, and it does not relaunch one either: every row above either reaches a citizen that is already running or refuses. Reopening a dormant pi citizen is `entwurf_resume_call`, a separate lifecycle verb that never routes through this decider. Fresh creation is the separate `entwurf_fresh_call` verb. It opens one fixed Pi, Claude Code, Copilot or OMP runtime visibly in the caller's tmux session with a required explicit model passed in that runtime's measured CLI dialect and one optional literal absolute `cwd`; omitted or `""` means the caller's cwd. Copilot opens through `entwurf copilot`, never the bare vendor; OMP is the opposite — the bare `omp` runtime with no positional prompt at all, because that vendor connects its MCP tools after the session has started, so the task rides a two-stage `--entwurf-bootstrap` payload the installed birth extension releases once the callback tool has actually answered. It returns only a synchronous launch receipt and lets the sibling report its new address asynchronously through the sender envelope of a nonce callback. Use this cwd input for a new cross-repository sibling; do not resume a dormant citizen as a cwd substitute. The meta-mailbox row requires an **active** self-fetch receiver; native-push requires a record-backed, probe-alive native conversation and never borrows mailbox state. The [mux launch lane](./docs/mux-launch-rail.md) owns placement, fixed-runtime launch, and the two narrow compositions above it (fresh-call and resume-call placement); delivery does not import launch, and mux is not a delivery transport.

A live pi target is *reached* over its control socket, but the socket is dispatch-internal transport, never identity (#50 C4). A control socket that no meta-record claims — a pre-record-era resident, an unreadable store, or a stale/planted file — is refused for **every** intent as `record-less-socket`, and the reject names the fix (restart the resident so `session_start` births its record, or quiesce and run the fresh-cut). `entwurf_peers` reports the same state as an aggregated `record-less-socket` diagnostic rather than a peer row.

> **Direction.** An Entwurf core (peer identity / garden id / inbox / liveness / dispatch / replyability / evidence) could later extract into its own repo with per-backend plugins; today this repo holds the v2 core + meta-bridge + ACP plugin together. ACP is one plugin, not the boundary — rationale: [#38](https://github.com/junghan0611/entwurf/issues/38).

### Garden launcher

A `--entwurf-control` session needs **no special launcher** (#50 C2): pi mints its own session id (a `uuidv7` is normal), and `session_start` attaches the session to its meta-record — the record mints the garden id, keys the control socket on it, and `PI_SESSION_ID` carries that garden address to every MCP child. The old `--session-id "$(run.sh new-session-id)"` injection contract (and the header-id guard it fed) is gone; `run.sh new-session-id` survives only as the garden-id generator the record layer itself uses. Launch is simply:

```bash
pi --entwurf-control
```

**Resuming an existing garden session.** Use `entwurf_resume_call {target}`. It reopens a DORMANT pi citizen under the SAME garden id in a visible window in the caller's own tmux session, resolving the transcript, model, provider and cwd from the record — so it takes only the target id, and it runs no turn: the window comes back with the conversation and waits, and talking to it is still `entwurf_v2`. Two receipts arrive and mean different things: a LAUNCH receipt (tmux made a window and was asked to start pi) and an OBSERVATION receipt (the control socket answered under the same id, or `resume-unobserved`). Unobserved is a real outcome, not an error to retry — the window is visible, so read it. A citizen that is already live is refused; so is a non-pi target (`target-not-pi`), because only pi stands a control socket up. The predecessor, `entwurf_v2 intent=owned-outcome`, resumed by launching a hidden window-less background child and was withdrawn under the visible-first rule; delivery still starts no process. Identity preconditions live in `resume-launch-identity.ts`, gated by `check-resume-launch-identity`.

**Starting a new session in-process — pi's own `/new`.** Since the #50 C2 cut there is nothing to replace it with: `/new`, `/fork`, `/clone` and RPC session replacement are pi's again. The replacement session fires `session_start`, which upserts its own meta-record and rebinds the control socket to that record's garden id; the old socket is dropped. pi's session id (a uuidv7) is recorded as the citizen's `nativeSessionId` and is never an address. Gate: `run.sh smoke-resident-garden-guard` REPLACEMENT section (0-token RPC E2E).

## Context carriers

System / developer carriers and rich pi context are separate.

The carrier holds an optional short operator engraving; empty or missing is fine. The runtime default is the bundled `pi-extensions/lib/acp/prompts/engraving.md` (the `# Engraving Here` placeholder, pinned non-empty by a gate); [`prompts/engraving.md`](./prompts/engraving.md) is a documented sample you copy and point the runtime at with `ENTWURF_ACP_ENGRAVING_PATH=/path/to/alt.md`. Template variables: `{{backend}}`, `{{mcp_servers}}`. Do not put AGENTS.md, bridge narrative, or tool catalogs here — large Claude carriers can route OAuth sessions to metered "extra usage" billing.

Your file's own leading and trailing whitespace is trimmed, and the loader then opens the carrier with one blank line. That boundary is not cosmetic: the Claude Agent SDK prefixes its own fixed identity sentence and concatenates the carrier onto it with nothing in between, so without it the engraving's first line reads as the tail of the SDK's sentence (measured 2026-07-31 as `You are a Claude agent, built on Anthropic's Claude Agent SDK.# Engraving Here`). Do not try to supply the boundary from inside the markdown — it is trimmed away before it reaches the wire.

Bridge identity, pi context, `~/AGENTS.md`, `cwd/AGENTS.md`, and date/cwd ride a one-shot first-user prepend (`pi-context-augment.ts`). Entwurf prompts already carry `cwd/AGENTS.md` inside `<project-context ...>`; the augment removes that duplicate. The augment describes capabilities, but the **actual callable schema remains source of truth** — `read` vs `Read` vs `exec_command`, MCP only when schema-visible.

## Compaction policy

**entwurf does not implement compaction.** When a backend compacts natively, the pi session and mapping survive that. The bridge exposes no backend-specific compaction knobs; operators who need to alter a backend's auto-compaction configure that backend through its own native interface. Do not rely on a pi-side JSONL summary to reduce a backend transcript — it does not.

The footer uses ACP `usage_update.used / size` (backend prompt/tools/cache/session included) with `[entwurf:usage]` diagnostics. Near limit, choose a visible action: clear, open a new session with a different model, or let the backend compact on its own.

## What this repo owns, and does not

Owns: provider registration (`entwurf/...`), ACP subprocess lifecycle + `resume > load > new`, prompt forwarding + ACP event mapping, the bridge surface that exposes pi capabilities such as entwurf to ACP-backed sessions, pi-facing MCP injection via `entwurfProvider.mcpServers`, and bridge-local cleanup and diagnostics.

Does not: reconstruct full history, hydrate backend transcripts into pi history, emulate Claude Code or Codex, run broad multi-agent orchestration (entwurf is narrow, record-addressed, identity-locked), or run a second session model competing with pi.

Only `pi:<sessionId>` mappings are persisted (`~/.pi/agent/cache/entwurf/sessions/`) — enough to re-attach pi to the same remote ACP session, never enough to act as a second harness. Backend stores (`~/.claude/`, `~/.codex/`) are interoperability side effects, not authority.

This repo also doubles as the maintainer's working laboratory for agent-harness boundaries — new workflow patterns (e.g. Mitsein over MCP) land here first as low-level instruments, before crystallizing into invariants or graduating into more polished surfaces elsewhere.

## Verification surfaces

- **[VERIFY.md](./VERIFY.md)** — agent-driven. One ACP-bridged identity runs the script against another and records what it sees. Carries the Evidence Levels L0–L5 rung ladder and the Claims Ledger so each claim is parked at the rung it has actually reached, and owns the deterministic-floor kill-proof protocol (gate qualification and its `[QK:<claim>]` coordinates).
- **[BASELINE.md](./BASELINE.md)** — operator-driven. The maintainer runs the interview directly (no agent in the verifier seat) and the result is recorded.
- **[DELIVERY.md](./DELIVERY.md)** — capability-coordinate. The cross-harness yardstick for one question: can an already-running native session receive an async message without pretending pi owns the backend transcript? Records the per-backend async-delivery level (`D0–D8`) each harness actually reaches instead of collapsing into works/doesn't.

VERIFY + BASELINE are the verification pair — use both; either one alone leaves a blind spot the other closes. DELIVERY sits on the orthogonal delivery-capability axis.

## References

- File map + code-level invariants: [AGENTS.md](./AGENTS.md)
- Current priority + open decisions: [NEXT.md](https://github.com/junghan0611/entwurf/blob/main/NEXT.md)
- Release record: [CHANGELOG.md](./CHANGELOG.md)
- [xenodium/agent-shell](https://github.com/xenodium/agent-shell) — Emacs ACP client, `resume > load > new` idea origin
- [agentclientprotocol/claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp) — canonical ACP server for Claude Code
- [agent-config](https://github.com/junghan0611/agent-config) — real consumer repo

## License

MIT
