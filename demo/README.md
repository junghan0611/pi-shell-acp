# entwurf recorded demos

> **Archived pre-0.12 evidence.** These scripts still describe the retired v1 `entwurf` / `entwurf_resume` / `entwurf_send` demo flow. They are kept for historical comparison and will be replaced by a v2-native retake in a post-0.12 follow-up; do not treat them as the current 0.12 runnable recipe.

> **Model ids here are archived, not recommended (2026-08-20).** The `entwurf/gpt-5.4` rows below record what these GIFs actually ran on. They are stale twice over: `entwurf/gpt-5.4` is no longer a curated `entwurf` ACP id at all — that provider serves only the `claude-*` and `cortex-*` rows in `pi-extensions/lib/acp/models.ts` — and the live-spend default has since moved to `openai-codex/gpt-5.6-luna` under a cheaper plan. Read them as a record of the recording, never as a default to copy; the current defaults live in `VERIFY.md` and `NEXT.md`.

Two recorded GIF scripts live here. Both use `asciinema` for capture and
`agg` for cast → GIF conversion. Both share the same gitignore policy
(`*.cast` global, `demo/*.gif`, `demo/*.log` — only the `.sh` and this
README are tracked).

## `demo-baseline.sh` — single-pane baseline + entwurf surface

Historical pre-0.12 demo, still linked from the top-level `README.md` as archived evidence. `package.json#pi.image` now points at the `entwurf` release hero instead. Two scenes driven into one pi pane:

1. **Baseline self-awareness** — the `Q-B0` + `Q-B0-CARRIER` interview,
   English answer enforced. The pane exposes how the running model
   names its harness, distinguishes native tools from MCP / custom
   tools, names the carrier surface for each cited piece of
   information, and admits unknowns instead of fabricating.
2. **Entwurf surface** — the same pane spawns a sibling via the
   `entwurf` tool (`mode=sync`, cross-model — driver `claude-sonnet-5`,
   sibling `gpt-5.4`), prints the Session ID, and quotes the sibling's
   one-line reply verbatim.

Run from the repo root (or `demo/`):

```bash
bash demo/demo-baseline.sh
```

Output lands directly in the publish surface — re-running the script
overwrites the previous take so the gallery preview always matches the
current branch:

- `docs/assets/entwurf-demo.cast` — raw asciinema recording (gitignored)
- `docs/assets/entwurf-demo.gif` — tracked, referenced by the top-level `README.md` as archived pre-0.12 evidence
- `demo/baseline-debug.log` — `ENTWURF_DEBUG=1` stderr (gitignored, stays next to the script)

## `demo.sh` — two-pane entwurf flow (regression guard)

Three-scene entwurf flow used for regression evidence, not for the
public README. Two pi sessions run side-by-side in one tmux window;
a background driver types the scene prompts into the sender pane.

1. **Spawn** a sonnet sibling (memory write — "tempered indigo").
2. **Resume** that same sibling (memory recall — identity preservation,
   the #9 regression guard).
3. **Cross-session greeting** via `entwurf_send` (sent box ↔ received box).

Run:

```bash
bash demo/demo.sh
```

Output mirrors the baseline demo's layout — recording artifacts land in
`docs/assets/` so the publish surface and the demo script share one
naming convention:

- `docs/assets/entwurf-entwurf.cast` — raw asciinema recording (gitignored via global `*.cast`)
- `docs/assets/entwurf-entwurf.gif` — tracked, referenced by the top-level `README.md` Entwurf section
- `demo/peer-debug.log` — `ENTWURF_DEBUG=1` stderr from the top pane (gitignored, stays next to the script)
- `demo/sender-debug.log` — same from the bottom pane

Watch debug live (separate terminal, before `bash demo.sh`):

```bash
tail -F demo/sender-debug.log demo/peer-debug.log
```

Quick post-run greps:

```bash
grep 'entwurf:debug'        demo/sender-debug.log
grep -E '(entwurf|model-switch)' demo/sender-debug.log
```

## Tunables (env vars)

### `demo.sh` (entwurf two-pane)

| Var | Default | Meaning |
|---|---|---|
| `PEER_MODEL` | `entwurf/gpt-5.4` (≡ `piat`) | top pane backend (receives greeting) |
| `SENDER_MODEL` | `entwurf/claude-sonnet-5` (≡ `pias`) | bottom pane backend (drives scenes) |
| `SCENE_DELAY` | `25` | seconds to wait for each scene's agent work |
| `WARMUP` | `3` | seconds to wait for both pi banners |
| `FINAL_PAUSE` | `5` | extra wait after scene 3 (peer reply lag) |
| `GIF_SPEED` | `2.8` | agg playback multiplier (cast time → GIF time) |
| `SESSION` | `entwurf-demo` | tmux session name |
| `OUTDIR` | `demo/` | debug log directory (cast + gif live in `docs/assets/`) |

### `demo-baseline.sh` (single-pane baseline + entwurf)

| Var | Default | Meaning |
|---|---|---|
| `DRIVER_MODEL` | `entwurf/claude-sonnet-5` (≡ `pias`) | the driven pane — answers Q-B0 and spawns the sibling |
| `SIBLING_MODEL` | `entwurf/gpt-5.4` (≡ `piat`) | cross-backend sibling spawned in scene 2 |
| `SIBLING_CWD` | repo root | cwd passed to the entwurf sibling (drives `<project-context>` injection) |
| `SCENE1_DELAY` | `60` | seconds for the long English baseline answer |
| `SCENE2_DELAY` | `30` | seconds for the sync entwurf round-trip |
| `WARMUP` | `3` | seconds to wait for the pi banner |
| `FINAL_PAUSE` | `4` | extra wait after scene 2 |
| `GIF_SPEED` | `2.0` | agg playback multiplier (slower than `demo.sh` — the answer rewards reading) |
| `GIF_COMPRESS` | `1` | run gifsicle after agg (`0` to skip) |
| `GIF_LOSSY` | `200` | gifsicle `--lossy` strength (drop to `80` if a future scenario shows artifacts) |
| `GIF_COLORS` | `64` | gifsicle `--colors` palette size |
| `SESSION` | `entwurf-baseline-demo` | tmux session name |
| `OUTDIR` | `demo/` | debug log directory (cast + gif live in `docs/assets/`) |

### Model ↔ alias map

The demo launch lines correspond to your shell aliases:

| Alias | Model id | Use as |
|---|---|---|
| `piao` | `entwurf/claude-opus-5` | `SENDER_MODEL` (precision scenes) |
| `pias` | `entwurf/claude-sonnet-5` | `SENDER_MODEL` (default) |
| `piat` | `entwurf/gpt-5.4` | `PEER_MODEL` (default) |
| `piat5` | `entwurf/gpt-5.5` | either |
| `piag` | `entwurf/gemini-3.1-pro-preview` | either |

Each pane runs with `ENTWURF_DEBUG=1` baked in — same shape as
the aliases — so every spawn/model-switch/entwurf trace lands in the
debug log files (see below).

Examples:

```bash
# Swap peer to gemini
PEER_MODEL=entwurf/gemini-3.1-pro-preview bash demo.sh

# Faster pacing for short retake
SCENE_DELAY=30 FINAL_PAUSE=10 bash demo.sh

# All three backends in one demo would need a 3-pane variant — out of scope here.
```

## Prerequisites

- `pi` on PATH (current floor 0.85.1)
- `entwurf` provider configured + auth ready for the selected sender/peer models
- `asciinema` installed
- `agg` installed (optional — only for GIF conversion)
- `gifsicle` installed (optional — `demo-baseline.sh` post-compress step; skip with `GIF_COMPRESS=0`. On NixOS: `nix-shell -p gifsicle` covers both scripts)
- `tmux` installed

If you watch the demo live: open another terminal and run
`tmux attach -t entwurf-demo -r` (read-only attach) **before** the script
starts recording. Do not attach writable — keystrokes from your terminal
would collide with the driver.

## Why pre-baked prompts

Each scene's prompt asks the inner agent to discover state itself
(`entwurf_peers`, prior Session ID from this conversation). So the driver
script types static strings only — no sessionId injection, no
output parsing. That's what makes it reproducible.

## Editing scenes

Open `demo.sh`, edit the three `tmux send-keys -t "$SENDER_PANE" -l '...'`
blocks under the `drive()` function. The `-l` flag tells tmux to send the
argument literally (no key-name interpretation), so quotes inside the prompt
are safe as long as you don't use single quotes inside the single-quoted
argument.

## Tracked vs. ignored

Tracked (committed):

- `demo/demo.sh`
- `demo/demo-baseline.sh`
- `demo/README.md`
- `docs/assets/entwurf-demo.gif` — archived pre-0.12 README demo GIF (no longer `package.json#pi.image`)
- `docs/assets/entwurf-entwurf.gif` — archived pre-0.12 Entwurf section illustration

Ignored (regenerable recording artifacts — both demos):

- `*.cast` (global rule — applies under `docs/assets/` too)
- `demo/*.log`

Both demos write their recording artifacts directly into `docs/assets/`
using the names above. Re-running a demo overwrites the previous take so
the published preview always matches `main`. The `.cast` source stays
local (global `*.cast` ignore); only the `.gif` rides the publish surface.
The `gifsicle` step inside `demo-baseline.sh` makes the take reproducible
without a manual compression pass — see the Tunables table for tuning the
lossy/colors flags.
