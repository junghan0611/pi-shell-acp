/**
 * ACP SDK dependency-surface contract — Phase 3 lane of issue #62, migrated from
 * `scripts/check-acp-sdk-surface.ts` (deleted; `./run.sh check-acp-sdk-surface`
 * remains the transition shim into this file).
 *
 * Historical contract mapping — every layer of the retired gate, by name:
 *
 *   L1   package.json exact pins            → "L1: package.json pins the three ACP deps exactly"
 *   L2   pnpm-lock peer-resolution lock     → "L2: pnpm-lock peer-resolves the anthropic SDK to the pin"
 *   L2b  runtime anthropic peer probe       → "L2b: claude-agent-sdk context peer-resolves the anthropic SDK"
 *   L2c  adapter wire-SDK + MCP resolves    → "L2c: adapter context resolves the shared wire SDK"
 *                                             + "L2c: claude-agent-sdk context resolves its declared MCP peer"
 *   L3   wire-SDK value-export surface      → "L3: the wire SDK still value-exports every symbol the raw turn uses"
 *   L4   forbidden import/API-client sweep  → "L4: no tracked source imports the anthropic SDK or builds an API client"
 *
 * The pins freeze the current behavior-oracle versions:
 *
 *   @agentclientprotocol/sdk              1.4.0    wire SDK (acp-bridge import source)
 *   @agentclientprotocol/claude-agent-acp 0.75.1   Claude adapter (spawn binary)
 *   @anthropic-ai/sdk                     0.100.1  peer-resolution pin ONLY
 *
 * The anthropic SDK is NOT an API client / auth surface here: it exists solely to
 * satisfy @anthropic-ai/claude-agent-sdk@0.3.257's `>=0.93.0` peer floor — drop it
 * and the tree resolves a stale 0.91.1, an unmet peer that would only surface at
 * the first raw turn. Source-level import / client instantiation stays forbidden
 * (L4). Per-bump measurement history (0.61→0.65 tarball hashes, reachability
 * judgments, "do not reuse a previous bump's argument") is durable in the ROADMAP
 * **Dep bump(별도 트랙)** ledger and the #62/#63 issue records — re-measure there
 * on every bump; this file carries only the current pinned truth.
 *
 * Lock text (L2) and the work-surface sweep (L4) stay deliberately STATIC — the
 * lockfile bytes and the tracked source set ARE the artifacts under contract.
 * The resolver probes (L2b/L2c) and export surface (L3) are behavioral: they run
 * the real Node resolver over the installed module graph, because lock text alone
 * once left a nested, never-probed MCP copy invisible (a probe whose subject is
 * "whatever the root happens to hoist" is a coincidence, not a check).
 */

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const REPO_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p: string): string => readFileSync(resolve(REPO_DIR, p), "utf8");

// Split literals so this file's own regexes never self-match in the L4 sweep.
const ANTHROPIC_SDK = `@anthropic-ai/${"sdk"}`;
const API_CLIENT_CLASS = `${"Anthropic"}`;

const PINS: Record<string, string> = {
	"@agentclientprotocol/sdk": "1.4.0",
	"@agentclientprotocol/claude-agent-acp": "0.75.1",
	[ANTHROPIC_SDK]: "0.100.1",
};

/** Walk up from a resolved entry to the nearest package.json — a `<pkg>/package.json`
 * subpath resolve can fail under "exports", so the entry path is the anchor. */
function pkgInfoFromEntry(entryPath: string): { name: string; version: string; dir: string } {
	let dir = dirname(entryPath);
	for (;;) {
		try {
			const pj = JSON.parse(readFileSync(resolve(dir, "package.json"), "utf8")) as {
				name?: string;
				version?: string;
			};
			if (pj.name && pj.version) return { name: pj.name, version: pj.version, dir };
		} catch {
			// no package.json here (or unreadable) — keep walking up.
		}
		const parent = dirname(dir);
		if (parent === dir) throw new Error(`no package.json found walking up from ${entryPath}`);
		dir = parent;
	}
}

describe("L1 — package.json exact pins", () => {
	it("L1: package.json pins the three ACP deps exactly", () => {
		const pkg = JSON.parse(read("package.json")) as { dependencies?: Record<string, string> };
		const deps = pkg.dependencies ?? {};
		for (const [name, ver] of Object.entries(PINS)) {
			expect(deps[name], `dependencies["${name}"] must be exact "${ver}" — the pins freeze the oracle set`).toBe(ver);
		}
	});
});

describe("L2 — pnpm-lock peer-resolution lock (static: the lockfile bytes are the artifact)", () => {
	it("L2: pnpm-lock peer-resolves the anthropic SDK to the pin", () => {
		const lock = read("pnpm-lock.yaml");
		expect(
			lock,
			"claude-agent-acp@0.75.1 must peer-resolve @anthropic-ai/sdk@0.100.1 (peer-pin), not the stale 0.91.1",
		).toMatch(/@agentclientprotocol\/claude-agent-acp@0\.75\.1\(@anthropic-ai\/sdk@0\.100\.1/);
		expect(
			lock,
			"claude-agent-sdk@0.3.257 must peer-resolve @anthropic-ai/sdk@0.100.1 — else its >=0.93.0 peer floor is unmet",
		).toMatch(/@anthropic-ai\/claude-agent-sdk@0\.3\.257\(@anthropic-ai\/sdk@0\.100\.1/);
	});
});

// The live module graph the adapter actually traverses. A top-level resolve of the
// anthropic SDK may legitimately see pi's own transitive 0.91.1 — the edge under
// contract is the one INSIDE claude-agent-sdk's context.
const rootRequire = createRequire(resolve(REPO_DIR, "package.json"));
const adapterRequire = createRequire(rootRequire.resolve("@agentclientprotocol/claude-agent-acp/package.json"));
const casInfo = pkgInfoFromEntry(adapterRequire.resolve("@anthropic-ai/claude-agent-sdk"));
const casRequire = createRequire(resolve(casInfo.dir, "package.json"));

describe("L2b — runtime peer-resolution probe (behavioral: the real Node resolver)", () => {
	it("L2b: claude-agent-sdk context peer-resolves the anthropic SDK", () => {
		expect(
			casInfo.version,
			"@anthropic-ai/claude-agent-sdk must runtime-resolve to 0.3.257 from the adapter context",
		).toBe("0.3.257");
		const sdkInfo = pkgInfoFromEntry(casRequire.resolve(ANTHROPIC_SDK));
		expect(
			sdkInfo.version,
			`${ANTHROPIC_SDK} must peer-resolve to 0.100.1 from the claude-agent-sdk context — a 0.91.1 here means the >=0.93.0 peer is unmet and the raw turn would break`,
		).toBe("0.100.1");
	});
});

describe("L2c — adapter-context wire-SDK + MCP-SDK resolves", () => {
	it("L2c: adapter context resolves the shared wire SDK", () => {
		const wireInfo = pkgInfoFromEntry(adapterRequire.resolve("@agentclientprotocol/sdk"));
		expect(
			wireInfo.version,
			"@agentclientprotocol/sdk must runtime-resolve to 1.4.0 from the adapter context — the adapter and the backend must share one wire SDK",
		).toBe("1.4.0");
	});
	it("L2c: claude-agent-sdk context resolves its declared MCP peer", () => {
		// The MCP SDK gates its bare specifier behind "exports" — resolve a real
		// SUBPATH and walk up. Resolving from the claude-agent-sdk context binds the
		// real adapter → claude-agent-sdk → MCP edge (the root's hoisted copy is a
		// coincidence, not a contract).
		const mcpInfo = pkgInfoFromEntry(casRequire.resolve("@modelcontextprotocol/sdk/server/index.js"));
		expect(
			mcpInfo.version.startsWith("1.29."),
			`@modelcontextprotocol/sdk must runtime-resolve to 1.29.x from the claude-agent-sdk context (got ${mcpInfo.version}) — claude-agent-sdk 0.3.257 declares a ^1.29.0 peer`,
		).toBe(true);
	});
});

describe("L3 — wire-SDK value-export surface (silent-rename gate)", () => {
	it("L3: the wire SDK still value-exports every symbol the raw turn uses", async () => {
		// The value imports the real ACP code uses: connectAcpClient (acp-client.ts)
		// drives `client` + the AGENT_METHODS/CLIENT_METHODS tables; the backend and
		// raw-turn smoke value-import `ndJsonStream` and `PROTOCOL_VERSION`. A silent
		// upstream rename erases nothing at typecheck (type-only erasure) but breaks
		// the raw turn.
		const acpSdk = (await import("@agentclientprotocol/sdk")) as Record<string, unknown>;
		for (const sym of ["client", "ndJsonStream", "PROTOCOL_VERSION", "AGENT_METHODS", "CLIENT_METHODS"]) {
			expect(sym in acpSdk, `@agentclientprotocol/sdk lost value export "${sym}" — the raw ACP turn would break`).toBe(
				true,
			);
		}
	});
});

describe("L4 — no source-level anthropic SDK import / API client (static work-surface sweep)", () => {
	it("L4: no tracked source imports the anthropic SDK or builds an API client", () => {
		// The credential boundary (AGENTS §ACP) forbids the bridge from importing the
		// SDK or instantiating an API client; the dep is a peer-resolution pin ONLY.
		// Line-based, so this file's own split-literal regexes are never offenders.
		const tracked = execFileSync("git", ["ls-files", "*.ts", "*.js", "*.mjs", "*.cjs"], {
			cwd: REPO_DIR,
			encoding: "utf8",
		})
			.split("\n")
			.filter(Boolean)
			// `git ls-files` still names an UNSTAGED deletion; absence cannot import
			// the SDK and must not crash this read-only sweep.
			.filter((f) => existsSync(resolve(REPO_DIR, f)));

		const spec = `["']${ANTHROPIC_SDK.replace("/", "\\/")}["']`;
		const specifierPatterns: ReadonlyArray<{ re: RegExp; kind: string }> = [
			{ re: new RegExp(String.raw`\bfrom\s+${spec}`), kind: `import/export from ${ANTHROPIC_SDK}` },
			{ re: new RegExp(String.raw`^\s*import\s+${spec}`), kind: `side-effect import ${ANTHROPIC_SDK}` },
			{ re: new RegExp(String.raw`\bimport\(\s*${spec}\s*\)`), kind: `dynamic import(${ANTHROPIC_SDK})` },
			{ re: new RegExp(String.raw`\brequire\(\s*${spec}\s*\)`), kind: `require(${ANTHROPIC_SDK})` },
		];
		const clientRe = new RegExp(String.raw`\bnew\s+${API_CLIENT_CLASS}\s*\(`);

		const offenders: string[] = [];
		for (const f of tracked) {
			const src = read(f);
			for (const line of src.split("\n")) {
				for (const { re, kind } of specifierPatterns) {
					if (re.test(line)) offenders.push(`${f}: ${kind}`);
				}
				if (clientRe.test(line)) offenders.push(`${f}: new ${API_CLIENT_CLASS}() API client`);
			}
		}
		expect(offenders, `${ANTHROPIC_SDK} is a peer-resolution pin ONLY — no source import / API client allowed`).toEqual(
			[],
		);
	});
});
