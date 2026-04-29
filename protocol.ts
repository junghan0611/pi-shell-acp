/**
 * Shared wire-format constants for pi-shell-acp surfaces that must agree
 * across the root bridge and pi-extension / MCP helper code.
 *
 * Keep this file dependency-free. It is imported by tsc-emitted root modules.
 * A matching protocol.js exists for Node strip-types runtime paths that resolve
 * explicit .js imports against source files.
 */

/**
 * Opening marker for the project-context block inserted by entwurf's
 * `enrichTaskWithProjectContext`. The ACP bridge uses the same marker to
 * detect entwurf-spawned first prompts and remove only the duplicate cwd
 * AGENTS.md section from its own pi-context augment.
 */
export const ENTWURF_PROJECT_CONTEXT_OPEN_TAG = "<project-context";
