---
name: example-skill
description: Reference SKILL.md showing the minimum frontmatter pi-shell-acp expects when injecting a skill via the skillPlugins lane. Replace this file with the real skill body (or symlink the directory from another repo's skills/<name>/).
---

# example-skill

This file is the bare minimum a skill needs:

- `name` — how the skill is referenced (must match the directory name).
- `description` — surfaced to the agent so it can decide whether to invoke the skill. Keep it concrete and trigger-oriented; the agent reads this listing once per turn budget.

The body below the frontmatter is loaded when the skill is actually invoked. Put the operating instructions, scripts, and references here.

This reference plugin is consumed by the Claude backend only. Codex via codex-acp does not use the SDK plugins option; codex skill-equivalent surfaces flow through the bridge MCP servers configured in `piShellAcpProvider.mcpServers`.
