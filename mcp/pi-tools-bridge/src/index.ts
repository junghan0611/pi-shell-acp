/**
 * pi-tools-bridge — MCP adapter exposing selected pi-side tools to ACP hosts.
 *
 * Ownership: this adapter lives inside `pi-shell-acp` alongside the rest of the
 * entwurf orchestration surface (pi-extensions/delegate.ts + lib/delegate-core.ts +
 * pi/delegate-targets.json + mcp/session-bridge). See AGENTS.md §Entwurf Orchestration.
 *
 * Historical note: this adapter previously lived in agent-config under the
 * "thin bridge, orchestration elsewhere" boundary. That boundary was superseded
 * during the entwurf migration — delegate/registry/identity-lock/session-bridge
 * all consolidated into pi-shell-acp. agent-config is now a consumer, not the owner.
 *
 * Wiring: registered only via piShellAcpProvider.mcpServers in pi settings.
 * No ambient discovery. The bridge never auto-promotes pi extension tools.
 *
 * Currently exposed tools (scope is deliberately narrow — anything that can live
 * as a local skill should live as a skill, not here):
 *   - send_to_session  → pi control.ts Unix-socket RPC
 *   - list_sessions    — active pi control sockets only (see control.ts getLiveSessions)
 *   - delegate         → pi-extensions/lib/delegate-core (sync mode only)
 *   - delegate_resume  — saved delegate session revival by taskId (sync only)
 *
 * Not here on purpose: semantic memory / session search / knowledge-base search.
 * Those are personal-workflow surfaces and live as Claude Code / Codex skills
 * (the "semantic-memory" skill, which in turn shells out to the user's
 * embedding CLI). Keeping them out of the MCP bridge is what lets pi-shell-acp
 * be a generic public package rather than a reflection of one operator's setup.
 *
 * Phase-2b deferred to a separate design round:
 *   - delegate_status + mode=async — couples with completion-notification contract that MCP
 *     currently has no surface for; design after the resume contract has settled in use.
 *
 * Layer separation (PM-mandated, do not blur):
 *   - list_sessions     = active control-socket discovery (control.ts world)
 *   - delegate_resume   = saved delegate-session revival (delegate.ts world)
 *   These are different lookup layers with different sources of truth. delegate_resume
 *   must NOT depend on a live control socket; the original delegate process may be dead
 *   and that is the normal case.
 *
 * Model routing:
 *   - delegate (spawn) — the Delegate Target Registry is the SSOT. Caller passes
 *     `provider` and/or `model`; resolveDelegateTarget normalizes to an exact
 *     (provider, model) tuple from `pi/delegate-targets.json` and routes via
 *     getRegistryRouting. Bare model auto-resolves only when unambiguous and
 *     not flagged `explicitOnly`.
 *   - delegate_resume — registry is NOT consulted. The session JSONL's recorded
 *     (provider, model) is reused verbatim per Identity Preservation Rule.
 *   - Legacy: PI_DELEGATE_ACP_FOR_CODEX env var still affects the heuristic
 *     getDelegateExplicitExtensions used only by the resume path. Slated for
 *     removal once the matrix routine settles.
 *
 * Principles:
 *   - explicit forwarding, no dynamic tool discovery
 *   - surface errors (isError:true); never silent empty results
 *   - no user-specific paths baked in; env-configurable with safe defaults
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { existsSync } from "node:fs";
import * as fs from "node:fs/promises";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import * as process from "node:process";

import {
  runDelegateSync,
  runDelegateResumeSync,
  formatSyncSummary,
  ensureDelegateOncePerTarget,
  markDelegateTargetUsed,
  resolveGuardTargetKey,
  DEFAULT_DELEGATE_MODEL,
} from "../../../pi-extensions/lib/delegate-core.ts";

const HOME = os.homedir();
const DEFAULT_CONTROL_DIR = path.join(HOME, ".pi", "session-control");
const CONTROL_DIR = process.env.PI_CONTROL_DIR ?? DEFAULT_CONTROL_DIR;
const SOCKET_SUFFIX = ".sock";

const RPC_TIMEOUT_MS = Number(process.env.PI_TOOLS_BRIDGE_RPC_TIMEOUT_MS ?? 5_000);

// ============================================================================
// pi control-socket RPC (for send_to_session)
// ============================================================================

interface RpcResponse {
  type: "response";
  command: string;
  success: boolean;
  error?: string;
  data?: unknown;
}

async function resolveControlSocket(target: string): Promise<string> {
  try {
    await fs.access(CONTROL_DIR);
  } catch {
    throw new Error(`pi control dir not found at ${CONTROL_DIR}. Target pi needs --session-control.`);
  }

  const direct = target.endsWith(SOCKET_SUFFIX)
    ? path.join(CONTROL_DIR, target)
    : path.join(CONTROL_DIR, `${target}${SOCKET_SUFFIX}`);
  if (existsSync(direct)) return direct;

  const entries = await fs.readdir(CONTROL_DIR).catch(() => [] as string[]);
  for (const name of entries) {
    if (name === target || name === `${target}${SOCKET_SUFFIX}`) {
      return path.join(CONTROL_DIR, name);
    }
  }
  throw new Error(`No pi control socket for "${target}" under ${CONTROL_DIR}`);
}

function rpcCall(socketPath: string, payload: Record<string, unknown>): Promise<RpcResponse> {
  return new Promise((resolve, reject) => {
    const conn = net.createConnection(socketPath);
    let buffer = "";
    const timer = setTimeout(() => {
      conn.destroy();
      reject(new Error(`RPC timeout (${RPC_TIMEOUT_MS}ms) to ${socketPath}`));
    }, RPC_TIMEOUT_MS);
    conn.setEncoding("utf8");
    conn.on("connect", () => {
      conn.write(`${JSON.stringify(payload)}\n`);
    });
    conn.on("data", (chunk) => {
      buffer += chunk;
      const nl = buffer.indexOf("\n");
      if (nl !== -1) {
        clearTimeout(timer);
        const line = buffer.slice(0, nl).trim();
        conn.end();
        try {
          resolve(JSON.parse(line) as RpcResponse);
        } catch {
          reject(new Error(`Invalid RPC response: ${line.slice(0, 200)}`));
        }
      }
    });
    conn.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

// ============================================================================
// Live control-socket discovery (for list_sessions)
//
// PM-mandated layer separation: this is the *active* control-socket world
// (~/.pi/session-control/*.sock). It is NOT used by delegate_resume — that
// layer lives over saved delegate session JSONL files in ~/.pi/agent/sessions
// and must not depend on a live socket.
// ============================================================================

interface LiveSessionInfo {
  sessionId: string;
  name?: string;
  aliases: string[];
  socketPath: string;
}

const SOCKET_PROBE_TIMEOUT_MS = 300;

async function isSocketAlive(socketPath: string): Promise<boolean> {
  return new Promise((resolve) => {
    const conn = net.createConnection(socketPath);
    const timer = setTimeout(() => {
      conn.destroy();
      resolve(false);
    }, SOCKET_PROBE_TIMEOUT_MS);
    conn.once("connect", () => {
      clearTimeout(timer);
      conn.end();
      resolve(true);
    });
    conn.once("error", () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
}

async function readAliasMap(): Promise<Map<string, string[]>> {
  const aliasMap = new Map<string, string[]>();
  const entries = await fs.readdir(CONTROL_DIR, { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    if (!entry.isSymbolicLink()) continue;
    if (!entry.name.endsWith(".alias")) continue;
    const aliasPath = path.join(CONTROL_DIR, entry.name);
    let target: string;
    try {
      target = await fs.readlink(aliasPath);
    } catch {
      continue;
    }
    const resolvedTarget = path.resolve(CONTROL_DIR, target);
    const aliasName = entry.name.slice(0, -".alias".length);
    const list = aliasMap.get(resolvedTarget);
    if (list) list.push(aliasName);
    else aliasMap.set(resolvedTarget, [aliasName]);
  }
  return aliasMap;
}

async function getLiveSessions(): Promise<LiveSessionInfo[]> {
  try {
    await fs.access(CONTROL_DIR);
  } catch {
    return [];
  }
  const entries = await fs.readdir(CONTROL_DIR, { withFileTypes: true }).catch(() => []);
  const aliasMap = await readAliasMap();
  const sessions: LiveSessionInfo[] = [];

  for (const entry of entries) {
    if (!entry.name.endsWith(SOCKET_SUFFIX)) continue;
    if (entry.isSymbolicLink()) continue;
    const socketPath = path.join(CONTROL_DIR, entry.name);
    if (!(await isSocketAlive(socketPath))) continue;
    const sessionId = entry.name.slice(0, -SOCKET_SUFFIX.length);
    if (!sessionId || sessionId.includes("/")) continue;
    const aliases = aliasMap.get(socketPath) ?? [];
    sessions.push({ sessionId, name: aliases[0], aliases, socketPath });
  }

  sessions.sort((a, b) => (a.name ?? a.sessionId).localeCompare(b.name ?? b.sessionId));
  return sessions;
}

// ============================================================================
// Helpers
// ============================================================================

function textOk(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

function textErr(msg: string) {
  return { content: [{ type: "text" as const, text: msg }], isError: true };
}

// ============================================================================
// MCP server
// ============================================================================

const server = new McpServer({ name: "pi-tools-bridge", version: "0.1.0" });

server.tool(
  "send_to_session",
  "Send a message to another running pi session via its control socket. " +
    "Target by sessionId or alias name. Requires the target pi to have been launched with --session-control. " +
    "Use list_sessions first if you need to discover what targets are reachable. " +
    "Messaging discipline — 'Send is throw, not wait': this bridge surface is " +
    "fire-and-forget on purpose (no wait_until parameter exposed). Delivery is " +
    "confirmed, a full turn result is not. If you need the target's answer, " +
    "let the target reply with its own send_to_session addressed to your " +
    "sender_info. If you need a result the *caller* owns (not a notification), " +
    "the correct surface is delegate(mode=async) + delegate_resume, not this tool.",
  {
    target: z.string().min(1).describe("Session id or alias registered under pi control dir"),
    message: z.string().min(1).describe("Message text to deliver"),
    mode: z.enum(["steer", "follow_up"]).optional().describe("Default follow_up"),
  },
  async ({ target, message, mode }) => {
    try {
      const sock = await resolveControlSocket(target);
      const resp = await rpcCall(sock, { type: "send", message, mode: mode ?? "follow_up" });
      if (!resp.success) {
        return textErr(`send_to_session failed: ${resp.error ?? "unknown"}`);
      }
      return textOk(`delivered to ${target}`);
    } catch (err) {
      return textErr(`send_to_session error: ${err instanceof Error ? err.message : String(err)}`);
    }
  },
);

server.tool(
  "list_sessions",
  "List active pi sessions that currently expose a control socket (i.e. were launched with " +
    "--session-control). Returns sessionId + optional alias name + socket path for each live " +
    "session. Pair with send_to_session to address a specific peer. " +
    "Note: this is the *active* session world. It is NOT the way to discover saved delegate " +
    "sessions — those live as JSONL files under ~/.pi/agent/sessions and are addressed by " +
    "taskId via delegate_resume; their original processes may already have exited.",
  {},
  async () => {
    try {
      const sessions = await getLiveSessions();
      const lines = sessions.length
        ? sessions.map((s) => {
            const name = s.name ? ` (${s.name})` : "";
            return `- ${s.sessionId}${name}`;
          })
        : ["(no live pi sessions with --session-control found)"];
      const payload = {
        controlDir: CONTROL_DIR,
        count: sessions.length,
        sessions: sessions.map((s) => ({
          sessionId: s.sessionId,
          name: s.name,
          aliases: s.aliases,
          socketPath: s.socketPath,
        })),
      };
      return textOk(`${lines.join("\n")}\n\n${JSON.stringify(payload)}`);
    } catch (err) {
      return textErr(`list_sessions error: ${err instanceof Error ? err.message : String(err)}`);
    }
  },
);

server.tool(
  "delegate",
  "Delegate a task to an independent pi agent process (sync mode). " +
    "Spawns a fresh pi -p run, waits for completion, returns stdout + turns + cost. Use for " +
    "isolated work (different cwd, different machine via SSH, or resource-intensive jobs) " +
    "where you want the result inline. " +
    "The result includes a Task ID — pass it to delegate_resume to continue this delegate's " +
    "saved session with a follow-up prompt. " +
    "Delegate Target Registry (narrow door, see pi-shell-acp/AGENTS.md §Entwurf Orchestration): every spawn must " +
    "resolve to an exact (provider, model) pair listed in ~/.pi/agent/delegate-targets.json. " +
    "Caller may pass either a qualified `model` (provider/name) or both `provider` and `model` " +
    "fields. Bare model is accepted only when unambiguous — e.g. `claude-sonnet-4-6` resolves " +
    "to pi-shell-acp; bare `gpt-5.4` resolves to native openai-codex (the pi-shell-acp/gpt-5.4 " +
    "entry is marked explicitOnly and skipped from auto-resolution). " +
    "Async spawn + delegate_status are not exposed here yet (deferred to a separate design round). " +
    `Default model when omitted: ${DEFAULT_DELEGATE_MODEL}.`,
  {
    task: z.string().min(1).describe("The task to delegate (plain text prompt)"),
    host: z.string().min(1).optional().describe("SSH host name (omit or 'local' for local)"),
    cwd: z.string().min(1).optional().describe("Working directory for the delegate"),
    provider: z
      .string()
      .min(1)
      .optional()
      .describe(
        "Provider id (e.g. 'pi-shell-acp', 'openai-codex'). Pair with `model` to disambiguate. " +
          "Optional if `model` is qualified ('provider/name') or unambiguous in the registry.",
      ),
    model: z
      .string()
      .min(1)
      .optional()
      .describe(
        "Model id. Either qualified ('pi-shell-acp/claude-sonnet-4-6') or bare ('claude-sonnet-4-6'). " +
          "Bare names must resolve unambiguously in the registry; otherwise pass `provider`.",
      ),
  },
  async ({ task, host, cwd, provider, model }) => {
    try {
      const guardSessionId = process.pid.toString();
      const guardTargetKey = resolveGuardTargetKey(provider, model);
      ensureDelegateOncePerTarget(guardSessionId, guardTargetKey);

      const result = await runDelegateSync(task, { host, cwd, provider, model });
      markDelegateTargetUsed(guardSessionId, guardTargetKey);
      const text = formatSyncSummary(result);
      return result.exitCode === 0 ? textOk(text) : textErr(text);
    } catch (err) {
      return textErr(`delegate error: ${err instanceof Error ? err.message : String(err)}`);
    }
  },
);

server.tool(
  "delegate_resume",
  "Resume a saved delegate session by taskId, with a follow-up prompt (sync mode only). " +
    "The taskId comes from a prior delegate call's output (look for 'Task ID: <id>' in the " +
    "summary). The bridge looks up the saved session JSONL under ~/.pi/agent/sessions and " +
    "spawns `pi --session <file>` with the new prompt; pi appends to the same file. " +
    "Important: this works on the saved session file. The original delegate process may have " +
    "exited and is NOT required to be alive — delegate_resume does NOT consult control sockets " +
    "or list_sessions. The two surfaces are separate by design (active sessions vs saved " +
    "delegate sessions). " +
    "Routing on resume comes entirely from the saved session JSONL (provider + model " +
    "as recorded). The Delegate Target Registry that gates spawn is NOT consulted here. " +
    "Identity Preservation Rule: this tool intentionally does NOT accept a `model` " +
    "parameter. The model is locked to whatever the saved session recorded at first " +
    "spawn — resuming under a different model is treated as splicing a new identity " +
    "onto someone else's transcript and is refused at the API layer. host and cwd may " +
    "change (execution environment is not identity); model may not. " +
    "Async resume is intentionally not exposed on this MCP surface; " +
    "the pi-native delegate_resume exposes mode=\"async\" for long-running resumes " +
    "with followUp delivery into the parent session (see Phase 0.5 in AGENTS.md).",
  {
    taskId: z
      .string()
      .min(1)
      .describe("Task ID from a prior delegate result (e.g. '3f9a8c1b')"),
    prompt: z.string().min(1).describe("Follow-up prompt to send into the resumed session"),
    host: z
      .string()
      .min(1)
      .optional()
      .describe(
        "SSH host name if the original delegate ran remote (default: 'local'). " +
          "NOTE: remote SSH path is implemented but not yet end-to-end verified — " +
          "use with care until the remote rollout phase.",
      ),
    cwd: z
      .string()
      .min(1)
      .optional()
      .describe("Working directory override for the resume spawn"),
  },
  async ({ taskId, prompt, host, cwd }) => {
    try {
      const result = await runDelegateResumeSync(taskId, prompt, { host, cwd });
      const text = formatSyncSummary(result);
      return result.exitCode === 0 ? textOk(text) : textErr(text);
    } catch (err) {
      return textErr(`delegate_resume error: ${err instanceof Error ? err.message : String(err)}`);
    }
  },
);

// ============================================================================
// Main
// ============================================================================

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error(`[pi-tools-bridge] fatal: ${err instanceof Error ? err.stack : err}`);
  process.exit(1);
});
