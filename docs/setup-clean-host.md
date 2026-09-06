# Clean-host setup

Current operator recipe for a fresh Linux desktop/workstation. The neutral npm
package can install elsewhere, but Claude's garden-native meta-bridge is certified
only on Linux because its strict live-owner join uses `/proc`.

## Requirements

| Component | Requirement | Needed for |
|---|---|---|
| Node | **`>=24.0.0`** | package and bridge runtime |
| npm/pnpm | npm is bundled with Node; pnpm is required for source setup | package or source installation |
| Python 3 | required by `setup`/`install` (project-path normalization + settings writers); `--help`/`check-bridge` stay Python-free | pi/Claude/agy/Copilot wiring writers |
| entwurf | global/project-local `@junghanacs/entwurf`, or a source checkout | operator command and garden capability |
| pi | optional-by-presence, `>=0.85.1 <0.86` — absent is an explicit setup SKIP, below-floor is a named FAIL | ACP provider, control sockets |
| Claude Code | optional, **`>=2.1.217`** — the exec-form hook floor | Claude ACP auth/runtime and mailbox-backed native citizen |
| GitHub Copilot CLI | optional-by-presence, operator-installed and authenticated — absent is an explicit setup SKIP; detected composes all four units (birth/MCP/receiver/footer) | self-fetch citizen and visible fresh |
| OMP (`omp`) | optional-by-presence, operator-installed — absent is an explicit setup SKIP; detected composes all four units (birth/MCP/`tools.xdev` setting/receiver) | self-fetch citizen and visible fresh (accepted on one host — see §4b) |
| Antigravity `agy` | optional, operator-installed and authenticated | native-push citizen |
| Cortex Code | optional, operator-installed and authenticated | Cortex ACP backend |

Claude Code >=2.1.217 is required for the managed exec-hook lifecycle. The package
never supplies or proxies backend credentials.

## 1. Install Node and entwurf

Use the host's normal Node 24 installation. With nvm:

```bash
nvm install 24
nvm use 24
node --version
npm --version
```

Global install is simplest when native harnesses should find stable bins from every
working directory:

```bash
npm install -g @junghanacs/entwurf
entwurf --help
entwurf check-bridge
```

A project-local installation is also supported:

```bash
mkdir -p ~/entwurf-smoke && cd ~/entwurf-smoke
npm init -y
npm install --save-dev @junghanacs/entwurf
npx entwurf check-bridge
```

`check-bridge` is auth-free. It proves the installed prebuilt MCP server boots and
lists the seven garden tools; it does not prove a backend model turn or native hook.

Neither npm form installs a harness runtime. `pi`, Claude Code, Copilot CLI, agy, Cortex and their
authentication remain operator-owned optional prerequisites for the integrations that use them;
all may be absent on an Entwurf-only host. A source checkout's pinned Pi development packages are
for building and testing this repo, not a transitive product installation promise.

Maintainers using a source checkout do not install a second global entwurf package. Full source
setup currently requires Node 24, pnpm, and Python 3 on PATH; every harness — including pi — is
optional-by-presence (absent → explicit SKIP, detected but below the supported floor → named FAIL
with a nonzero setup result):

```bash
git clone https://github.com/junghan0611/entwurf ~/repos/gh/entwurf
cd ~/repos/gh/entwurf
./run.sh setup /path/to/consumer-project
```

This owns `~/.local/bin/entwurf` as a symlink to that checkout's `run.sh` and fails if the
link is foreign, outside PATH, or shadowed by another command. It detects and wires
pi/Claude/agy/Copilot/OMP by presence and prints a computed per-component PASS/SKIP/FAIL summary — a
detected harness that cannot be completed makes setup exit nonzero. A detected `copilot`
composes all four native units (birth → MCP → receiver → visible footer) with independent
per-unit verdicts (#86 C3b), and a detected `omp` composes its own four (birth → MCP →
`tools.xdev` setting → receiver) the same way; §4 and §4b keep the explicit per-unit
install/doctor/inverse surfaces for repair.

### 1.1 User-scope ownership (one shared registration, one recorded owner)

The GLOBAL pi user-scope registration (`~/.pi/agent/settings.json` `packages[]` plus the
`entwurfProvider.mcpServers.entwurf-bridge` key) is ONE shared entry across every install root, and
it carries a recorded owner: `packageRoot` in `$XDG_DATA_HOME/entwurf/pi-package/install-state.json`
and `installerRoot` in the provider install-state. Normal `install`/`setup` from a different root —
whether the recorded owner is live or missing — refuses with zero settings bytes written; the only
writer that moves the shared entry is the operator-explicit `entwurf takeover-user-scope`
(old→new reported). Every user-scope operation is ATOMIC across the two halves: both ownership
preflights run read-only first, so a refusal on either side leaves the other byte-identical. A
takeover over an operator's own provider override is a SPLIT verdict — the package owner moves,
the override is preserved and stays unowned (its stale ownership state is cleared), never a false
"both owned". A LEGACY provider state (no `installerRoot`) accepts no inverse: run `setup`/`install`
from the owning root first (named adoption), then remove. Both install-states also bind the exact
settings file they manage (`managedSettingsPath`): pointing an operation at a different, symlinked
or unparseable file refuses with zero writes before either half proceeds, and the owned/orphan
inverse removes only the recorded owner's exact `packages[]` entry (0 or 2+ exact entries refuse).
`entwurf doctor-pi-package` names the package-side verdict including the
packageRoot↔installerRoot coupling mismatch and a package/provider managed-path mismatch.

| Root shape | Package root written | Stable commands from | Project write | User write | Takeover trigger | Inverse | Stale/moved verdict |
|---|---|---|---|---|---|---|---|
| source checkout | the checkout dir | `dev-bin` symlinks (`setup`) | `<project>/.pi/settings.json` | shared entry + owner state | `takeover-user-scope` from the new checkout | `remove` (project) / `remove-user-scope` (global, same-owner-only) | `doctor-pi-package` → `missing-owner`; normal install still refuses |
| global npm (`npm i -g`) | the global `node_modules/@junghanacs/entwurf` | npm bin linking | same | same shared entry | same explicit action | same; a LIVE foreign owner always refuses | same |
| project-local npm | that project's `node_modules/@junghanacs/entwurf` | `node_modules/.bin` | same | same shared entry | same explicit action | same | same; a deleted root becomes the aligned `remove-user-scope` orphan cleanup (entry + package state + provider installerRoot must all name that missing root) |

## 2. Optional pi adapter / ACP plugin

Install the exact release floor, then wire the project:

```bash
npm install -g @earendil-works/pi-coding-agent@0.85.1
pi --version

cd ~/entwurf-smoke
entwurf install .
pi -e "$(npm root -g)/@junghanacs/entwurf" --list-models entwurf
```

The supported range is `>=0.85.1 <0.86`. It is a hard minimum: installing this
release onto a 0.83.x pi host upgrades the runtime rather than keeping the older
minor. A host using only the external MCP bridge can skip pi until it needs a
control socket; no delivery rail launches a pi process.

For daily garden-native pi sessions:

```bash
cd ~/entwurf-smoke
pi -e "$(npm root -g)/@junghanacs/entwurf" --entwurf-control
```

The V3 record births the garden id; do not inject a pi session id manually.

## 3. Optional Claude Code native citizen

First register the MCP bridge if the stable bin is not already present:

```bash
claude mcp add --scope user entwurf-bridge entwurf-bridge
```

Then install and certify the mailbox/self-fetch lifecycle:

```bash
entwurf install-meta-bridge
# restart every already-open Claude Code process
# open a new Claude Code session
entwurf doctor-meta-bridge
```

The supported floor `>=2.1.217` is enforced by package metadata through installer
and doctor gates. Older Claude versions validate an exec-form hook but silently drop
its `args` at runtime, so there is no shell-form fallback.

A doctor PASS requires both ownership and runtime evidence, including a live
MCP↔sender↔receiver owner join. `NOT CERTIFIED` exits nonzero: a fixture, plugin
validation, or hand-inspected marker cannot replace a new real session. If the launch
form is unsupported, reinstall; if ownership is correct but the live join is absent,
restart the affected session.

New macOS wiring is refused because the live join is not instrumented there. Darwin
uninstall remains available for cleaning an older managed install; this is an evidence
boundary, not a permanent impossibility claim.

## 4. Optional GitHub Copilot CLI native citizen

Copilot has four independently owned surfaces. `setup` composes all four when `copilot` is on
PATH (#86 C3b); the commands below are the per-unit repair, doctor, and inverse surfaces. All
four must be green for supported visible fresh; a manual citizen may omit the footer, but fresh
refuses before opening a window when any required surface is absent.

```bash
entwurf install-copilot-bridge
entwurf install-copilot-mcp
entwurf install-copilot-receive
entwurf install-copilot-statusline

entwurf doctor-copilot-bridge
entwurf doctor-copilot-mcp
entwurf doctor-copilot-receive
entwurf doctor-copilot-statusline
```

Launch the supported invocation with `entwurf copilot`, not bare `copilot`. It enables extension
scanning for that process, checks the receiver, removes inherited pi identity carriers, and owns
the model/permission defaults. Birth occurs on the first prompt. `entwurf_fresh_call` uses this
same managed invocation and requires the birth, MCP, receiver, and visible-identity preflight.

## 4b. Optional OMP (`omp`) native citizen — accepted on one host

Three independently owned surfaces, and a boundary that is part of the instructions rather
than a footnote. Birth, visible identity, who-sent, the MCP hand and RECEIVE are landed, and
`entwurf_fresh_call` opens an omp sibling on all three public surfaces. The clause 7 LIVE
receipt has been taken: `smoke-omp-fresh-live` went green on 2026-08-30 (omp 18.0.0, one
model, one accepted run), which is what `docs/adding-a-harness.md` step 9 asks for and why
that smoke is wired as a release-gate MUST — the label was never allowed to move ahead of the
evidence, and it moved only once the evidence existed. Read the receipt itself in DELIVERY.md's
OMP row; what it does NOT establish is multi-host, multi-model, or repeated fresh calls in one
process. Open omp yourself and it is a two-way citizen either way — it sends under its own
garden id and a reply lands on it.

The first turn of a fresh omp sibling is a TWO-STAGE BOOTSTRAP, not a positional prompt: the
launcher carries `{v,target,nonce,task}` on the fixed registered flag `--entwurf-bootstrap`,
and the installed birth extension waits until the callback tool is actually callable, sends a
callback-only prompt, and delivers the operator's task only after that exact call succeeds.
That is a measured correction — the interactive host defers MCP discovery, so a positional
first turn began before the tool it named existed.

**One operator setting is load-bearing for fresh, not just for receive.** `tools: xdev: false`
in the omp agent config is checked by the fresh preflight BEFORE any window opens, because the
vendor default mounts MCP tools as `xd://` devices whose schemas never reach the prompt: a
sibling launched onto a default-config host would start, look healthy, and be unable to call
the callback tool at all. A refusal there names `omp-callback-tool-uncallable` and opens
nothing.

`setup` composes all four omp units when `omp` is on PATH, and the setting is one of them —
`entwurf setup` writes `tools: xdev: false` itself. The verbs below are the REPAIR path, not
the install:

```bash
entwurf install-omp-bridge     # the birth extension, into <omp agent dir>/extensions/
entwurf install-omp-mcp        # the omp-native entwurf-bridge server
entwurf install-omp-config     # the operator setting: tools.xdev: false
entwurf install-omp-receive    # the receiver extension: mailbox watch + doorbell

entwurf doctor-omp-bridge
entwurf doctor-omp-mcp         # also owns the tools.xdev runtime axis
entwurf doctor-omp-receive
```

The setting writer owns exactly the lines it adds and records them, so `uninstall-omp-config`
takes back its own bytes and nothing else. It refuses a symlinked config, a config it cannot
parse, and — deliberately — an EXPLICIT `tools: xdev: true`: that is your decision, not drift,
so setup names it as a component FAIL for you to resolve instead of overwriting it.

Order matters only in one direction: the receiver JOINS the citizen birth mints, and
announces a tool the MCP hand provides. Install it without them and it will log
`arm-deferred`, give up after ~20s, and `doctor-omp-receive` will name the missing sibling
as a note rather than a fault.

### The OMP version rule — a weak floor, deliberately (#91)

**entwurf sets no OMP version floor in code, and will not grow one on schedule.** Detection is
presence-only (`command -v "${OMP_BIN:-omp}"`); there is no `entwurf.ompFloor`, no coherence
gate, and no exact pin — unlike Node (`engines.node`), pi (`>=0.85.1 <0.86`) and Claude Code
(`entwurf.claudeCodeFloor`), each of which has an enforcement point. That asymmetry is a
decision, not an omission. A floor is the answer to a vendor that fails SILENTLY — Claude Code
earned one because an older binary validates the exec manifest, drops `args` at runtime, and
reports success. OMP has never been observed to fail that way, it publishes at close to a
daily cadence, and when its contact surface breaks the two LIVE smokes go loudly red.

What stands instead is a **weak floor: the last version with a LIVE receipt.**

> **OMP minimum: `18.1.10`** — `[측정 2026-09-04, thinkpad, Linux x86-64, omp/18.1.10]`
> `smoke-omp-receive-live` 11 assertions ok (garden `20260904T224103-d36fed`) and
> `smoke-omp-fresh-live` 21 assertions ok (garden `20260904T224132-351877`, model
> `openai-codex/gpt-5.6-sol`), with `doctor-omp-receive` PASS and `doctor-omp-mcp` ok. That
> update skipped one minor and ten patches from 18.0.0 and broke nothing.
>
> **This number moves only when a NEW LIVE receipt exists** — never on a release cadence, a
> changelog read, or a static gate. Run newer OMP freely; the floor records what was proven,
> not what is permitted.
>
> **The drift sentinels are `smoke-omp-fresh-live` and `smoke-omp-receive-live`**, both
> release-gate MUST steps. Green after an update means keep going. Red means open a NEW issue
> carrying the first vendor contact point that broke and its reproduction receipt — do not
> reopen the closed adoption question. If a SILENT failure is ever observed (green smokes over
> a dead contact point), that is the evidence a real floor needs, and it earns its own issue
> for the same reason Claude Code's floor exists.

The evidence and the reasoning are in **#91**; this paragraph is its durable form.

**The receiver arms per session, and only for the visible TUI host.** Opening omp arms it;
`/new` re-arms it for the replacement citizen and retires the previous one; closing omp
retires it. A task subagent arms nothing. While nothing is armed, dispatch to that garden
id is the honest `mailbox-undeliverable` refusal — an unarmed receiver is a legible state,
not a broken one.

`[측정]` This section used to end by saying `setup` did not compose these and the verbs had to
be run by hand. That is what v0.16.0 actually shipped, and on an operator host it printed a
green `setup` summary with OMP entirely absent — no extension, no MCP entry, no visible garden
id. The composition landed afterwards; `docs/adding-a-harness.md` step 10 is the rule that
keeps the next harness from repeating it.

Both installers resolve the omp agent directory the way omp itself does, and REFUSE rather
than guess when an inherited `PI_CODING_AGENT_DIR`, `PI_CONFIG_DIR` or `PI_PROFILE` makes it
ambiguous: omp is a pi fork and reads pi's env vocabulary, so those names no longer say which
harness they address. Pass `ENTWURF_OMP_AGENT_DIR` if you genuinely mean a non-default one.

Two things the installers deliberately will NOT do. They never adopt an artifact already
sitting at their path without entwurf's own ownership state — a directory that merely looks
like our unit could be yours, and adopting it would overwrite it with no way back — so a
no-state path is a named refusal you resolve by hand. And the MCP writer's target is exactly
`<resolved omp agent dir>/mcp.json`; there is no path override, so it can never be aimed at
another tool's config.

**Where an omp citizen's garden artifacts live.** Under `$HOME/.pi/agent/meta-*`, the same
garden every other citizen uses — and that stays true under `omp --profile work`. omp is a pi
fork, so the vendor exports `PI_CODING_AGENT_DIR` for every named profile; for entwurf that
name means pi's persistence root, so honouring it here would put an omp session's record in a
different store (or in a pi sandbox). For backend omp it is read as the VENDOR's agent dir
only, and never as a garden root. Its presence on a live omp is normal and is not a fault.
The four `ENTWURF_META_*` variables remain the way to relocate the garden roots, and for
backend omp each one must be **absolute or `~`-rooted** (`~` or `~/…`). A relative value is
refused by name rather than resolved: it would resolve against each process's own working
directory, and the omp extension and `doctor-omp-bridge` do not share one — the doctor would
then report on a directory the extension never writes to. A refused value mints nothing and
turns the doctor's runtime axis red.

**One vendor setting is required, and the default is wrong for a citizen.** omp's
`tools.xdev` (default ON) mounts MCP tools as `xd://<tool>` devices and removes them from the
model's top-level toolset, so `entwurf_v2` is reached by WRITING JSON to a virtual file rather
than by calling a tool — and with `tools.xdevDocs` at its `builtins` default its schema is not
in the prompt at all. On that default a plain "send this to garden id X" was measured to list
peers and then CLAIM the send without ever dispatching. Put this in `~/.omp/agent/config.yml`
and restart the session:

```yaml
tools:
  xdev: false
```

It disables nothing — it exposes every enabled tool top-level, omp's own `lsp`, `debug`,
`browser` and `ast_edit` included, which the default was hiding as well. Plan mode and staged
`xd://resolve` / `xd://propose` finalization keep working. The rationale, the numbers and the
narrower `tools.xdevInlineDevices` alternative are in
[`external-mcp-host.md`](./external-mcp-host.md).

Birth happens when the TUI OPENS (not on the first prompt, unlike Copilot), and the garden id
appears on omp's status line as `🪛 <garden-id> omp`. `/new`, fork and in-TUI resume mint the
replacement session's own record. Task subagents of that session are refused by design — they
borrow the host's tools under the host's garden id and never get a second address.

The MCP entry deliberately uses the same server key as any Claude Code import so that it
SHADOWS it; see [`external-mcp-host.md`](./external-mcp-host.md) for why that key is pinned and
why `disabledServers` is never the way to hide an import.

## 5. Optional Antigravity native citizen

Install the three independently owned surfaces:

```bash
entwurf install-agy-bridge
entwurf install-agy-statusline
entwurf install-agy-hooks

entwurf doctor-agy-bridge
entwurf doctor-agy-statusline
entwurf doctor-agy-hooks
```

The bridge owns one MCP server and narrow rules for the normal tools; the statusline
owns its subtree; the hook owns one `PreInvocation` entry. Unrelated settings are
preserved. A fresh conversation initially may show `🪛 ? agy`; the first invocation
births the record by native `conversationId`, after which the garden id appears.

Real native-push acceptance needs an already-running conversation:

```bash
LIVE=1 AGY_CONVERSATION_ID=<id> entwurf smoke-agy-native-push-live
```

## 6. Optional ACP backend turns

Claude uses the operator's existing local Claude authentication:

```bash
LIVE=1 entwurf smoke-acp-provider-live
```

Cortex requires an authenticated `cortex` CLI and an explicit connection. Keep
`CORTEX_HOME` unset; the adapter refuses its presence because it bypasses containment.

```bash
LIVE=1 ENTWURF_ACP_CORTEX_CONNECTION=<conn> \
  entwurf smoke-acp-cortex-live
```

The aggregate release gate is Claude-backed and does not run Cortex automatically.
Its silence is not a Cortex PASS.

## 7. Upgrade and repair

After upgrading the package, rerun the managed installers for every native harness
in use and restart their existing processes. Native plugin caches are not live-reload
safe across launch-contract changes.

If install or doctor reports an unreadable/old active citizen generation, do not edit
records by hand. Close pi, Claude, Copilot, and agy sessions first, run
`entwurf meta-bridge-fresh-cut`, and read its exit status before any install. Then choose the
installation mode you actually own:

```bash
# npm package consumer
entwurf install ~/entwurf-smoke
entwurf install-meta-bridge
# `entwurf setup` re-composes the four Copilot units when `copilot` is on PATH

# source maintainer — from the checkout
./run.sh setup ~/entwurf-smoke
```

The package-installed `entwurf setup` is the same consumer command in installed mode: it names
that mode first, never runs npm/pnpm inside `node_modules` (the frozen pnpm bootstrap is
source-checkout-only), and composes the detected harnesses with the same per-component
PASS/SKIP/FAIL summary. The complete quiescence, archive, and exit-code contract is
[fresh-cut-policy.md](./fresh-cut-policy.md).

## 8. Release acceptance versus host acceptance

- `entwurf check-bridge`: installed MCP bytes boot; no backend auth.
- `pnpm check` / `pnpm run check:full`: tiered source deterministic floors (everyday
  core / full candidate floor); maintainer checkout only.
- `check-install-container`: checkout-invisible Linux package-consumer shape using
  fixtures; not a native lifecycle proof.
- `doctor-meta-bridge`: one installed real Claude host, only with a new live session.
- `LIVE=1 entwurf release-gate /path/to/scratch --cut`: aggregate runtime acceptance (`--cut` makes any MUST SKIP red; without it the run is a diagnostic pass).

Keep these verdicts separate. Current protocol is [VERIFY.md](../VERIFY.md); recorded
host verdicts are [BASELINE.md](../BASELINE.md).

## Uninstall

Run only the surfaces this host owns:

```bash
entwurf uninstall-meta-bridge
entwurf uninstall-copilot-statusline
entwurf uninstall-copilot-receive
entwurf uninstall-copilot-mcp
entwurf uninstall-copilot-bridge
entwurf uninstall-agy-hooks
entwurf uninstall-agy-statusline
entwurf uninstall-agy-bridge
entwurf remove ~/entwurf-smoke
# only when no other project uses the shared user-scope pi registration:
entwurf remove-user-scope
npm uninstall -g @junghanacs/entwurf
```

The package `uninstall-*`/`remove` surfaces preserve unrelated native-harness configuration.
Copilot birth now has a package-owned inverse: `uninstall-copilot-bridge` removes exactly what
its install-state (`$XDG_DATA_HOME/entwurf/copilot-bridge/install-state.json`) records — the
qualified plugin, the local marketplace registration when it is owned and still at the recorded
path, and the recorded assembly — never with `--force`, never a bare plugin name that could
match somebody else's unit, and never the stale Claude unit. The complete ownership preflight
runs read-only before the first vendor write, so a marketplace under our name at another path,
a registration the state does not own, or a failing vendor list (UNKNOWN, never absence)
refuses the whole inverse with zero writes; the state is deleted last, so a partial failure
keeps a rerun-repair authority.
A legacy no-state installation is adopted by re-running `install-copilot-bridge` first.
