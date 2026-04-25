/**
 * engraving — the short self-recognition prompt pi-shell-acp surfaces to the
 * ACP-side agent at session bootstrap.
 *
 * The canonical source is `prompts/engraving.md`, read at runtime so the
 * prompt can be edited without rebuilding the bridge. Placeholders are
 * interpolated here against the current backend + mcp wiring so the agent
 * sees "what is actually connected" rather than a static claim.
 *
 * Consumption:
 *   - Claude backend: rendered text is concatenated into systemPromptAppend
 *     alongside any baseSystemPrompt / post-compaction summary, so pi's
 *     `_meta.systemPrompt.append` path delivers it to the ACP session.
 *   - Codex backend: delivery path will be a ContentBlock prepended to the
 *     first prompt turn — wired via AcpBackendAdapter.buildBootstrapPromptAugment
 *     once the codex-acp delivery spike confirms the ContentBlock reaches model
 *     context reliably. Not enabled yet.
 *
 * Stability contract:
 *   The rendered output MUST be a pure function of (template content on disk,
 *   backend, mcpServerNames). That stability is why cachedSource is keyed by
 *   file path and the interpolation has no clock/random/env-time inputs.
 *   `bridgeConfigSignature` hashes systemPromptAppend — if this output drifts
 *   turn-to-turn, pi-shell-acp will rebuild the ACP session every turn.
 *
 * A/B experimentation:
 *   Set PI_SHELL_ACP_ENGRAVING_PATH=/abs/path/to/alt-engraving.md to point
 *   the loader at a different prompt file. The env override bypasses the
 *   in-process cache so edits are picked up on the next session bootstrap.
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
 * Returns the rendered engraving, or null when the template file is missing /
 * unreadable. A missing engraving is not fatal — the bridge still operates;
 * the agent simply won't see the self-recognition prompt.
 */
export function loadEngraving(params: EngravingParams): string | null {
	try {
		const filePath = resolveEngravingPath();
		const source = loadSource(filePath);
		const rendered = interpolate(source, params).trim();
		return rendered.length > 0 ? rendered : null;
	} catch {
		return null;
	}
}
