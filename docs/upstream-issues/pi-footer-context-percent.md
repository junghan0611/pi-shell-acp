# pi-coding-agent — context-usage metric conflates cacheRead with live context

## Summary

`calculateContextTokens(usage)` — the function pi uses to drive the TUI footer's context-usage percent **and** compaction timing decisions — includes `cacheRead` and `cacheWrite` in its result. On sessions where cache-heavy turns dominate (long prompt-cache conversations, large tool-call payloads that the provider caches), this causes the context metric to report a much higher fill than the live transcript actually occupies, which in turn:

1. makes the footer look alarming even when there is plenty of live context left ("78.9% / 1.0M" with `cacheRead=769,183`), and
2. can trigger compaction prematurely, because the same function decides when compaction fires.

This is reported from a real session: total `789,429` of which `769,183` was `cacheRead`.

## Reproduction

```
- Open an opus-tier session (contextWindow=1_000_000).
- Run a long conversation with prompt caching enabled on the backend
  (i.e. Anthropic Claude Sonnet/Opus with cache_control markers).
- After a few multi-turn replies, read the TUI footer's context percent
  AND the last assistant message usage block.
- Observe: footer shows ~78% / 1M; actual live transcript is a small
  fraction of that. The difference is entirely cacheRead + cacheWrite.
```

## Code path

File: `pi-mono/packages/coding-agent/src/core/compaction/compaction.ts:135-136`

```ts
export function calculateContextTokens(usage: Usage): number {
    return usage.totalTokens || usage.input + usage.output + usage.cacheRead + usage.cacheWrite;
}
```

Consumers of this function in the same package:

- `modes/interactive/components/footer.ts` — drives the TUI footer percent display.
- `core/compaction/compaction.ts:202` — `const usageTokens = calculateContextTokens(usageInfo.usage);` — drives compaction timing decisions.
- `core/agent-session.ts:1827` — `contextTokens = calculateContextTokens(assistantMessage.usage);` — per-session accounting.

All three derive the same "context size" metric from a value that is actually an API-billing total.

## Why this matters beyond cosmetics

- **Operator confusion.** The footer reads as "context is almost full" when the live context is small. Users migrating from Claude Code / Codex native clients are accustomed to a footer that reflects *live* occupancy. On pi the number reflects billing-side totals.
- **Compaction timing drift.** Because the same value gates compaction, a session with heavy cacheRead usage may trigger compaction while the actual live transcript is still well under the model's context capacity. Compacting too early means losing content the session could have kept.
- **Provider-level `contextWindow` declarations look wrong.** Downstream ACP routers (for example pi-shell-acp) declare honest `contextWindow` values that match the underlying model capacity. Those values are the *denominator* in pi's footer calculation. When the numerator is cache-inclusive, an honest denominator looks like an overstated capacity. The router cannot compensate without declaring dishonest capacity to every other consumer that reads the same surface.

## Proposed fixes

Two orthogonal options; either is an improvement, and they can be combined.

### Option A — exclude cacheRead / cacheWrite from the context metric

Change `calculateContextTokens(usage)` so the footer + compaction metric tracks live-context tokens only:

```ts
// One possible shape — strict live-only
export function calculateContextTokens(usage: Usage): number {
    return usage.input + usage.output;
}
```

Or, if `totalTokens` from the provider is trusted for some providers but not others, gate the fallback on provider semantics rather than blindly summing cache fields.

Trade-off: this is the simpler fix and most closely matches what operators think the footer means. Risk: any existing telemetry or pricing-adjacent consumer that relied on the cache-inclusive behaviour of this one function breaks. That can be mitigated by splitting out a second function (`calculateBillingTokens(usage)`) for any such consumer.

### Option B — split the footer UI

Keep `calculateContextTokens` as-is for accounting consumers, but change the footer to display two numbers side by side instead of folding them into one percent:

```
ctx 18.4% / 1.0M      usage 789k (cache 769k)
```

Trade-off: requires only footer-layer changes; no risk to compaction logic. But compaction timing is still driven by the cache-inclusive metric, so the operator-confusion half is fixed while the early-compaction half is not.

**Recommendation.** Apply Option A to `calculateContextTokens` *and* keep Option B's visual separation in the footer. The live metric drives both UI and compaction; the billing-side metric becomes a separate display value for operators who want to watch cache economics.

## Related

- Downstream repo `pi-shell-acp` recently changed opus models' default `contextWindow` from a shared 200K cap to per-model defaults (sonnet 200K, opus 1M) at commit [`3a4dedf`](https://github.com/junghan0611/pi-shell-acp/commit/3a4dedf). That change is honest to model capacity; it made this pre-existing upstream metric mismatch more visible on opus sessions. The downstream change itself is not the fix target.

## Environment

- `@mariozechner/pi-coding-agent` at version `0.70.0`.
- `@mariozechner/pi-ai` at version `0.70.0`.
- Node >= 22.6.
- Observed via pi-shell-acp on Anthropic opus-4-7; prompt cache active.
