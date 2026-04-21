# VERIFY.md

`pi-shell-acp` 수동 검증 가이드.

이 문서는 **메트릭스 문서가 아니라 작업 문서**다.
스크립트가 깨져도, 에이전트가 이 순서대로 직접 실행하고 결과를 읽으면 다음을 바로 판별할 수 있어야 한다.

- ACP가 싱글턴에서 멍청한지 아닌지
- 멀티턴 세션이 진짜 이어지는지
- cross-process continuity가 되는지
- bridge invariant가 안 새는지
- tool call / event mapping이 보이는지
- 프로세스/캐시가 쓰레기처럼 남지 않는지
- pi session 기록이 나중에 andenken 임베딩의 공통 기억축으로 쓸 만한지

---

## 0. 품질 기준

우리가 원하는 것은 단순한 "Claude Code를 부른다"가 아니다.

목표는 다음과 같다.

1. **agent-shell 수준의 session continuity**
   - 텍스트 뭉치 재투척이 아니라 ACP session resume/load/new로 이어질 것
2. **pi 하네스 의미론 유지**
   - pi session 파일, transcript, memory pipeline은 그대로 공통 축일 것
3. **restart-safe**
   - 프로세스가 바뀌어도 같은 pi session은 같은 ACP session으로 최대한 이어질 것
4. **thin bridge 유지**
   - 여기서 두 번째 하네스를 만들지 말 것
5. **capability exposure boundary 명시**
   - pi custom tool / user MCP 가시성은 `piShellAcpProvider.mcpServers` 설정에 의해서만 결정된다
   - 자동 `~/.mcp.json` 로드는 하지 않는다
6. **운영 위생 유지**
   - orphan subprocess, 쓰레기 persisted session 남발 금지

---

## 1. 준비

### 1.1 변수

```bash
export REPO_DIR=/home/junghan/repos/gh/pi-shell-acp
export PROJECT_DIR=/home/junghan/repos/gh/agent-config
export CACHE_DIR=$HOME/.pi/agent/cache/pi-shell-acp/sessions
mkdir -p "$CACHE_DIR"
```

### 1.2 설치/스모크

실제 소비자 프로젝트에서 확인하려면:

```bash
cd "$REPO_DIR"
./run.sh setup "$PROJECT_DIR"
```

빠른 재검증:

```bash
cd "$REPO_DIR"
npm run typecheck
npm run check-mcp            # pi-facing MCP normalization pure-logic gate (no Claude/ACP subprocess)
./run.sh smoke "$PROJECT_DIR"
```

기대 결과:
- typecheck 통과
- check-mcp 통과 (`[check-mcp] N assertions ok`)
- `--list-models pi-shell-acp` 성공
- bridge prompt smoke 성공

---

## 2. 기존 벤치 재사용 — 품질/성능의 큰 이상 유무만 본다

이 단계는 **세션 무결성 검증이 아니라 거친 parity 체크**다.

```bash
cd "$REPO_DIR"
PI_BENCH_SUITE=quick ./bench.sh "$PROJECT_DIR"
PI_BENCH_SUITE=full ./bench.sh "$PROJECT_DIR"
```

볼 것:
- direct 대비 ACP가 전반적으로 바보처럼 굴지 않는가
- read/bash/search/git/sysprompt가 대체로 정상인가
- 응답이 완전히 엉뚱한 방향으로 튀지 않는가

주의:
- exact string match는 보지 않는다
- **의미 수준 parity**를 본다
- 이 벤치만 통과해도 session continuity는 증명되지 않는다

---

## 3. 싱글턴 검증 — 가장 먼저 깨지는 회귀 포인트

### 3.1 SessionStart hook 회귀 확인

`index.ts`의 `extractPromptBlocks()` 회귀를 가장 먼저 본다.

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p 'ok만 답하세요'
```

기대 결과:
- `ok` 또는 그에 준하는 매우 짧은 응답
- `device=...`, `time_kst=...` 같은 hook 메시지를 주 프롬프트로 오인하지 않을 것

깨지면 의심할 곳:
- `index.ts`의 `extractPromptBlocks()`
- pi hook message가 trailing user message로 들어오는 구조

### 3.2 기본 도구 호출 확인

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p '현재 날짜와 시간을 알려주세요. date 명령어를 사용하세요.'
```

기대 결과:
- date 실행 흔적이 보이거나, 적어도 tool 사용 기반 응답일 것
- event-mapper가 붙은 환경이면 `[tool:start]`, `[tool:done]` 류 notice가 관찰될 수 있음

---

## 4. 멀티턴 검증 — 같은 pi session 파일에서 이어지는가

이 단계부터가 중요하다.

```bash
export SESSION_FILE=$(mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl)
echo "$SESSION_FILE"
```

### 4.1 1턴: 사실 주입

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '이 세션의 암호문은 blue-otter-913 입니다. 설명 없이 READY만 답하세요.'
```

기대 결과:
- `READY`

### 4.2 2턴: 기억 확인

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '방금 내가 준 암호문만 그대로 답하세요.'
```

기대 결과:
- `blue-otter-913`

### 4.3 3턴: 갱신 확인

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '이제 암호문을 red-otter-204로 바꾸자. CHANGED만 답하세요.'
```

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '현재 암호문만 답하세요.'
```

기대 결과:
- 마지막 응답이 `red-otter-204`

판정 포인트:
- 텍스트 뭉치 재투척 없이 세션이 자연스럽게 이어지는가
- 이전 턴의 상태 갱신이 반영되는가

---

## 5. cross-process continuity — 프로세스가 바뀌어도 이어지는가

사실 위 멀티턴 테스트 자체가 `pi -p` 반복 호출이므로 **cross-process** 성격을 이미 갖는다.
하지만 여기서는 persisted mapping과 cache까지 같이 본다.

### 5.1 캐시 전후 관찰

```bash
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

세션 파일을 쓴 뒤 다시:

```bash
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

기대 결과:
- `pi:<sessionId>`에 대응하는 persisted session record가 생긴다
- pi 프로세스 종료 후에도 record는 남아 있다
- 같은 `SESSION_FILE`로 다음 호출 시 continuity가 유지된다

### 5.2 README 시나리오 그대로 검증

```bash
export SESSION_FILE=$(mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl)
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'Remember this exact secret token for later: test-token-123. Reply only READY.'
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'What was the secret token? Reply with the token only.'
```

기대 결과:
- 첫 번째 응답 `READY`
- 두 번째 응답 `test-token-123`

---

## 6. persistence boundary — `cwd:` 세션은 절대 영속화하지 않는다

이 리포의 핵심 불변식이다.

`pi` 경유에서는 항상 `sessionId`가 있는 경우가 많으므로, 이 검증은 bridge API를 직접 두드려도 된다.

실행 전 파일 수 기록:

```bash
BEFORE=$(find "$CACHE_DIR" -maxdepth 1 -type f | wc -l)
echo "$BEFORE"
```

직접 호출:

```bash
cd "$REPO_DIR"
node --input-type=module <<'EOF'
import { ensureBridgeSession, closeBridgeSession, normalizeMcpServers } from './acp-bridge.ts';

const cwd = process.cwd();
const key = `cwd:${cwd}`;
const { hash: mcpServersHash } = normalizeMcpServers(undefined);
const session = await ensureBridgeSession({
  sessionKey: key,
  cwd,
  modelId: 'claude-sonnet-4-6',
  systemPromptAppend: undefined,
  settingSources: ['user'],
  strictMcpConfig: false,
  mcpServers: [],
  bridgeConfigSignature: JSON.stringify({ appendSystemPrompt: false, settingSources: ['user'], strictMcpConfig: false, mcpServersHash }),
  contextMessageSignatures: ['verify:cwd-boundary'],
});
await closeBridgeSession(key, { closeRemote: true, invalidatePersisted: true });
console.log('cwd boundary check done');
EOF
```

실행 후 파일 수 재확인:

```bash
AFTER=$(find "$CACHE_DIR" -maxdepth 1 -type f | wc -l)
echo "$AFTER"
```

기대 결과:
- `AFTER == BEFORE`
- `cwd:` 기반 record가 새로 생기지 않는다

깨지면 의심할 곳:
- `isPersistableSessionKey()`
- `persistBridgeSessionRecord()`
- `deletePersistedSessionRecord()`

---

## 7. ordinary shutdown semantics — 프로세스 종료는 mapping을 보존해야 한다

일반 종료 후 persisted mapping이 살아 있어야 다음 pi 프로세스가 이어받을 수 있다.

### 7.1 종료 전후 캐시 확인

```bash
export SESSION_FILE=$(mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl)
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '세션 보존 테스트입니다. READY만 답하세요.'
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

이후 같은 세션 파일로 다시:

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '직전 테스트가 무엇이었는지 한 줄로 답하세요.'
```

기대 결과:
- 직전 대화 맥락을 이어간다
- 일반 종료가 곧 invalidate를 의미하지 않는다

주의:
- 현재는 `resume` vs `load` vs `new` 중 무엇을 탔는지 외부에서 바로 보기 어렵다
- 이 문서 단계에서는 **결과 continuity**를 먼저 본다
- bootstrap path 관찰성은 후속 개선 포인트다

---

## 8. tool call / event mapping 검증

### 8.1 read

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p 'README.md 첫 3줄을 읽고 한 줄로 요약해줘.'
```

### 8.2 grep/search

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p '이 프로젝트에서 extractPromptBlocks 함수가 정의된 파일을 grep으로 찾아줘.'
```

### 8.3 bash/git

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p '현재 git 브랜치와 최근 커밋 메시지 1개를 알려줘.'
```

기대 결과:
- read/search/bash 성격의 도구 사용이 일관되다
- 필요한 경우 tool notice가 자연스럽게 보인다
- 최종 응답이 tool output을 왜곡하지 않는다

관찰 포인트:
- `event-mapper.ts`가 text/thinking/tool notice를 적절히 흘려주는가
- permission event가 있을 경우 이상한 노이즈가 아니라 관찰 가능한 수준으로만 보이는가

### 8.4 pi custom tool visibility 확인 — 현재 핵심 의심 지점

여기서 보는 것은 `bash`, `read`, `grep` 같은 Claude Code/native tool이 아니라,
**pi가 원래 LLM에게 주던 custom tool이 ACP 경유 시에도 보이는가** 다.

대표 예시:
- `delegate`
- `delegate_status`
- `session_search`
- `knowledge_search`

검증 프롬프트 예시:

```bash
cd "$REPO_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p 'delegate 툴이 보이면, 아주 짧은 sync 위임을 1회 실행해줘. 보이지 않으면 정확히 "delegate tool not visible"이라고만 답해.'
```

**현재 설계 기준 Pass:**
- 정확히 `delegate tool not visible`

**Fail:**
- 없는 tool을 있는 척 hallucination
- `bash`로 `pi`를 재귀 호출해서 delegate를 흉내냄
- "대신 비슷하게 해봤다" 식으로 boundary를 흐림

```bash
cd "$REPO_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p 'session_search 또는 knowledge_search 툴이 보이면 각각 가능 여부를 짧게 말해줘. 둘 다 안 보이면 정확히 "pi custom tools not visible"이라고만 답해.'
```

**현재 설계 기준 Pass:**
- 정확히 `pi custom tools not visible`

**Fail:**
- tool visibility가 없는데 있는 척 설명
- native tool만으로 얼버무리며 넘어감
- recursive `pi` 호출로 우회

현재 코드 기준 의심점:
- `acp-bridge.ts`의 `newSession/loadSession/resumeSession` 호출은 이제 `params.mcpServers`를 전달한다
- 그 목록은 `piShellAcpProvider.mcpServers` 설정(§8.5)에서만 온다 — 자동 `~/.mcp.json` 로드 없음
- `buildSessionMeta()`가 Claude 쪽 `tools: { type: "preset", preset: "claude_code" }`를 넘김

즉 현재 기본값(설정 없음)에서는 **Claude Code native tool은 보이지만 pi custom tool은 안 보이는 상태**가 정상이다.

이 boundary 판정은 Claude뿐 아니라 Codex에도 동일하게 적용한다. 다만 MCP tool 이름 표기는 백엔드별로 약간 다를 수 있다.
- Claude 예: `mcp__pi-tools-bridge__session_search`
- Codex 예: `mcp__pi_tools_bridge__session_search`

따라서 검증 기준은 **브리지 이름(`pi-tools-bridge` / `pi_tools_bridge`) + tool suffix**가 함께 보이는지로 잡는 편이 안전하다.

이 항목의 의미:
- 기본값은 "Claude-native only" 로 선언됐다
- pi 하네스 parity는 **별도 MCP adapter**를 만들어 `piShellAcpProvider.mcpServers` 로 주입할 때만 생긴다
- bridge는 그것을 pass-through만 할 뿐, repo 안에서 승격 로직을 갖지 않는다

이 테스트에서 실패하면:
- 억지로 Claude 안에서 `bash`로 `pi`를 재귀 호출하게 하지 말 것
- 먼저 **현재 bridge의 tool exposure boundary를 명확히 판정**할 것
- 필요하면 `piShellAcpProvider.mcpServers`에 external MCP adapter를 명시적으로 추가해 §8.5로 검증

### 8.5 pi-facing MCP injection 가시성 — 하나의 명시 설정이 resume/load/new 세 경로에 동일하게 반영되는가

`pi-shell-acp`의 MCP 책임은 단 하나다: `piShellAcpProvider.mcpServers`에 등록된 pi-facing MCP를 모든 ACP 세션 요청(`newSession` / `resumeSession` / `loadSession`)에 동일하게 주입한다. 이 테스트가 검증하는 것은 "범용 MCP 매니저"가 아니라 "pi가 정말 보이길 원하는 MCP 하나가 세 경로에서 일관되게 보이는가"이다.

실험용 pi-facing MCP 하나(예: `session-bridge`)를 프로젝트 settings에 등록한다. 예를 들어 `<PROJECT>/.pi/settings.json`:

```jsonc
{
  "piShellAcpProvider": {
    "mcpServers": {
      "session-bridge": {
        "command": "node",
        "args": ["/home/junghan/repos/gh/agent-config/mcp/session-bridge/server.js"]
      }
    }
  }
}
```

그 다음 같은 프로젝트에서:

```bash
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p '지금 보이는 MCP 서버 이름을 쉼표로만 나열해. 설명 없이.'
```

**Pass 기준:**
- 설정에 등록된 MCP(예: `session-bridge`)가 응답 목록에 들어 있다
- 등록하지 않은 MCP는 보이지 않는다 (자동 `~/.mcp.json` 로드 없음을 확인)

**resume/load/new 일관성:**

같은 `SESSION_FILE`로 여러 턴을 돌려도 visibility가 바뀌면 안 된다.

```bash
export SESSION_FILE=$(mktemp /tmp/pi-shell-acp-mcp-XXXXXX.jsonl)
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '지금 보이는 MCP 서버 이름을 쉼표로만 나열해.'
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '다시 한 번 MCP 서버 이름만 나열해.'
```

Pass: 두 응답의 서버 목록이 동일.
Fail: 1턴에만 보이거나, 2턴에서 달라짐 → session fingerprint 또는 세 경로 주입 통일 문제.

**설정 변경 → 세션 무효화:**

`piShellAcpProvider.mcpServers`를 바꾸면 `bridgeConfigSignature`가 달라져 persisted session이 호환 실패하고 새 세션으로 넘어가야 한다.

```bash
# settings.json에서 mcpServers 항목 추가/제거 후
cd "$PROJECT_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'MCP 서버 이름만 나열해.'
```

Pass: 새 설정이 즉시 반영됨 (stale capability 없음).

현재 운영 기준에서는 이 visibility 확인을 **Claude + Codex 둘 다** 돌리고, 최소 1개의 bridged MCP tool 호출도 실제로 통과시킨다. 가장 안정적인 자동화 경로는 `send_to_session` negative-path 호출이다. 존재하지 않는 target에 대해 `No pi control socket ...` 오류가 surface되면, `ACP host → MCP bridge → pi-side RPC` 호출 경로가 실제로 살아 있음을 의미한다.

---

## 9. 시나리오 테스트 — 실제 작업자처럼 써본다

이 단계는 synthetic benchmark보다 중요하다.

### 9.1 현재 리포 자기이해

```bash
cd "$REPO_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p 'AGENTS.md와 README.md를 읽고, 이 리포의 현재 불변식만 7줄 이내로 요약해줘. 특히 provider/model/settings 이름, session continuity 경계, bootstrap 순서, 하지 말아야 할 것을 포함해.'
```

### 9.2 구조 설명

```bash
cd "$REPO_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p 'acp-bridge.ts와 index.ts를 기준으로, 지금 pi-shell-acp의 핵심 구조를 설명해줘. agent-shell을 semantic reference로 보되, 우리가 일부러 가져오지 않은 것까지 함께 말해줘.'
```

### 9.3 다음 고도화 제안

```bash
cd "$REPO_DIR"
pi -e "$REPO_DIR" --model pi-shell-acp/claude-sonnet-4-6 -p '현재 상태에서 다음 고도화 포인트를 3개만 제안해줘. 단, 얇은 bridge 원칙을 깨지 않는 것만. 각 항목마다 왜 필요한지, 어느 파일을 건드리는지, 검증 방법을 붙여줘.'
```

기대 결과:
- 대답이 얇은 bridge 철학을 유지한다
- 자기 repo 문맥 이해가 된다
- hallucination 없이 실제 파일에 근거한다

---

## 10. 프로세스/캐시 위생 검증

### 10.1 사전 관찰

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

### 10.2 여러 테스트 후 재관찰

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

기대 결과:
- 테스트를 많이 돌렸다고 `claude-agent-acp` 프로세스가 무한 증식하지 않는다
- cache record가 의미 없이 폭증하지 않는다
- `pi:<sessionId>`와 무관한 쓰레기 record가 생기지 않는다

주의:
- 캐시 파일 수가 늘어나는 것 자체는 새 세션을 만들면 자연스러울 수 있다
- 중요한 것은 **boundary가 지켜지는가** 와 **orphan가 남는가** 다

---

## 11. pi session 기록 확인 — andenken용 공통 기억축으로 쓸 수 있는가

핵심은 ACP를 써도 결국 **pi 세션 파일이 공통 기록 원천**으로 유지되는가다.

세션 파일을 하나 잡고:

```bash
export SESSION_FILE=$(mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl)
cd "$REPO_DIR"
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p 'AGENTS.md를 읽고 이 리포의 핵심 원칙 3개만 답해.'
pi -e "$REPO_DIR" --session "$SESSION_FILE" --model pi-shell-acp/claude-sonnet-4-6 -p '방금 답변을 한 줄로 다시 요약해.'
```

그 다음 세션 파일을 본다:

```bash
wc -l "$SESSION_FILE"
tail -n 40 "$SESSION_FILE"
```

확인할 것:
- user / assistant turn이 pi session에 정상적으로 누적되는가
- ACP 경유라고 해서 transcript가 깨지거나 텅 비지 않는가
- 나중에 임베딩할 때 최소한의 세션 의미론이 남아 있는가

중요:
- 여기서 보는 것은 ACP 내부 transcript가 아니라 **pi 쪽 기록축** 이다
- 우리가 지키려는 것은 “Claude는 ACP로, 기억은 pi 축으로”의 공존이다

---

## 12. 아직 비어있는 검증 포인트

아래는 현재 문서화는 해두되, 아직 관찰성/자동화가 덜 된 부분이다.

1. 실제 bootstrap path가 `resume`인지 `load`인지 `new`인지 외부에서 즉시 보이게 하는 것
2. persisted session incompatibility가 발생했을 때 invalidate 이유를 operator가 빠르게 읽는 것
3. ~~model switch 시 `unstable_setSessionModel` 경로 vs 새 세션 fallback 경로를 명확히 관찰하는 것~~ — §12.3 참조
4. ~~cancel/abort 시 bridge와 child process가 얼마나 깔끔하게 정리되는지 보는 것~~ — §12.4 참조
5. 장시간 세션에서 tool notice / thinking / text block이 누적될 때 stream shape가 안정적인지 보는 것
6. delegate-style continuity (partial, §12.5 참조) — Claude 는 real delegate-style e2e, Codex 는 shape-equivalent only. 진짜 Codex delegate orchestration parity 는 agent-config/delegate-core 쪽 follow-up 이 필요하다.

즉, 이 문서는 완료 선언 문서가 아니라 **다음 개선 포인트를 드러내는 운영 문서**다.

### 12.3 model switch observability (green)

`unstable_setSessionModel` 경로는 operator가 stderr에서 바로 읽을 수 있도록 단일 diagnostic 라인을 흘린다. bootstrap/cancel 라인과 같은 `key=value` 포맷이다.

```text
[pi-shell-acp:model-switch] path=bootstrap|reuse outcome=applied|unsupported|failed sessionKey=... backend=... acpSessionId=... fromModel=... toModel=... reason=... fallback=new_session|none
```

의미 (observability가 아니라 실제 규칙):

- `path=bootstrap` — new/resume/load 직후 `enforceRequestedSessionModel` 경로. `requestedModelId`가 있으면 무조건 enforcement를 시도한다. `resolveModelIdFromSessionResponse()`가 backend가 currentModelId를 돌려주지 않는 경우 requested를 fallback으로 쓰므로 "current == requested"로 판정해 건너뛰면 안 된다. 여기서는 `outcome=failed`는 지금도 그대로 throw되어 bootstrap 전체가 실패한다 (fail-fast 유지).
- `path=reuse` — `ensureBridgeSession`의 compatible existing session에서 `modelId`가 바뀐 경우. 
  - `outcome=applied`: `setModel` 성공, 같은 세션 유지
  - `outcome=unsupported fallback=new_session`: `setModel` not a function → `closeBridgeSession` + `startNewBridgeSession`
  - `outcome=failed fallback=new_session reason=...`: `setModel` throw → `closeBridgeSession` + `startNewBridgeSession`
  - 두 fallback 경로는 직후 `[pi-shell-acp:bootstrap] path=new`로 이어진다.

Smoke:

```bash
./run.sh smoke-model-switch /home/junghan/repos/gh/agent-config
```

Pass 기준 (backend별로 Claude/Codex 모두):

- `[pi-shell-acp:model-switch] path=reuse outcome=applied` 라인 존재
- `[pi-shell-acp:model-switch] path=reuse outcome=unsupported fallback=new_session` 라인 존재
- `[pi-shell-acp:model-switch] path=reuse outcome=failed fallback=new_session reason=...` 라인 존재
- 두 fallback 뒤에 `[pi-shell-acp:bootstrap] path=new`가 한 번씩 더 찍혀 새 세션 재부팅이 실제 일어남
- fallback 후 새 세션으로 짧은 한 턴 프롬프트가 `stopReason=end_turn`으로 성공

bootstrap 분기는 로그만 추가되어 있고, deterministic smoke는 reuse 3분기 중심이다. bootstrap `unsupported` / `failed`는 현재 운영 기본으로 보수적으로 유지한다 (unsupported는 skip, failed는 throw).

운영 기본은 resilient (reuse는 stderr diagnostic + new-session fallback, pi 세션은 계속), smoke는 fail-fast (하나라도 어기면 전체 실패).

### 12.4 cancel / abort cleanup observability (green)

cancel/abort 경로는 operator가 stderr에서 바로 읽을 수 있도록 3종 diagnostic 라인을 흘린다. bootstrap 라인과 같은 `key=value` 포맷이다.

```text
[pi-shell-acp:cancel]      sessionKey=... backend=... acpSessionId=... outcome=dispatched|unsupported|failed reason=...
[pi-shell-acp:shutdown]    sessionKey=... backend=... acpSessionId=... closeRemote=... invalidatePersisted=... childPid=... closedRemote=ok|fail|skip childExit=exited|timeout
[pi-shell-acp:orphan-kill] sessionKey=... backend=... pid=... signal=SIGKILL
```

Cleanup invariant (observability가 아니라 실제 규칙):

- `onAbort`는 `cancelActivePrompt()`만 호출하고, bridge/child는 파괴하지 않는다 (abort 후 세션 재사용 가능해야 함)
- `streamShellAcp` catch block에서 `stopReason === "error"`인 경우(= user abort가 아닌 실제 오류) `closeBridgeSession(..., {closeRemote:true, invalidatePersisted:false})`로 명시 정리한다
- `destroyBridgeSession`는 child 종료를 최대 2초까지 기다리고, 필요 시 `orphan-kill` 라인을 찍는다

Smoke:

```bash
./run.sh smoke-cancel /home/junghan/repos/gh/agent-config
```

Pass 기준:

- `[pi-shell-acp:cancel]` 라인이 stderr에 반드시 있다
- `outcome=dispatched` 또는 `outcome=unsupported` 는 정상, `outcome=failed`는 실패
- abort 후 같은 sessionKey로 다음 프롬프트가 성공한다 (세션 재사용)
- `[pi-shell-acp:shutdown]` 라인이 반드시 있다
- 명시 `closeBridgeSession` 후 해당 backend 프로세스 delta가 0

운영 기본은 resilient (stderr diagnostic만, pi 세션은 계속), smoke는 fail-fast (하나라도 어기면 전체 실패).

### 12.5 delegate-style continuity (partial — evidence boundary 주의)

delegate 가 실제로 쓰는 spawn 형태(`pi --mode json -p --no-extensions -e <repo> --provider pi-shell-acp --model <M> --session <F> <task>`)를 그대로 흉내 내어 turn1=new → turn2=resume(Claude)/load(Codex) 연속성을 확인한다. bridge diagnostic 라인(`[pi-shell-acp:bootstrap]`, `[pi-shell-acp:model-switch]`, `[pi-shell-acp:shutdown]`)과 session file assistant payload 양쪽에서 증거를 본다.

Smoke:

```bash
./run.sh smoke-delegate-resume /home/junghan/repos/gh/agent-config
```

Pass 기준:

- turn1 `[pi-shell-acp:bootstrap] path=new backend=<backend>` 라인 존재 + acpSessionId 추출 가능
- turn1 session file에 `role:"assistant"` record 1개 이상
- turn2 `[pi-shell-acp:bootstrap] path=resume|load backend=<backend>` 라인 존재 + acpSessionId 가 turn1과 동일
- turn2 에 `bootstrap-invalidate` / `bootstrap-fallback` 라인 없음
- session file assistant message 수 ≥ 2 이고, 마지막 assistant payload 길이 > 0

**Evidence boundary (중요 — 확대 해석 금지):**

- **Claude**: real delegate-style e2e. `pi-extensions/delegate.ts` 의 spawn 인자와 동일한 모양을 `pi` CLI 에 직접 전달한다. delegate async orchestration (taskId/delegate_status/delegate_resume) 을 돌리는 것은 아니지만, 실제 하위 프로세스 CLI 표면은 delegate 경로와 같다. 외부 marker-recall 검증 (semantic continuity) 까지 확인됨 — 단순 shape 일치가 아니라 대화 기억이 resume 경로로 살아 넘어간다.
- **Codex** (sync mode 기준):
  - *default direct path* (`--provider openai-codex --model openai-codex/gpt-5.4`): pi-shell-acp 를 거치지 않고 openai-codex provider 로 직행. 이 smoke 의 범위 밖.
  - *opt-in ACP path* (`PI_DELEGATE_ACP_FOR_CODEX=1` + `openai-codex/gpt-5.4`): agent-config `delegate-core.ts` 의 `getDelegateExplicitExtensions` 가 `-e pi-shell-acp --provider pi-shell-acp` 를 자동 주입하고, `normalizeCodexDelegateModelForAcp()` 가 model id 를 `openai-codex/gpt-5.4` → `gpt-5.4` 로 벗겨서 codex-acp 가 ChatGPT 계정에서도 수락하도록 한다. marker-recall 로 real e2e 확인됨.
  - *이 repo 의 smoke*: `smoke_delegate_resume_single` 은 bare `gpt-5.4` 를 그대로 써서 pi-shell-acp 가 Codex 세션을 load 경로로 이어 들 수 있음 (shape-equivalent continuity) 을 검증한다. 실제 `delegate` tool 이 opt-in 조건에서 같은 경로로 가는지는 agent-config 쪽 `delegate-core.ts` 변경과 함께 본다.
- **async delegate orchestration** (taskId, delegate_status, delegate_resume): 여전히 별도 Phase. MCP pi-tools-bridge 에는 sync 만 노출되어 있고, async surface 는 pi native extension 에서만 사용 가능. VERIFY 승격 대상이 아니다.

이 smoke 는 `setup` / baseline exit criteria 에 올리지 않는다. 추가 evidence gate 로만 유지한다.

---

## 13. 실패 시 반드시 남길 증거

문제가 생기면 최소한 아래는 함께 남긴다.

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

그리고 함께 보관:
- 사용한 정확한 명령어
- 전체 stdout/stderr
- 사용한 `SESSION_FILE`
- 캐시 디렉토리 변화
- 기대 결과와 실제 결과의 차이

짧은 기록 예시:

```text
[verify] multi-turn continuity failed
- command: pi -e ... --session /tmp/xxx.jsonl ...
- expected: second turn returns test-token-123
- actual: model says it does not remember
- cache: persisted file existed
- process: no orphan / or orphan 1 left
- suspicion: resume/load path broken or session compatibility gate too strict
```

---

## 14. 통과 기준

최소 통과선은 아래다.

1. smoke 통과
2. bench quick/full에서 큰 이상 없음
3. single-turn prompt extraction 정상
4. same `SESSION_FILE` multi-turn continuity 정상
5. cross-process continuity 정상
6. `cwd:` persistence boundary 정상
7. tool use / event mapping 대체로 정상
8. orphan process / garbage record 남발 없음
9. pi session transcript가 공통 기억축으로 usable함
10. pi-facing MCP injection이 `piShellAcpProvider.mcpServers` 설정대로만 반영되고, resume/load/new 세 경로에서 가시성이 동일하며, 설정 변경 시 세션이 올바르게 무효화되며, 잘못된 설정은 `McpServerConfigError`로 즉시 fail-fast됨

이 10개가 통과하면, 그때부터 `pi-shell-acp`는 단순 실험이 아니라
**pi 하네스 안에서 운영 가능한 ACP bridge** 로 본다.
