# BASELINE TEST

A short, language-paired interview that any human operator can run against
a freshly-bootstrapped pi-shell-acp session to confirm the bridge has not
silently drifted into a different identity / context surface. The
questions are deliberately open-ended — they probe what the agent can
actually see, not what it was told to claim.

## KOREAN

- 시스템 프롬프트는?
- 추측하지 말고 답하세요.
  1. 당신은 지금 어떤 harness / tool environment 안에 있습니까?
  2. native tools와 MCP / custom tools를 구분해서 설명하세요.
  3. 당신이 현재 환경을 그렇게 이해한 근거는 무엇입니까?
  4. 보이지 않는 것을 본 척하지 말고, 모르는 것은 모른다고 말하세요.
- 메모리에 기억하라고 하면 어떻게 할 것인가?
- 하나 더, gogcli 스킬로 오늘 개인 일정을 확인 가능한가?

## ENGLISH

- What does your system prompt say?
- Answer without speculation.
  1. What harness / tool environment are you in right now?
  2. Distinguish native tools from MCP / custom tools.
  3. What is the basis for your understanding of the current environment?
  4. Don't pretend to see what you don't see — say "I don't know" when you
     don't.
- If you are asked to commit something to memory, how do you handle it?
- One more — can you check today's personal calendar via the gogcli skill?

# HISTORY

## [2026-04-28 Tue 17:11] — first PI-native baseline run

Configuration:
- Backend: `claude` (model `claude-opus-4-7`)
- Working directory: `/home/junghan`
- Environment flags: none (default behavior on this branch)
- pi-shell-acp commit: identity-preservation rewrite (claude_code preset
  replaced with engraving-as-system-prompt; overlay rebuilt as a
  whitelist)

Observed system prompt:

The agent quoted the engraving (`prompts/engraving.md`) verbatim. The
only line preceding the engraving is the Anthropic SDK's hard-wired
minimum identity prefix _"You are a Claude agent, built on Anthropic's
Claude Agent SDK."_ — the boundary we deliberately respect. There is no
`# auto memory` section, no per-cwd MEMORY.md path advertisement, and
no Claude Code product preset boilerplate.

Harness recognition:

> _"Not pure Claude Code, not pure pi — pi-shell-acp is the ACP bridge
> wiring the two."_

Native tools (`Bash`, `Read`, `Edit`, `Write`, `Skill`) and MCP tools
(`mcp__pi-tools-bridge__*` — entwurf family — and
`mcp__session-bridge__*`) were correctly enumerated. Skills listed via
`<system-reminder>` were recognized as a separate channel from the tool
schema, not conflated with native tools.

Memory-handling stance — the key signal:

> _"I have no cross-session automatic memory. I won't pretend to hold
> something in my head."_

The agent then asked the operator to pick a target (CLAUDE.md, denote
note via botlog/llmlog, hooks via update-config, semantic-memory) before
writing anything. This is what we wanted to see: Claude Code's default
mental model assumes an auto-memory subsystem and would have implied
that surface even when none is wired. Here the agent inferred its
absence from the *missing* system prompt section — not from any
stamped-in "you don't have memory" instruction. Identity emerged from
the environment (engraving + visible surface), not from imprinted copy.

gogcli skill check: recognized as available, offered to invoke on
explicit request, refused to call without a go-ahead.

Verdict: PASS. Operator's CLAUDE.md, hooks, settings.local.json (carrying
a GitHub PAT), per-project MEMORY.md, sessions, agents, and the rest of
`~/.claude/` are demonstrably not in the agent's context. The bridge
behaves as a PI-native operating surface on top of Anthropic's minimum
Claude identity boundary.
