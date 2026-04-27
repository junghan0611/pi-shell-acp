# Changelog

All notable changes to this project will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The repo uses semver.

## Unreleased

## 0.2.0 — 2026-04-27

Initial public release.

* ACP bridge providing Claude Code and Codex backends to pi-coding-agent.
* `piShellAcpProvider.skillPlugins` — inject local skill plugins through the Claude Agent SDK's `plugins:[{type:"local", path}]` channel (works around SDK isolation `settingSources: []`).
* `pi-tools-bridge` MCP server — exposes pi-side delegate/control surface to Claude/Codex sessions.
* Entwurf orchestration surface — async delegate, resume, cross-session messaging via control sockets.
* Pinned `@zed-industries/codex-acp@0.12.0` with full-access sandbox/approval default; `@agentclientprotocol/claude-agent-acp@0.31.0` + ACP SDK `0.20.0`.
