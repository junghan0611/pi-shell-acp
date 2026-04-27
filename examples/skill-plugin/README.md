# skill-plugin reference

Reference layout for `piShellAcpProvider.skillPlugins` entries.

## Why this exists

`pi-shell-acp` defaults to SDK isolation mode (`settingSources: []`), so the Claude backend does **not** discover skills from `~/.claude/skills/` automatically. Skills are injected explicitly via the SDK's plugin path:

```ts
Options.plugins = [{ type: "local", path: "<plugin-root>" }]
```

Each `<plugin-root>` is a directory that follows the layout below. Operators list the plugin paths in `piShellAcpProvider.skillPlugins` (an array of absolute paths) and `pi-shell-acp` threads them through the ACP boundary into the SDK on every session bootstrap.

## Required layout

```
<plugin-root>/
├── .claude-plugin/
│   └── plugin.json          # manifest (name, description, optional author/version)
└── skills/
    └── <skill-name>/
        └── SKILL.md         # YAML frontmatter (name, description) + body
```

`name` in `SKILL.md` frontmatter must match the directory name. Optional fields like `tools:` are honored by Claude Code's skill loader; keep them aligned with the pi-shell-acp default tool surface (`Read`, `Bash`, `Edit`, `Write`) unless you have a reason to widen.

## Adopting an existing skill collection

If you already maintain skills under `your-repo/skills/<name>/SKILL.md` (e.g. as `~/.claude/skills/<name>` symlink targets), turning the repo into a plugin needs only one new file:

```bash
your-repo/.claude-plugin/plugin.json
```

The existing `skills/` directory is reused as-is. Then add the repo's absolute path to your pi config:

```json
"piShellAcpProvider": {
  "skillPlugins": ["/absolute/path/to/your-repo"]
}
```

`./run.sh install` does not auto-populate `skillPlugins` — operators choose which plugin paths to attach.

## Verification

After adding `skillPlugins` and running a `pi-shell-acp/claude-*` session, ask the agent:

> 추측하지 말고 답하세요. 사용 가능한 skill을 모두 나열하세요. 보이지 않는 것은 모른다고 말하세요.

The agent should list every `<skill-name>` whose directory is under one of your `skillPlugins` paths. If skills are missing, check:

1. `<plugin-root>/.claude-plugin/plugin.json` exists and is valid JSON.
2. `<plugin-root>/skills/<skill-name>/SKILL.md` exists and the frontmatter `name:` matches the directory name.
3. `piShellAcpProvider.skillPlugins` contains the absolute plugin-root path (not the inner `skills/` path).
4. The pi-shell-acp build picked up the config — bridgeConfigSignature folds `skillPlugins`, so adding/removing plugins invalidates persisted ACP mappings on the next turn automatically.
