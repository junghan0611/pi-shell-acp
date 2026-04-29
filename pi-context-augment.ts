/**
 * pi-context-augment — system narrative + project context delivered to the
 * ACP-side agent on the first user message of a freshly opened session.
 *
 * Why this exists as a separate surface from `engraving.ts`
 * ========================================================
 *
 * The ACP-side agent needs two different kinds of context:
 *
 *   1. Bridge identity narrative — "you are speaking through pi-shell-acp",
 *      "Connected MCP servers: …", entwurf-as-sibling invariant.
 *   2. Working environment — pi's base intro and tool surface, the operator's
 *      personal `~/AGENTS.md`, the project's `cwd/AGENTS.md`, current date,
 *      current working directory.
 *
 * Both used to be candidates for the system-prompt carrier
 * (`_meta.systemPrompt`). Operator evidence (2026-04-29) showed that path
 * triggers Anthropic's metered-billing classification the moment the carrier
 * grows beyond the SDK-default shape — subscription users hit HTTP 400
 * "You're out of extra usage" instead of getting their session.
 *
 * → Both kinds of context now ride the **first user message** instead. The
 * system-prompt carrier (`engraving.ts`) stays small and stays inside
 * subscription billing; the rich context lives in a ContentBlock prepended
 * to the first prompt of a `bootstrapPath="new"` session, which is
 * structurally identical to a long user message and does not affect
 * billing classification.
 *
 * Entwurf de-duplication
 * ======================
 *
 * `pi-extensions/lib/entwurf-core.ts:enrichTaskWithProjectContext` already
 * prepends a `<project-context path="${cwd}/AGENTS.md">` block to the task
 * sent through the entwurf MCP tool. When that task lands as the first user
 * message of an ACP session (entwurf-spawned bridge session), augmenting it
 * a second time would mean the same AGENTS.md content appearing twice in
 * the same prompt.
 *
 * The de-dup check itself lives in `acp-bridge.ts:sendPrompt`, where the
 * first user message text is actually known. This module just produces the
 * augment text; the bridge decides whether to apply it on the wire.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import * as path from "node:path";

import type { AcpBackend } from "./acp-bridge.js";

const MAX_AUGMENT_BYTES = 50 * 1024;

export interface PiContextAugmentParams {
	backend: AcpBackend;
	cwd: string;
	mcpServerNames: string[];
}

/**
 * Returns the augment text to prepend to the first user message of a new
 * ACP session.
 *
 * The output is a pure function of (cwd, backend, mcpServerNames, AGENTS.md
 * file contents at call time). Date is rendered to day granularity so two
 * prompts on the same calendar day produce the same augment.
 */
export function buildPiContextAugment(params: PiContextAugmentParams): string {
	const mcpList = params.mcpServerNames.length > 0 ? params.mcpServerNames.join(", ") : "(none registered)";

	const sections: string[] = [];

	sections.push(
		[
			"You are operating through pi-shell-acp, an ACP bridge between pi (the harness) and the underlying model.",
			`Backend: ${params.backend}.`,
			`Connected MCP servers: ${mcpList}.`,
			"When entwurf is invoked, you do not spawn workers — you summon sibling agents through this bridge.",
		].join("\n"),
	);

	sections.push(
		[
			"You are an expert coding assistant operating inside pi, a coding agent harness.",
			"You help users by reading files, executing commands, editing code, and writing new files.",
			"",
			"Tool surface:",
			"- Treat the actual callable function/tool schema exposed in this session as the source of truth.",
			"- Do not assume a tool exists only because this context or AGENTS.md mentions it.",
			"- Pi-level work generally includes reading files, running shell commands, editing files, and writing files; concrete tool names differ by backend.",
			"- Native pi may expose read/bash/edit/write; Claude ACP may expose Read/Bash/Edit/Write/Skill; Codex ACP may expose exec_command/apply_patch/write_stdin/update_plan.",
			"- MCP/custom tools are usable only when they appear in the actual tool schema for this session.",
		].join("\n"),
	);

	const projectContextParts: string[] = [];
	const homeAgents = path.join(homedir(), "AGENTS.md");
	const cwdAgents = path.join(params.cwd, "AGENTS.md");

	if (existsSync(homeAgents)) {
		try {
			const content = readFileSync(homeAgents, "utf8").trim();
			if (content.length > 0) {
				projectContextParts.push(`## ${homeAgents}\n\n${content}`);
			}
		} catch (error) {
			throw new Error(
				`Failed to read home AGENTS.md at ${homeAgents}: ${error instanceof Error ? error.message : String(error)}`,
			);
		}
	}

	if (existsSync(cwdAgents) && cwdAgents !== homeAgents) {
		try {
			const content = readFileSync(cwdAgents, "utf8").trim();
			if (content.length > 0) {
				projectContextParts.push(`## ${cwdAgents}\n\n${content}`);
			}
		} catch (error) {
			throw new Error(
				`Failed to read cwd AGENTS.md at ${cwdAgents}: ${error instanceof Error ? error.message : String(error)}`,
			);
		}
	}

	if (projectContextParts.length > 0) {
		sections.push(
			["# Project Context", "", "Project-specific instructions and guidelines:", "", ...projectContextParts].join("\n"),
		);
	}

	const currentDate = new Intl.DateTimeFormat("en-CA", {
		timeZone: "Asia/Seoul",
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
	}).format(new Date());
	sections.push([`Current date: ${currentDate}`, `Current working directory: ${params.cwd}`].join("\n"));

	return truncateAugment(sections.join("\n\n"));
}

function truncateAugment(text: string): string {
	if (Buffer.byteLength(text, "utf8") <= MAX_AUGMENT_BYTES) return text;
	const marker = `\n\n[pi-shell-acp: context augment truncated to ${MAX_AUGMENT_BYTES} bytes; read AGENTS.md files directly if more detail is needed.]`;
	const markerBytes = Buffer.byteLength(marker, "utf8");
	let end = text.length;
	while (end > 0 && Buffer.byteLength(text.slice(0, end), "utf8") + markerBytes > MAX_AUGMENT_BYTES) {
		end = Math.max(0, end - 1024);
	}
	while (end < text.length && Buffer.byteLength(text.slice(0, end + 1), "utf8") + markerBytes <= MAX_AUGMENT_BYTES) {
		end++;
	}
	return `${text.slice(0, end).trimEnd()}${marker}`;
}
