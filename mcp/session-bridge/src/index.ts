/**
 * session-bridge — Cross-session communication MCP server for Claude Code
 *
 * Based on PI control.ts protocol (Unix domain sockets, newline-delimited JSON).
 * Each Claude Code session runs this MCP server, which:
 *   1. Creates a socket at ~/.claude/session-bridge/<session-id>.sock
 *   2. Exposes list_sessions / send_message / receive_messages tools
 *   3. Queues incoming messages for the session to poll
 *
 * Environment:
 *   SESSION_NAME — human-readable session alias (e.g. "entwurf", "cos")
 *   SESSION_BRIDGE_DIR — override socket directory (default: ~/.claude/session-bridge)
 *
 * Wire protocol (same as PI control.ts):
 *   Client → Server: { type: "send", message: "...", sender?: "..." }
 *   Server → Client: { type: "response", command: "send", success: true }
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs/promises";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// ============================================================================
// Configuration
// ============================================================================

const SESSION_ID = process.env.SESSION_ID || crypto.randomUUID();
const SESSION_NAME = process.env.SESSION_NAME || "";
const BRIDGE_DIR = process.env.SESSION_BRIDGE_DIR || path.join(os.homedir(), ".claude", "session-bridge");
const SOCKET_SUFFIX = ".sock";
const ALIAS_SUFFIX = ".alias";

// ============================================================================
// Types
// ============================================================================

interface IncomingMessage {
	from: string; // sender session name or id
	message: string;
	timestamp: string; // ISO 8601
}

interface RpcSendCommand {
	type: "send";
	message: string;
	sender?: string;
}

interface RpcResponse {
	type: "response";
	command: string;
	success: boolean;
	error?: string;
}

interface LiveSession {
	sessionId: string;
	name?: string;
	socketPath: string;
}

// ============================================================================
// State
// ============================================================================

const messageQueue: IncomingMessage[] = [];
let socketServer: net.Server | null = null;
let socketPath: string | null = null;

// ============================================================================
// Socket directory management
// ============================================================================

async function ensureBridgeDir(): Promise<void> {
	await fs.mkdir(BRIDGE_DIR, { recursive: true });
}

function getSocketPath(sessionId: string): string {
	return path.join(BRIDGE_DIR, `${sessionId}${SOCKET_SUFFIX}`);
}

function getAliasPath(name: string): string {
	return path.join(BRIDGE_DIR, `${name}${ALIAS_SUFFIX}`);
}

// ============================================================================
// Socket server — receives messages from other sessions
// ============================================================================

function startSocketServer(): void {
	socketPath = getSocketPath(SESSION_ID);

	socketServer = net.createServer((conn) => {
		conn.setEncoding("utf8");
		let buffer = "";

		conn.on("data", (chunk) => {
			buffer += chunk;
			let idx = buffer.indexOf("\n");
			while (idx !== -1) {
				const line = buffer.slice(0, idx).trim();
				buffer = buffer.slice(idx + 1);
				idx = buffer.indexOf("\n");
				if (!line) continue;

				try {
					const cmd = JSON.parse(line) as RpcSendCommand;
					if (cmd.type === "send" && cmd.message) {
						messageQueue.push({
							from: cmd.sender || "unknown",
							message: cmd.message,
							timestamp: new Date().toISOString(),
						});
						const resp: RpcResponse = { type: "response", command: "send", success: true };
						conn.write(JSON.stringify(resp) + "\n");
					} else {
						const resp: RpcResponse = {
							type: "response",
							command: cmd.type || "unknown",
							success: false,
							error: "Unsupported command",
						};
						conn.write(JSON.stringify(resp) + "\n");
					}
				} catch {
					const resp: RpcResponse = { type: "response", command: "parse", success: false, error: "Invalid JSON" };
					conn.write(JSON.stringify(resp) + "\n");
				}
			}
		});
	});

	socketServer.listen(socketPath, () => {
		// Set permissions so other processes can connect
		fs.chmod(socketPath!, 0o666).catch(() => {});
	});

	socketServer.on("error", (err) => {
		console.error(`[session-bridge] Socket server error: ${err.message}`);
	});
}

// ============================================================================
// Alias management — map session name to socket path
// ============================================================================

async function createAlias(name: string, sessionId: string): Promise<void> {
	if (!name) return;
	const aliasPath = getAliasPath(name);
	const targetSocket = getSocketPath(sessionId);
	try {
		await fs.unlink(aliasPath).catch(() => {});
		await fs.symlink(targetSocket, aliasPath);
	} catch {
		// Best effort
	}
}

async function removeAlias(name: string): Promise<void> {
	if (!name) return;
	try {
		await fs.unlink(getAliasPath(name));
	} catch {
		// Ignore
	}
}

// ============================================================================
// Session discovery
// ============================================================================

async function isSocketAlive(sockPath: string): Promise<boolean> {
	return new Promise((resolve) => {
		const conn = net.createConnection(sockPath);
		const timer = setTimeout(() => {
			conn.destroy();
			resolve(false);
		}, 500);
		conn.on("connect", () => {
			clearTimeout(timer);
			conn.destroy();
			resolve(true);
		});
		conn.on("error", () => {
			clearTimeout(timer);
			resolve(false);
		});
	});
}

async function getLiveSessions(): Promise<LiveSession[]> {
	await ensureBridgeDir();
	const entries = await fs.readdir(BRIDGE_DIR, { withFileTypes: true });

	// Build alias map: socket path → name
	const aliasMap = new Map<string, string>();
	for (const entry of entries) {
		if (!entry.name.endsWith(ALIAS_SUFFIX)) continue;
		const aliasPath = path.join(BRIDGE_DIR, entry.name);
		try {
			const target = await fs.readlink(aliasPath);
			const name = entry.name.slice(0, -ALIAS_SUFFIX.length);
			aliasMap.set(target, name);
		} catch {
			// Stale alias
		}
	}

	const sessions: LiveSession[] = [];
	for (const entry of entries) {
		if (!entry.name.endsWith(SOCKET_SUFFIX)) continue;
		const sockPath = path.join(BRIDGE_DIR, entry.name);
		const alive = await isSocketAlive(sockPath);
		if (!alive) {
			// Clean up dead socket
			await fs.unlink(sockPath).catch(() => {});
			continue;
		}
		const sessionId = entry.name.slice(0, -SOCKET_SUFFIX.length);
		const name = aliasMap.get(sockPath);
		sessions.push({ sessionId, name, socketPath: sockPath });
	}

	return sessions;
}

// ============================================================================
// Send message to another session
// ============================================================================

async function sendToSession(targetSocketPath: string, message: string, sender: string): Promise<RpcResponse> {
	return new Promise((resolve, reject) => {
		const conn = net.createConnection(targetSocketPath);
		conn.setEncoding("utf8");

		const timer = setTimeout(() => {
			conn.destroy();
			reject(new Error("Connection timeout"));
		}, 5000);

		let buffer = "";

		conn.on("connect", () => {
			const cmd: RpcSendCommand = { type: "send", message, sender };
			conn.write(JSON.stringify(cmd) + "\n");
		});

		conn.on("data", (chunk) => {
			buffer += chunk;
			const idx = buffer.indexOf("\n");
			if (idx !== -1) {
				clearTimeout(timer);
				const line = buffer.slice(0, idx).trim();
				conn.end();
				try {
					resolve(JSON.parse(line) as RpcResponse);
				} catch {
					reject(new Error("Invalid response"));
				}
			}
		});

		conn.on("error", (err) => {
			clearTimeout(timer);
			reject(err);
		});
	});
}

async function resolveTarget(
	sessionId?: string,
	sessionName?: string,
): Promise<{ socketPath: string; display: string } | { error: string }> {
	if (sessionName) {
		const aliasPath = getAliasPath(sessionName);
		try {
			const target = await fs.readlink(aliasPath);
			const alive = await isSocketAlive(target);
			if (alive) return { socketPath: target, display: sessionName };
		} catch {
			// Fall through to session list scan
		}
		// Scan live sessions for matching name
		const sessions = await getLiveSessions();
		const match = sessions.find((s) => s.name === sessionName);
		if (match) return { socketPath: match.socketPath, display: sessionName };
		return { error: `Session "${sessionName}" not found` };
	}

	if (sessionId) {
		const sockPath = getSocketPath(sessionId);
		const alive = await isSocketAlive(sockPath);
		if (alive) return { socketPath: sockPath, display: sessionId };
		return { error: `Session "${sessionId}" not found or dead` };
	}

	return { error: "Specify sessionId or sessionName" };
}

// ============================================================================
// Cleanup
// ============================================================================

async function cleanup(): Promise<void> {
	if (socketServer) {
		socketServer.close();
		socketServer = null;
	}
	if (socketPath) {
		await fs.unlink(socketPath).catch(() => {});
	}
	if (SESSION_NAME) {
		await removeAlias(SESSION_NAME);
	}
}

// ============================================================================
// MCP Server
// ============================================================================

const server = new McpServer({
	name: "session-bridge",
	version: "0.1.0",
});

// --- Tool: list_sessions ---

server.tool(
	"list_sessions",
	"List live Claude Code / PI sessions that expose a session-bridge socket. " +
		"Returns session IDs and optional names. Use this for discovery.",
	{},
	async () => {
		const sessions = await getLiveSessions();
		if (sessions.length === 0) {
			return {
				content: [{ type: "text", text: "No live sessions found." }],
			};
		}

		const lines = sessions.map((s) => {
			const self = s.sessionId === SESSION_ID ? " (this session)" : "";
			const name = s.name ? ` (${s.name})` : "";
			return `- ${s.sessionId}${name}${self}`;
		});

		return {
			content: [
				{
					type: "text",
					text: `Live sessions:\n${lines.join("\n")}\n\nThis session: ${SESSION_ID}${SESSION_NAME ? ` (${SESSION_NAME})` : ""}`,
				},
			],
		};
	},
);

// --- Tool: send_message ---

server.tool(
	"send_message",
	"Send a message to another session via its session-bridge socket. " +
		"Target by sessionName (alias) or sessionId. " +
		"The message is queued in the target session for retrieval via receive_messages.",
	{
		sessionId: z.string().optional().describe("Target session UUID"),
		sessionName: z.string().optional().describe("Target session name (alias)"),
		message: z.string().describe("Message to send"),
	},
	async ({ sessionId, sessionName, message }) => {
		const target = await resolveTarget(sessionId, sessionName);
		if ("error" in target) {
			return { content: [{ type: "text", text: target.error }], isError: true };
		}

		const sender = SESSION_NAME || SESSION_ID;
		try {
			const resp = await sendToSession(target.socketPath, message, sender);
			if (resp.success) {
				return {
					content: [{ type: "text", text: `Message sent to ${target.display}.` }],
				};
			}
			return {
				content: [{ type: "text", text: `Failed: ${resp.error || "unknown error"}` }],
				isError: true,
			};
		} catch (err) {
			const msg = err instanceof Error ? err.message : String(err);
			return {
				content: [{ type: "text", text: `Connection error: ${msg}` }],
				isError: true,
			};
		}
	},
);

// --- Tool: receive_messages ---

server.tool(
	"receive_messages",
	"Check and retrieve messages that other sessions have sent to this session. " +
		"Messages are returned and cleared from the queue. " +
		"Call this periodically or when you expect a reply from another session.",
	{},
	async () => {
		if (messageQueue.length === 0) {
			return {
				content: [{ type: "text", text: "No pending messages." }],
			};
		}

		const messages = messageQueue.splice(0);
		const formatted = messages.map((m, i) => {
			return `[${i + 1}] from: ${m.from} (${m.timestamp})\n${m.message}`;
		});

		return {
			content: [{ type: "text", text: `${messages.length} message(s) received:\n\n${formatted.join("\n\n---\n\n")}` }],
		};
	},
);

// --- Tool: session_info ---

server.tool(
	"session_info",
	"Get this session's identity — session ID and name. " +
		"Share this with other sessions so they can send messages back.",
	{},
	async () => {
		return {
			content: [
				{
					type: "text",
					text: `Session ID: ${SESSION_ID}\nSession Name: ${SESSION_NAME || "(none)"}\nSocket: ${socketPath || "(not started)"}`,
				},
			],
		};
	},
);

// ============================================================================
// Main
// ============================================================================

async function main(): Promise<void> {
	await ensureBridgeDir();
	startSocketServer();

	if (SESSION_NAME) {
		await createAlias(SESSION_NAME, SESSION_ID);
	}

	// Write session metadata for external discovery
	const metaPath = path.join(BRIDGE_DIR, `${SESSION_ID}.meta`);
	await fs.writeFile(
		metaPath,
		JSON.stringify({
			sessionId: SESSION_ID,
			name: SESSION_NAME || undefined,
			pid: process.pid,
			started: new Date().toISOString(),
		}) + "\n",
	);

	const transport = new StdioServerTransport();
	await server.connect(transport);

	// Cleanup on exit
	const exit = async () => {
		await cleanup();
		await fs.unlink(metaPath).catch(() => {});
		process.exit(0);
	};
	process.on("SIGINT", exit);
	process.on("SIGTERM", exit);
	process.on("SIGHUP", exit);
}

main().catch((err) => {
	console.error(`[session-bridge] Fatal: ${err}`);
	process.exit(1);
});
