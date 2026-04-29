/**
 * engraving — operator-authored personal additions to the ACP-side agent's
 * system prompt at session bootstrap.
 *
 * Role
 * ====
 *
 * This is an **operator surface**, not a system narrative carrier. Things
 * that belong here:
 *   - personal notes the operator wants to attach to every session that
 *     don't fit in AGENTS.md (e.g. private working conventions, secrets-free
 *     reminders, model-mode preferences).
 *
 * Things that do NOT belong here:
 *   - Bridge identity narrative ("you are speaking through pi-shell-acp",
 *     "Connected MCP servers: …", entwurf-as-sibling invariant).
 *     Those live in `pi-context-augment.ts` and ride the first-user-message
 *     surface so the system-prompt carrier stays small.
 *   - cwd / home AGENTS.md content. Same — first-user-message surface.
 *   - pi base intro / Available tools. Same.
 *
 * Why minimal
 * ===========
 *
 * Anthropic's subscription billing (Claude Code OAuth, "정액제") classifies a
 * call by how close the system prompt stays to the SDK-default shape. When
 * `_meta.systemPrompt = <string>` materially exceeds the baseline shape —
 * e.g. by injecting AGENTS.md, the pi base prompt, or any other multi-KB
 * material — the call is routed to metered "extra usage" billing. Operators
 * on subscription with no metered balance see HTTP 400 the moment the
 * carrier grows.
 *
 * → Keep this file SHORT. Empty is fine. The default ships as a single-line
 * placeholder so operators have a clear hint that this surface exists.
 *
 * Consumption
 * ===========
 *
 * If non-empty, the rendered text is concatenated into `systemPromptAppend`
 * alongside any baseSystemPrompt and ultimately delivered as
 * `_meta.systemPrompt = <string>` (Claude) or
 * `-c developer_instructions=<string>` (Codex).
 *
 * If empty / missing, the engraving is silently skipped — operators who
 * don't need a personal additions surface aren't forced to use it.
 *
 * Stability contract
 * ==================
 *
 * The rendered output MUST be a pure function of (template content on disk,
 * backend, mcpServerNames). That stability is why cachedSource is keyed by
 * file path and the interpolation has no clock/random/env-time inputs.
 * `bridgeConfigSignature` hashes systemPromptAppend — if this output drifts
 * turn-to-turn, pi-shell-acp will rebuild the ACP session every turn.
 *
 * A/B experimentation
 * ===================
 *
 * Set `PI_SHELL_ACP_ENGRAVING_PATH=/abs/path/to/alt-engraving.md` to point
 * the loader at a different prompt file. The env override bypasses the
 * in-process cache so edits are picked up on the next session bootstrap.
 */

import { readFileSync } from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import type { AcpBackend } from "./acp-bridge.js";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_ENGRAVING_PATH = path.join(HERE, "prompts", "engraving.md");

export interface EngravingParams {
	backend: AcpBackend;
	mcpServerNames: string[];
}

type CachedSource = { filePath: string; content: string };
let cached: CachedSource | null = null;

function resolveEngravingPath(): string {
	const envPath = process.env.PI_SHELL_ACP_ENGRAVING_PATH?.trim();
	return envPath ? path.resolve(envPath) : DEFAULT_ENGRAVING_PATH;
}

function loadSource(filePath: string): string {
	// Env override → always re-read (A/B experimentation); default path → cache once.
	if (filePath !== DEFAULT_ENGRAVING_PATH) {
		return readFileSync(filePath, "utf8");
	}
	if (!cached || cached.filePath !== filePath) {
		cached = { filePath, content: readFileSync(filePath, "utf8") };
	}
	return cached.content;
}

function interpolate(template: string, params: EngravingParams): string {
	const mcpList = params.mcpServerNames.length > 0 ? params.mcpServerNames.join(", ") : "(none registered)";
	return template.replace(/\{\{backend\}\}/g, params.backend).replace(/\{\{mcp_servers\}\}/g, mcpList);
}

/**
 * Returns the rendered engraving, or null if the engraving file is empty,
 * missing, or unreadable. The engraving is an optional operator-authored
 * surface — operators who don't need it shouldn't be forced to populate it,
 * so absence is a normal state, not an error.
 *
 * Callers should treat null as "no engraving configured" and skip the
 * `_meta.systemPrompt` injection. The bridge identity narrative is carried
 * separately by `pi-context-augment.ts` on the first-user-message surface.
 */
export function loadEngraving(params: EngravingParams): string | null {
	const filePath = resolveEngravingPath();
	let source: string;
	try {
		source = loadSource(filePath);
	} catch {
		return null;
	}
	const rendered = interpolate(source, params).trim();
	if (rendered.length === 0) {
		return null;
	}
	return rendered;
}
