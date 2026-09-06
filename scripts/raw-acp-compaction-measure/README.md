# raw-acp-compaction-measure — what a compacting turn looks like after claude-agent-acp 0.75.0

Measurement receipts for the ONE change in the `claude-agent-acp 0.73.0 → 0.75.1` bump that
reaches entwurf. Not a gate; nothing here runs in any check tier.

```
LIVE=1 node --experimental-strip-types scripts/raw-acp-compaction-measure/probe.ts
```

## The change

`0.75.0` (#991, `f74a517`, "surface context compaction as an ACP tool lifecycle") stopped
sending compaction as assistant text and started sending it as a **synthetic tool call**.

`[읽음, ~/repos/3rd/claude-agent-acp]` at `v0.73.0 src/acp-agent.ts:3437-3457` a compaction
result produced two `agent_message_chunk` texts — `"\n\nCompacting completed."` and
`"Compacting failed<reason>"`. At `v0.75.1` those are gone; `ContextCompactionLifecycle`
(`git grep -c` in `src/`: **0** at v0.73.0 and v0.74.0, **2** at v0.75.0 and v0.75.1) drives
`tool_call` / `tool_call_update` notifications instead
(`dist/acp-agent.js:31`, `:1877`, `:2711-2742`).

**What did NOT change:** the post-compaction occupancy refresh. `v0.73.0
src/acp-agent.ts:3460+` already emitted a `usage_update` at `compact_boundary`, and 0.75.1
still does (`dist/acp-agent.js:2740-2752`) — only its source moved, from a
`getContextUsage` control request to `compact_metadata.post_tokens`. So the
`used_end`-shrinks-mid-turn case that `backend.ts:1286-1288` already names as #96's weak
floor is **not newly triggered by this bump**.

## M1 — one live `/compact` turn, and the same notifications replayed through our mapper

`[측정 2026-09-06, oracle, claude-agent-acp 0.75.1, model claude-sonnet-5]`
`compact stopReason=end_turn`, 2 tool-lifecycle notifications. Verbatim from the probe:

```
tool_call        kind=think status=in_progress title="Compact conversation"
                 meta={"contextCompaction":{"version":1},"claudeCode":{"toolName":"compact"}}
tool_call_update kind=-     status=failed      title=null
                 meta={"contextCompaction":{"version":1,"error":"Not enough messages to compact."},
                       "claudeCode":{"toolName":"compact"}}
```

Those exact objects, replayed through the PRODUCTION `applyAcpSessionUpdate`
(`pi-extensions/lib/acp/event-mapper.ts`) — the same function `backend.ts` calls — produce:

```json
[{"type":"text","text":"\n[tool:start] Compact conversation\n"},
 {"type":"text","text":"\n[tool:failed] Compact conversation — Compaction failed: Not enough messages to compact.\n"}]
```

### What this establishes

1. **No type or contract break.** `renderToolUpdate` (`event-mapper.ts:236-270`) routes every
   `tool_call`/`tool_call_update` regardless of `kind`, so a `kind: "think"` synthetic call
   needs no new branch. The turn ends `end_turn`, not an error.
2. **`_meta.contextCompaction` reaches nothing.** It is carried on the notification and
   dropped by the mapper, which reads only `toolCallId` / `title` / `status` / `content` /
   `rawOutput`. No accounting path sees it — `usage.acp`, `_meta.quota` and the four pi
   fields are untouched by this lifecycle.
3. **What an operator now SEES changed.** Where 0.73.0 put `Compacting completed.` in the
   assistant's own text, 0.75.1 puts a `[tool:start]` / `[tool:failed]` notice pair in the
   transcript — that pair is what was OBSERVED. On a compaction that succeeds the second
   notice is `[tool:done]`, which is inferred from the mapper's own status branch
   (`event-mapper.ts:262-266`) and not observed here; see the limits below. Either way,
   that notice pair is the whole reachable delta of this bump.

### What this does NOT establish (measured limits, stated rather than rounded off)

- **The `completed` branch was not observed.** The seeded session was too short, so the
  vendor answered `"Not enough messages to compact."` and the lifecycle terminated at
  `status: "failed"`. The success path — `status: "completed"` plus
  `_meta.contextCompaction` carrying `trigger` / `preTokens` / `postTokens` / `durationMs`
  (`f74a517` commit message; `contextCompactionMetadataFromBoundary`) — is **inferred from
  source, not measured here.** In the mapper it is the same `status`-transition branch that
  produced `[tool:failed]` above, one literal apart (`[tool:done]`,
  `event-mapper.ts:262-266`).
- **No organic (auto-trigger) compaction was driven.** Only the explicit `/compact` command.
- One host, one model, one run.
