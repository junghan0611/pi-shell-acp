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

## 0A. 실행 방침 — 투명 모드(실상황 기준)

이 문서의 검증은 벤치마크가 아니다. 실운영에서 우리는 `delegate` / `delegate_resume`처럼
**짧은 sync 턴을 계속 주고받으며** 상태를 확인하고, 이상이 보이면 즉시 멈추고 원인 분리 후 재개한다.

이 문서는 **검증 의도(무엇을 보는가)와 통과 기준(어떻게 판정하는가)** 만 적는다.
실행 shape는 에이전트가 자기 환경에서 가장 합리적인 도구로 알아서 정한다.
같은 의도를 다른 모양으로 검증해도 된다 — 통과 기준만 만족하면 된다.

### 기본 실행 shape — delegate orchestration

- 1턴 검증: `delegate(provider="pi-shell-acp", model="<M>", mode="sync")` 1회
- 멀티턴 검증: 첫 턴은 `delegate`, 이어붙임은 같은 `taskId`로 `delegate_resume`
- 다른 backend 검증: provider/model만 바꿔서 같은 패턴 (예: `pi-shell-acp/codex-...`)

### 하지 말 것 — 운영 경로 우회 패턴

다음 패턴은 **검증하려는 위임 로직 자체를 우회**한다. 표면적으로 continuity가 이어진 것처럼 보여도 실제 운영 경로(delegate → delegate_resume)가 아니므로, 통과해도 운영이 깨져 있을 수 있다.

- ✗ `mktemp /tmp/pi-shell-acp-verify-XXXXXX.jsonl`로 세션 파일을 직접 만들기
- ✗ `pi -e <REPO> --session <FILE> --model <M> -p '...'` 형태의 수동 호출
- ✗ 같은 세션 파일을 두 번 던져 멀티턴을 흉내내기

이 문서가 과거에 위 명령을 직접 적어두었기 때문에 에이전트가 그대로 복사해 운영 경로를 우회하는 사고가 있었다. 본문은 의도와 통과 기준만 둔다. 셸 명령은 boundary 검증(§6) 등 명령에 결합된 곳에서만 살린다.

수동 `pi --session` 경로는 다음 두 경우에만 쓴다.
- delegate 경로 자체가 부서져서 우회로로 격리 디버깅이 필요할 때
- bridge 내부 API를 직접 두드려야 하는 §6 같은 boundary 검증

### 운영 원칙

- **한 번에 하나의 명령만 실행**한다. (여러 단계를 `;`로 묶지 않는다)
- 각 단계마다 **stdout/stderr 전체**를 남긴다.
- 문제가 나면 다음 단계로 넘어가지 말고 **중단 → 대기(hold)** 한다. (필요하면 세션/캐시/프로세스 상태를 먼저 보존)

### 검증 프롬프트 wording — safety 해석 오염 피하기

continuity 검증에서 사실을 주입하고 다시 회수할 때, **모델 safety 해석이 끼어들지 않는 평문 사실**을 쓴다. 다음 어휘는 피한다.

- ✗ `secret token`, `test-token-123`, `password`, `API key`, `credential`
- ✗ "비밀", "민감", "유출하지 마라" 같은 메타지시

이런 wording은 Claude가 prompt injection / secret exfiltration / safety violation으로 해석해서 "모른다", "공유하지 않겠다" 같은 응답을 만든다. 그러면 **continuity는 살아 있는데도 회수 실패로 보인다** — 즉 safety 거부가 continuity 붕괴를 가장한다. 실제로 이 사고가 한 번 있었다 (`test-token-123` 검증이 거부 응답을 받아 위임 로직 실패로 오진).

대신 **비민감 평문**을 쓴다.

- ✓ `비밀번호는 올빼미다 → 한 단어로 답해 → 올빼미`
- ✓ 코드네임 / 색 / 동물 이름 / 평범한 단어 / 임의의 영숫자 토큰 (의미적 신호 없는)
- ✓ 첫 turn 응답은 짧은 ack(`READY` 등)로 강제

요점: continuity 검증과 safety 행동 검증을 한 프롬프트에 섞지 않는다.

### bridge continuity vs semantic continuity — 같은 것으로 취급하지 말 것

다음 두 층은 별개로 본다.

- **bridge continuity**: same `sessionKey` / persisted record hit / same `acpSessionId` / `bootstrap path=resume|load`
- **semantic continuity**: 이전 turn에서 준 사실을 다음 turn에서 회수 가능

bridge continuity가 살아 있어도 semantic continuity가 깨질 수 있다 (위 wording 오염 케이스). 반대도 마찬가지로 가능. 한 층의 통과를 다른 층의 통과로 외삽하지 말 것. bootstrap path 관찰성(§12 1번)이 약하면 두 층을 혼동해 wording 오염을 continuity 붕괴로 오진하기 쉬우니, 의심될 때는 wording을 바꿔 다시 한 번 더 보고, bridge stderr의 `[pi-shell-acp:bootstrap]` 라인도 함께 본다.

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

## 1A. 메인 에이전트 검증 질의서 — `pi-shell-acp` Claude는 충분히 강력한가?

이 섹션은 llmlog에 있던 질의서를 이 repo의 운영 문서로 옮긴 것이다.
핵심 질문은 하나다.

> **Claude가 pi를 통해 ACP로 연결되었을 때, 메인 코딩 에이전트로서 충분히 강력한가?**

이 검증은 continuity smoke와 별개다. smoke가 "세션이 이어진다"를 증명한다면,
이 질의서는 **도구 자기인식 / native tool 사용성 / pi-facing MCP boundary 인식 /
장기 턴 집중력 / direct Claude Code 대비 품질**을 본다.

실행 shape는 §0A의 원칙을 따른다 — Layer 0~3은 한 target(`pi-shell-acp/claude-sonnet-4-6`)에 대해 `delegate` 1회로 시작하고, 멀티턴이 필요하면 같은 taskId로 `delegate_resume`. Layer 4는 direct Claude Code와의 비교라 별도 경로다.

### 1A.1 Layer 0 — 세션 시작 시 자기 인식

의도:
- Claude가 지금 어떤 하네스/도구 환경에 있는지 스스로 설명할 수 있는가
- Claude Code native tool과 pi-facing MCP tool의 경계를 혼동하지 않는가
- 보이지 않는 system prompt / 프로젝트 문맥을 단정적으로 재현하려 하지 않는가

세 가지를 한 세션 안에서 자유롭게 묻는다 (환경 자기인식 / MCP 가시성 / 상위 지시 인식). 추측 금지를 명시한다.

Pass:
- native tool 계열을 대체로 인식하고, 모르는 것은 모른다고 말한다
- MCP 가시성은 현재 설정대로만 답한다 (설정이 없으면 "안 보인다")
- 상위 지시는 종류만 조심스럽게 설명, 내부 prompt를 단정적으로 재현하지 않는다

Fail:
- 없는 tool을 있는 척 말한다
- pi custom tool과 native tool을 뒤섞어 설명한다
- MCP visibility를 hallucination한다

### 1A.2 Layer 1 — 기본 코딩 작업에서 native tool을 자연스럽게 쓰는가

의도: "메인 코딩 에이전트" 적합성. 파일 읽기 / 구조 파악 / 회귀 포인트 찾기 / 검증 명령 식별 같은 일상 코딩 흐름을 던져, native tool 선택이 자연스러운지 본다.

Pass:
- Read/Edit/Bash/Grep/Glob 류 선택이 자연스럽다
- 검색 → 읽기 → 분석 순서가 매끄럽다
- 불필요하게 MCP나 recursive `pi` 호출로 우회하지 않는다

Fail:
- 단순 파일 읽기를 이상한 우회로로 처리한다
- 실제 파일을 읽지 않고 기억/추측으로 말한다

### 1A.3 Layer 2 — pi-facing MCP tool boundary를 이해하는가

의도: **tool confusion 방지.** 기본값에서 pi custom tool(`delegate`, `session_search`, `knowledge_search` 등)이 안 보이는 것이 정상이다. 중요한 것은 "보이는지/안 보이는지 정직하게 말하고, 안 보이면 없는 척 우회하지 않는가"다.

Pass:
- 안 보이는 tool은 안 보인다고 답한다 (예: "delegate tool not visible", "pi custom tools not visible")
- native tool과 MCP tool 경계를 설명할 수 있다

Fail:
- 없는 tool을 있는 척 사용한다
- `bash`로 `pi`를 재귀 호출해 delegate/session_search를 흉내낸다
- 경계 질문에서 한쪽만 맹목적으로 쓴다

참고: 기본 visibility boundary는 §8.4, §8.5의 operator 검증과 함께 본다.

### 1A.4 Layer 3 — 턴이 쌓여도 집중력이 유지되는가

의도: 세션이 이어지느냐보다, **이어진 상태에서 품질이 유지되는가**. 한 target에 대해 첫 turn(`delegate`)로 사실 주입(예: "AGENTS.md의 핵심 불변식 3개 기억해, READY만 답해") → 같은 taskId로 `delegate_resume`을 4~5회 이어가며 회수/탐색/회수를 섞는다.

Pass:
- 5턴 후에도 초기 불변식과 중간 탐색 결과를 함께 붙잡는다
- 이미 한 탐색을 반복하거나 앞뒤가 어긋나지 않는다
- tool selection이 턴이 지나도 크게 흔들리지 않는다

Fail:
- 초반에 읽은 것을 바로 잊는다
- 이전 턴과 모순된 도구 전략을 낸다
- 같은 파일 탐색을 불필요하게 반복한다

참고: compaction 이후 handoff 자체는 `./run.sh check-compaction-handoff`, `./run.sh smoke-compaction "$PROJECT_DIR"`로 별도 검증한다.

### 1A.5 Layer 4 — direct Claude Code와의 비교

같은 질문을 direct Claude Code와 `pi-shell-acp` 경로(= delegate target `pi-shell-acp/claude-sonnet-4-6`)에 각각 던져 비교한다. 문자열 일치가 아니라 **작업 품질과 도구 선택의 의미 수준 parity**를 본다.

비교 질문 예시: 이 리포 핵심 불변식 요약 / `run.sh`의 smoke 검증 체계 설명 / compaction handoff가 필요한 이유 / 다음 개선 포인트 3개 (thin bridge 원칙 유지).

비교 항목: 첫 응답까지 latency / native tool selection 정확도 / 불필요한 삽질 횟수 / MCP boundary 혼동 여부 / 10~15턴 근처에서의 품질 유지.

판정:
- direct보다 약간 느리거나 말투가 달라도 괜찮다
- **tool confusion, 장기 턴 망각, 경계 위반 우회**가 반복되면 불합격

### 1A.6 결과 해석

- Layer 0~2 양호 → 메인 코딩 에이전트 기본 자질은 확보
- Layer 2 약함 → tool description / MCP visibility 설명 / operating contract 후보 검토
- Layer 3 약함 → compaction, prompt shape, 장기 세션 관찰 강화
- Layer 4에서 direct 대비 현저히 약함 → bridge handoff 또는 capability framing 재검토

이 질의서는 smoke를 대체하지 않는다.
- 구조/불변식 회귀: `run.sh` deterministic + smoke
- 메인 에이전트 적합성: **이 섹션**

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

`pi-shell-acp/claude-sonnet-4-6` target에 대해 sync `delegate` 1회.

### 3.1 SessionStart hook 회귀 확인

`index.ts`의 `extractPromptBlocks()` 회귀를 가장 먼저 본다. 짧은 답("ok만 답하세요")만 요구하는 1턴.

Pass:
- `ok` 또는 그에 준하는 매우 짧은 응답
- `device=...`, `time_kst=...` 같은 hook 메시지를 주 프롬프트로 오인하지 않음

깨지면 의심할 곳: `index.ts`의 `extractPromptBlocks()`, pi hook message가 trailing user message로 들어오는 구조.

### 3.2 기본 도구 호출 확인

"현재 날짜·시간을 `date`로 알려달라" 같은 1턴.

Pass:
- date 실행 흔적이 보이거나, 적어도 tool 사용 기반 응답
- event-mapper가 붙은 환경이면 `[tool:start]`, `[tool:done]` 류 notice가 관찰될 수 있음

---

## 4. 멀티턴 검증 — 한 target이 이어지는가

이 단계부터가 중요하다. 실행 shape는 §0A 그대로 — 첫 turn `delegate(provider="pi-shell-acp", model="claude-sonnet-4-6", mode="sync")`로 시작하고, 같은 taskId로 `delegate_resume`을 이어 던진다.

검증용 사실은 §0A의 wording 가이드를 따른다 — `secret token` / `password` / `API key` 류 금지, 비민감 평문(코드네임 / 색 / 동물 이름 등)만.

### 4.1 사실 주입 → 회수 → 갱신

세 단계의 의도만 적는다.

1. 첫 turn: 비민감 사실 한 개를 주입하고 짧은 ack(`READY`)만 받는다. 예: "비밀번호는 올빼미다. 설명 없이 READY만 답하세요."
2. 두 번째 turn (`delegate_resume`): 방금 준 사실을 그대로 회수. 예: "방금 내가 말한 비밀번호가 뭐였는지 한 단어로만 답하세요." → `올빼미`
3. 세 번째 turn (`delegate_resume`): 사실을 다른 값으로 갱신하고 `CHANGED` 받기. 네 번째 turn에서 갱신된 값을 회수.

Pass:
- 두 번째 turn이 정확한 값을 답한다
- 갱신 후 마지막 turn이 갱신된 값을 답한다
- 텍스트 뭉치 재투척 없이 자연스럽게 이어지는 형태 (delegate orchestration이 ACP resume/load로 이어줌)

Fail:
- 사실을 잊거나, 첫 turn 내용을 통째로 다시 보내야만 답하거나, 갱신이 반영되지 않는다

Fail로 보이지만 의심해볼 것:
- 응답이 "공유하지 않겠다", "모른다" 같은 거부조라면 wording이 safety를 끌어들였을 가능성. §0A의 wording 가이드대로 평범한 사실로 다시 던져 본다 — 그래도 회수 실패면 진짜 continuity 문제, 회수되면 wording 오염이었다는 증거.

---

## 5. cross-process continuity — 프로세스가 바뀌어도 이어지는가

§4의 `delegate` → `delegate_resume` 쌍 자체가 서로 다른 child pi 프로세스를 거치므로 **cross-process** 성격을 이미 갖는다. 여기서는 persisted mapping과 cache까지 같이 본다.

### 5.1 캐시 전후 관찰

§4 실행 전후로 `find "$CACHE_DIR" -maxdepth 1 -type f | sort` 두 번 떠서 비교.

Pass:
- 첫 turn 후 `pi:<sessionId>`에 대응하는 persisted session record가 새로 생긴다
- 첫 turn의 child pi 프로세스가 종료된 뒤에도 record는 남아 있다
- 같은 taskId의 `delegate_resume`이 그 record를 그대로 재사용해 ACP 세션을 잇는다 (continuity 유지)

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

일반 종료 후 persisted mapping이 살아 있어야 다음 child pi 프로세스가 이어받을 수 있다. §4의 첫 `delegate`가 끝나면 child pi 프로세스는 자연 종료되는데, 그때 cache record가 invalidate되면 안 된다 — 이 invariant는 §5.1 snapshot으로 이미 관찰된다.

추가로 의미적 continuity를 한 번 더 보고 싶으면, §4의 마지막 turn 이후 일정 시간 뒤 같은 taskId로 `delegate_resume`을 한 번 더 던져 직전 대화 맥락이 자연스럽게 이어지는지 확인한다.

Pass:
- 직전 대화 맥락을 이어간다
- 일반 종료가 곧 invalidate를 의미하지 않는다

주의:
- 현재는 `resume` vs `load` vs `new` 중 무엇을 탔는지 외부에서 바로 보기 어렵다
- 이 문서 단계에서는 **결과 continuity**를 먼저 본다
- bootstrap path 관찰성은 후속 개선 포인트다

---

## 8. tool call / event mapping 검증

### 8.1~8.3 read / grep / bash 성격

`pi-shell-acp/claude-sonnet-4-6` target에 sync `delegate` 1회씩, 의도가 다른 짧은 작업 셋: 파일 일부 읽고 요약, 특정 함수 정의 grep, 현재 git 브랜치와 최근 커밋 1개.

Pass:
- read/search/bash 성격의 도구 사용이 일관되다
- 필요한 경우 tool notice가 자연스럽게 보인다
- 최종 응답이 tool output을 왜곡하지 않는다

관찰 포인트:
- `event-mapper.ts`가 text/thinking/tool notice를 적절히 흘려주는가
- permission event가 있을 경우 이상한 노이즈가 아니라 관찰 가능한 수준으로만 보이는가

### 8.4 pi custom tool visibility 확인 — 현재 핵심 의심 지점

여기서 보는 것은 `bash`, `read`, `grep` 같은 native tool이 아니라, **pi가 원래 LLM에게 주던 custom tool(`delegate`, `delegate_status`, `session_search`, `knowledge_search` 등)이 ACP 경유 시에도 보이는가**다.

검증 의도: `pi-shell-acp/claude-sonnet-4-6` target 안에서 "이 도구가 보이는가"를 묻고, 안 보이면 안 보인다고만 답하게 한다. 약속된 정확한 답:
- delegate 단일 가시성: `delegate tool not visible`
- pi custom tool 묶음 가시성: `pi custom tools not visible`

**현재 설계 기준 Pass:** 위 약속 문자열 그대로.

**Fail:**
- 없는 tool을 있는 척 hallucination
- `bash`로 `pi`를 재귀 호출해서 delegate를 흉내냄
- "대신 비슷하게 해봤다" 식으로 boundary를 흐림
- native tool만으로 얼버무리며 넘어감

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

**기본 가시성 (1턴):**

같은 프로젝트에서 `pi-shell-acp/claude-sonnet-4-6` target에 sync `delegate` 1회로 "지금 보이는 MCP 서버 이름을 쉼표로만 나열해" 류 프롬프트를 던진다.

Pass:
- 설정에 등록된 MCP(예: `session-bridge`)가 응답 목록에 들어 있다
- 등록하지 않은 MCP는 보이지 않는다 (자동 `~/.mcp.json` 로드 없음을 확인)

**resume/load/new 일관성 (멀티턴):**

§4 패턴(`delegate` → 같은 taskId `delegate_resume`)으로 두 turn 이상 돌려, 각 turn에서 본 MCP 서버 목록이 동일한지 확인.

Pass: 두 응답의 서버 목록이 동일.
Fail: 1턴에만 보이거나, 2턴에서 달라짐 → session fingerprint 또는 세 경로 주입 통일 문제.

**설정 변경 → 세션 무효화:**

`piShellAcpProvider.mcpServers`를 바꾸면 `bridgeConfigSignature`가 달라져 persisted session이 호환 실패하고 새 세션으로 넘어가야 한다. settings.json에서 `mcpServers` 항목을 추가/제거한 직후 `delegate_resume` 또는 새 `delegate`를 던져 새 설정이 즉시 반영되는지 확인.

Pass: 새 설정이 즉시 반영됨 (stale capability 없음).

현재 운영 기준에서는 이 visibility 확인을 **Claude + Codex 둘 다** 돌리고, 최소 1개의 bridged MCP tool 호출도 실제로 통과시킨다. 가장 안정적인 자동화 경로는 `send_to_session` negative-path 호출이다. 존재하지 않는 target에 대해 `No pi control socket ...` 오류가 surface되면, `ACP host → MCP bridge → pi-side RPC` 호출 경로가 실제로 살아 있음을 의미한다.

---

## 9. 시나리오 테스트 — 실제 작업자처럼 써본다

이 단계는 synthetic benchmark보다 중요하다. 한 target(`pi-shell-acp/claude-sonnet-4-6`)에 대해 sync `delegate` 1회씩, 의도가 다른 작업 셋.

- **9.1 자기이해**: AGENTS.md/README를 읽고 이 리포의 현재 불변식 7줄 이내 요약 (provider/model/settings 이름, session continuity 경계, bootstrap 순서, 하지 말아야 할 것 포함)
- **9.2 구조 설명**: `acp-bridge.ts`, `index.ts`를 기준으로 핵심 구조 설명. agent-shell을 semantic reference로 보되 일부러 가져오지 않은 것까지 함께
- **9.3 다음 고도화 제안**: 얇은 bridge 원칙을 깨지 않는 개선 포인트 3개. 항목마다 이유 / 건드릴 파일 / 검증 방법

Pass:
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

§4의 `delegate` → `delegate_resume` 쌍이 끝난 뒤, 그 task에 대응하는 child pi session 파일을 (taskId로 위치 확인 후) `wc -l` / `tail`로 들여다 본다.

Pass:
- user / assistant turn이 pi session에 정상적으로 누적되어 있다
- ACP 경유라고 해서 transcript가 깨지거나 텅 비지 않는다
- 나중에 임베딩할 때 최소한의 세션 의미론이 남아 있다

중요:
- 여기서 보는 것은 ACP 내부 transcript가 아니라 **pi 쪽 기록축**이다
- 우리가 지키려는 것은 "Claude는 ACP로, 기억은 pi 축으로"의 공존이다

---

## 12. 아직 비어있는 검증 포인트

아래는 현재 문서화는 해두되, 아직 관찰성/자동화가 덜 된 부분이다.

1. 실제 bootstrap path가 `resume`인지 `load`인지 `new`인지 외부에서 즉시 보이게 하는 것 — 현재 stderr `[pi-shell-acp:bootstrap]` 라인으로만 확인 가능. delegate orchestration 경로에서는 그 stderr가 사용자 앞단까지 surface되지 않아, 박살 진단 시 `bridge continuity` 통과 여부를 즉답하기 어렵다. 이 관찰성 부족이 wording 오염을 continuity 붕괴로 오진하게 만든다 (§0A "bridge vs semantic continuity" 참조).
2. persisted session incompatibility가 발생했을 때 invalidate 이유를 operator가 빠르게 읽는 것
3. ~~model switch 시 `unstable_setSessionModel` 경로 vs 새 세션 fallback 경로를 명확히 관찰하는 것~~ — §12.3 참조
4. ~~cancel/abort 시 bridge와 child process가 얼마나 깔끔하게 정리되는지 보는 것~~ — §12.4 참조
5. 장시간 세션에서 tool notice / thinking / text block이 누적될 때 stream shape가 안정적인지 보는 것
6. delegate-style continuity (§12.5 참조) — Claude / Codex 양쪽 backend 에서 bridge 의 resume / load 경로가 delegate 와 동일한 spawn shape 에 대해 이어진다. delegate orchestration 자체 (어느 target 으로 spawn 할지, taskId / async completion / resume identity lock) 는 이 repo 의 범위 밖이다. spawn 결정권은 `agent-config/pi/delegate-targets.json` registry 에 있다.
7. `bridge continuity`(sessionKey/acpSessionId/bootstrap path)와 `semantic continuity`(이전 turn 사실 회수)를 관찰성에서 분리하는 것 — 두 층은 별개로 통과/실패할 수 있다. §0A에 룰만 박아두었지만, 자동 smoke가 둘을 분리해서 판정하는 형태는 아직 없다.

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

### 12.5 delegate-style continuity (bridge-level)

이 smoke 는 delegate 가 실제로 쓰는 spawn 형태(`pi --mode json -p --no-extensions -e <repo> --provider pi-shell-acp --model <M> --session <F> <task>`)를 그대로 흉내 내어 turn1=new → turn2=resume(Claude)/load(Codex) 연속성을 확인한다. bridge diagnostic 라인(`[pi-shell-acp:bootstrap]`, `[pi-shell-acp:model-switch]`, `[pi-shell-acp:shutdown]`)과 session file assistant payload 양쪽에서 증거를 본다.

이 smoke 가 증명하는 것은 **bridge-level continuity** 다. 즉 "pi-shell-acp 가 주어진 (backend, session file, model) 조합에 대해 resume / load 경로로 세션을 이어 들 수 있다" 까지다. **어느 target 으로 spawn 할지 / async orchestration / resume identity lock / matrix coverage** 는 `agent-config` 의 책임이며 거기 `delegate-targets.json` registry 와 pi-tools-bridge 가 담당한다.

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

**Scope (retired narrative 주의):**

- Claude / Codex 둘 다 bridge 는 backend-native 방식으로 세션을 이어 든다. Claude 는 ACP `resumeSession` 을, Codex 는 `loadSession` 을 쓴다 (codex-acp 의 capability 차이 — `resumeSession: false, loadSession: true`). 이 smoke 는 두 경로 모두 bridge 가 올바르게 태우는지만 검증한다.
- 이 smoke 는 "shape-equivalent vs real e2e" 같은 라벨을 더 이상 쓰지 않는다. 그 구분은 delegate spawn authority 가 env 변수 (`PI_DELEGATE_ACP_FOR_CODEX=1`) 기반이던 과거 상태에서 나온 표현이다. 현재 spawn authority 는 `agent-config/pi/delegate-targets.json` registry 이며, bridge 는 registry 를 읽지 않는다. 해당 env 변수는 agent-config 쪽에서 legacy 로 표시되어 있고 registry 정착과 함께 정리될 예정이다.
- delegate orchestration 전체 (parent × target positive matrix, async completion, resume identity lock) 는 agent-config 가 책임진다 — bridge smoke 는 거기에 올라타지 않는다.

이 smoke 는 `setup` / baseline exit criteria 에 올리지 않는다. 추가 evidence gate 로만 유지한다.

---

## 13. 실패 시 반드시 남길 증거

문제가 생기면 최소한 아래는 함께 남긴다.

```bash
pgrep -af claude-agent-acp || true
find "$CACHE_DIR" -maxdepth 1 -type f | sort
```

그리고 함께 보관:
- 사용한 정확한 호출 (delegate provider/model/mode + delegate_resume taskId)
- 전체 stdout/stderr
- 해당 task의 child pi session 파일 경로
- 캐시 디렉토리 변화
- 기대 결과와 실제 결과의 차이

짧은 기록 예시:

```text
[verify] multi-turn continuity failed
- call: delegate(provider="pi-shell-acp", model="claude-sonnet-4-6", mode="sync") → taskId=...
        then delegate_resume(taskId=..., task="방금 내가 말한 비밀번호가 뭐였는지 한 단어로만 답하세요.")
- injected: "비밀번호는 올빼미다. 설명 없이 READY만 답하세요."
- expected: second turn returns "올빼미"
- actual: model says it does not remember
- cache: persisted file existed
- bridge stderr: [pi-shell-acp:bootstrap] line not captured
- process: no orphan / or orphan 1 left
- wording-recheck: tried again with "코드네임은 펭귄이다" → still fails (rules out wording oil)
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
