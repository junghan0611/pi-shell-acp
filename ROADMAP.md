# entwurf ROADMAP — 현재 + 미래 방향

> 이 문서는 **현재이자 미래방향**이다. `NEXT.md`는 disposable한 다음-한-걸음 나침반,
> `CHANGELOG.md`는 게시되는 "닫힌 변경" 핵심 로그, 이 `ROADMAP.md`는 게시되지 않는
> 내부 방향/설계 SSOT. 닫힌 작업의 세션별 process 잡음은 git 커밋 history에 산다.
> (NEXT는 npm tarball에서 제외, ROADMAP도 제외 — 내부 detail 안전. CHANGELOG는 게시됨.)

---

## 현재 — 0.15.1 shipped; OMP vendor measurement (실무 잠수함)

이 repo는 **entwurf-core(v2 garden-citizen dispatch) + native-harness bridges + pi adapter + ACP plugin**이다.
`v0.15.1`은 GitHub와 npm `latest`로 게시됐다 (`repair=0.12.8-repair.1` 보존). 0.15.0은 Copilot을 시민으로 들였고, 0.15.1은 Linux one-command setup honesty(#86)다. Claude mailbox, pi control-socket,
Antigravity native-push, Copilot self-fetch가 한 garden-id dispatch 표면으로 출하됐고, ACP plugin은 Claude와 Cortex를 pi host
안에서 연결한다. 0.14.0은 hidden background resume을 철회하고 visible fresh creation과 same-id pi resume을
각각 `entwurf_fresh_call` / `entwurf_resume_call`로 분리했으며, 0.14.1은 fresh creation에 literal absolute cwd를
더했고, 0.14.2는 exact configured bridge invocation과 ACP child-end evidence를 강화했다. 0.15.0은 Copilot을
시민으로 들였다. 검증은 ≤60s core와 frozen-candidate full floor로 계층화했다.

**2026-08-01~02 축 전환(GLG 지시).** pi가 공식 provider로 지원하는 Codex/Grok을 위해 native citizen이나
ACP backend를 중복 구현하지 않는다. #56 Codex native lane은 닫혔고, Codex/Grok 탐구 브랜치는 main 밖에
격리한다. 거기서 얻은 native/ACP rail 방법론은 필요할 때만 현재 증거로 다시 세운다.

현재 우선순위는 **OMP를 보이는 세션 하나로서만 재는 것** (`docs/adding-a-harness.md` step 1; 서브에이전트는 citizen이 아니다), 그 다음 #78 portability다. 구현 레인은 GLG grant 전 금지. GitHub OPEN은 backlog가 아니라 최대 5개의 실행 가능한
계약만 둔다 (현재는 초과 — 이 컷이 sweep하지 않는다). 방향·철학·관찰 중인 가능성은 이 문서가 지며, 재현 가능한 결손이 되면 그때 증거와 다음 측정을
갖고 이슈로 승격한다. 현재 실행 계약은 OMP 측정(이슈 아님, NEXT가 계약), #78 platform evidence, #72 ACP retained-child 원인, #76 subscription rail 강제, #80 public vocabulary다. #82/#86은 CLOSED. 실행 순서는 active NEXT handoff가 진다.

Pi는 가장 깊이 붙은 adapter지만 프로젝트의 본질은 여전히 **garden id로 호명 가능한 형제 세션 사이의 얇은
dispatch substrate**다. provider 연결과 TUI/RPC/session lifecycle은 pi에 맡기고, entwurf는 부르는 법과
배달의 정직한 경계에 집중한다. pi launch profile은 tmux placement primitive가 실물로 선 뒤에만 논한다.

v1 entwurf verbs(`entwurf`/`entwurf_resume`/`entwurf_send`)는 끝났고 사라졌다. `entwurf_v2`가 척추다.
기존 citizen 대상 send/reply → `entwurf_v2`(process를 열지 않으며 dormant는 정직하게 거절); 무에서 새 형제를 여는 fresh creation → `entwurf_fresh_call`(별도 verb, launch receipt만 동기 반환); dormant pi를 같은 garden id로 보이는 창에 다시 세우기 → `entwurf_resume_call {target}`(또 다른 별도 verb, prompt·model override 없음, 턴 없음, launch/observation receipt 분리).

### Vocabulary guard — 익숙한 말로 되돌리지 않는다

- **garden id**: 의도적으로 낯선 주소어. session id / worker id / delegate id로 번역하지 않는다.
- **citizen / sibling**: backend를 pi의 worker로 낮추지 않는다. 각 harness는 자기 transcript/auth/runtime을 가진다.
- **thin bridge**: auth 우회, transcript hydration, ambient MCP scanning, giant hidden prompt를 하지 않는다.
- **tool narrowing**: subagent 없음, todo tool 없음, yolo/좁은 tool surface는 기능 부족이 아니라 힣의 드라이버 규율이다.

### Current shipped / probe matrix

| Harness / rail | status | 이 repo에서의 정체 | Evidence |
|---|---|---|---|
| **pi** | shipped | control-socket adapter. ACP plugin도 pi provider/model로 들어온다. delivery 안의 relaunch transport는 visible-first cut으로 회수됐고, 그 자리는 별도 verb `entwurf_resume_call`이 visible same-id resume으로 채웠다. | `pnpm check`, v2 matrix LIVE, release-gate MUST |
| **Claude Code** | shipped | SessionStart meta-bridge → garden id + mailbox + trusted marker. Transcript를 가져오지 않는다. | meta-session gates, mailbox/deliverability, `doctor-meta-bridge` |
| **ACP Claude** | shipped; **outbound callback verified, retained-child failure tracked in #72** | Claude-first ACP plugin backend under local operator auth; socket-citizen rail. Integrated lifecycle proves callback, visible same-id resume and recall. Synthetic long-turn LIVE passes beyond 733s, but a real retained Sonnet tool-loop failed after four reuse turns with `ACP connection closed` (`20260730T194358-0061d2`), and GLG reports the same user-facing shape on hard workloads. #72 must recover child exit/signal/stderr and classify the workload-shape gap without automatic replay. Earlier intermittent bundled-MCP readiness observations remain separately recorded below. | ACP LIVE smokes + mux lifecycle release-gate MUST + #72 field report |
| **Codex** | native probe archived; managed lane declined | direct/native delivery evidence는 방법론 기록으로 남지만, pi가 공식 GPT provider를 지원하므로 별도 native citizen/ACP backend를 출하하지 않는다. 일반 external MCP host로 명시 배선하는 것은 별개다. | DELIVERY.md raw probe / closed #56 |
| **Copilot CLI** | shipped (0.15.0); D3 pending / D8 unproven | 첫 프롬프트에 `backend:"copilot"` V3 record. receive는 포크된 first-party extension + mailbox rail. visible fresh는 `entwurf_fresh_call {backend:"copilot"}` → owned `entwurf copilot` invocation, 4축 preflight, exact-nonce callback. `--ui-server`/`ws.*`는 거절. D3 pending / D8 unproven. Copilot visible-fresh LIVE는 operator-metered이며 release MUST가 아니다. | DELIVERY.md matrix row (LIVE receipts 2026-08-23 / 2026-08-25) + issue #82 thread |
| **Antigravity (`agy`)** | shipped | `PreInvocation` auto-birth + record-backed sender + native LS gRPC push; managed MCP/permission, statusline, hook adapters. | agy deterministic gates + doctors + 2026-07-13 live round trip |
| **Cortex / governed ACP** | **landed (0.13.0)** — hvkiefer's PR #40 adapter transplanted with the CP0-audit revisions (dual-HOME overlay, mcp.json projection, per-turn set-model, 4-row curation) | current D1–D10 contract is `docs/acp-backend-rail.md` “Cortex Code audit”; deterministic gate `check-acp-cortex` + mutant lane `acp-cortex`; CP2 live smoke `smoke-acp-cortex-live` stays outside the claude-only release floor | PR #40 / #48 / `docs/acp-backend-rail.md` |
| **Gemini CLI** | deprecated path | replaced by Antigravity direction for current Google individual tiers. | README migration note |

### ACP plugin boundary

ACP는 중심이 아니라 v2 core 위에 provider/model로 들어오는 **plugin 하나**(#38)다. Host
`--entwurf-control` pi 세션이 *이미* v2 socket-citizen이고, plugin은 socket/peers/citizen 층을 새로 만들지
않는다. Claude-first이며, backend auth는 operator의 로컬 상태에 맡긴다. No OAuth proxy, no subscription bypass.

| 단계 | 능력 | LIVE 증거 |
|---|---|---|
| S0 | loader/fence + provider 등록 + curated Claude + no-auth sentinel | `pi --list-models` · check-auth-boundary / check-acp-provider-surface |
| S1 | turn-free socket citizenship (ACP model이 `entwurf_peers` 1급 시민) | `smoke-acp-socket-citizen-live` |
| S2a | pinned ACP deps + raw 1턴 (stdio JSON-RPC) | `smoke-acp-raw-turn-live` |
| S2b | config overlay (격리 + 도구축소 + `hooks:{}`) + tool-surface preflight | `smoke-acp-overlay-live` |
| S2c | event mapping + `streamSimple` 실 backend | `smoke-acp-provider-live` |
| S2d | in-memory session reuse + delta-only prompt + carrier(핀1) + first-user augment | `smoke-acp-session-reuse-live` · `smoke-acp-carrier-augment-live` |
| S2e | RGG — ACP-target garden guard | `smoke-acp-rgg-live` |
| S2g | operator mcpServers/skills + bundled bridge | deterministic split pending for bundled-mcp MUST vs BEHAVIOR |

### v2 substrate evidence

| 기능 | 증거 |
|---|---|
| v2 pi live send | `smoke-entwurf-v2-matrix-live` C1 |
| v2 record-less socket 거부 — 모든 intent pre-probe `record-less-socket`, 원인+fresh-cut 명명 (#50 C4; A1 narrow 은퇴) | matrix-live C1b |
| v2 dormant pi → honest reject (`dormant-fire-forget-unsupported`, 아무 프로세스도 시작하지 않음) | matrix-live + `check-entwurf-v2-surface` |
| v2 active Claude Code meta → meta-mailbox enqueue + doorbell | matrix-live C2 |
| v2 live Antigravity → native-push direct injection | native-push adapter/register/decider gates + `smoke-agy-native-push-live` |
| agy automatic citizen birth + sender/reply identity | hooks/statusline/install/sender gates + three doctors + fresh live round trip |
| v2 honest reject (false-delivered/`.msg` garbage 0) | matrix-live C3 + deliverability/native-push reject gates |
| pi 0.85.1 fence | `pnpm check` + release-gate MUST |

### Historical — 0.12.0 cutover close checklist

- ✅ README / DELIVERY / BASELINE / VERIFY / CHANGELOG를 0.12.0 현재 표면으로 재정리했다.
- ✅ 오래된 `pi-shell-acp` / `pi-tools-bridge` / clean-host 중심 문서는 live-instruction 표면에서 제거하거나 history/cutover 문맥으로 한정했다.
- ✅ release cut 직전 `pnpm check` + `check-pack` + `check-pack-install` + `LIVE=1 ./run.sh release-gate <scratch>`를 재확인했다: 2026-06-25 MUST `PASS=17 FAIL=0 SKIP=0`; BEHAVIOR `/gnew` T3 `entwurf_self` flake 1건은 advisory.
- `smoke-acp-bundled-mcp-live`의 MUST/model-in-loop 불일치를 split한다: deterministic bundled bridge proof는 MUST,
  모델 자율 tool-call echo는 BEHAVIOR. 이번 cut에서는 PASS였지만 taxonomy hardening으로 남긴다.
- 데모 gif / hero 이미지를 새 표면에 맞춰 재생성한다.
- **ACP 백엔드 어댑터 레일을 재도입한다 (아래 표준궤 섹션).**

### Historical design record — 0.12.0 ACP 백엔드 어댑터 레일

PR #40(Snowflake Cortex Code, hvkiefer)이 드러낸 핵심: 0.11.0엔 `AcpBackendAdapter` 어댑터 패턴
(`type AcpBackend`=claude|codex|gemini, `ACP_BACKEND_ADAPTERS` Record, `resolveAcpBackendAdapter`)이
있었고 PR은 거기에 cortex를 4번째로 끼웠다. 그러나 0.12.0 cutover가 fat `acp-bridge.ts`를 통째 버리고
Claude-first로 새로 빌드하며 그 추상화를 제거 → 현재 `lib/acp/`는 claude 단선 + `config.ts:374`
non-claude **throw** 가드. **백엔드 추가 레일이 0.11.0보다 후퇴**(단일 claude 코드 품질은 향상).

- **결정:** `AcpBackendAdapter` 인터페이스를 plugin 구조 위에 재도입하고 claude를 그 *첫 구현*으로
  리팩터한다. cortex가 2번째 백엔드 = 추상화를 정당화하는 첫 실수요("2개부터 패턴이 산다").
  레일을 표준궤로 못박는 것이 곧 0.12.0에 담을 내용이다.
- **7 seam:** `resolveLaunch` · `ensureOverlay`(auth passthrough+state hiding) · `buildSessionMeta`
  (carrier; cortex=undefined→first-user augment) · curated models+prefix 라우팅(`inferBackendFromModel`) ·
  model enforcement(both landed backends: per-turn `session/set_config_option`; a launch-pinned backend would be the no-op case) ·
  settings+`bridgeConfigSignature` · gates(`check-backends`/`check-models`/`smoke-cortex`).
- **역할 분담:** GLG가 레일(인터페이스 + claude 리팩터)을 깔고, 기여자(hvkiefer)가 PR #40을 0.12.0
  `lib/acp/` 어댑터 하나로 포팅한다. 설계 SSOT = `docs/acp-backend-rail.md`. GPT 논의 후 확정.

### deferred (범위는 보임)

- **persisted resume/load (1b-2c)** — 현재는 in-memory reuse + record write만, persisted read/use는 OFF.
- **Cortex 백엔드 자체의 운영 lane** — 어댑터 레일(위 표준궤 섹션)이 0.12.0에 들어간 *뒤*, 기여자가
  PR #40을 어댑터로 포팅하고 로컬 완전검증(`smoke-cortex`)이 서면 운영 surface로 승격. 레일=0.12.0,
  백엔드 검증=그 위에서. (이전 "vendor CLI 검증되면" 단일 항목을 레일/백엔드로 분리.)
- **fresh sibling creation** — **landed as `entwurf_fresh_call`** (2026-08-05). v2 delivery transport
  (control-socket / meta-mailbox / native-push)는 여전히 전부 기존 citizen 대상이고
  `spawn-fresh`류 transport 이름은 굽지 않았다. 새 verb는 placement leaf → launch → fresh-call composition
  위에 서며, 새 sibling의 주소는 조회가 아니라 **callback sender envelope**으로 온다
  (docs/mux-launch-rail.md §6-a). **pre-injected token 기반 identity lookup(§6)은 deferred가 아니라
  CLOSED다** — callback correlation이 대체했고 새 증거 + GLG 재승인 없이 재개하지 않는다. 남은 deferred는
  generic harness profile뿐이다(resume용 visible placement는 S1에서 착지했다).
- **test/release-gate taxonomy (#41)** — 검증 자산을 deterministic / MUST live / BEHAVIOR / utility로 재분류.

### two-tier release-gate 원리

release-gate는 MUST(차단·exit code 소유 — transport/provider/backend invariant)와 BEHAVIOR(advisory·
비차단 — 모델이 MCP entwurf를 *자율 호출*하는가)를 분리한다. model-in-loop tool-selection은 Claude
Sonnet에서 flaky라 한 번의 flake가 컷을 막으면 안 된다. 우회/포기는 BEHAVIOR lane 안에서도 hard FAIL로
기록하되 컷은 막지 않는다. 단, MUST에 model-in-loop가 섞인 gate는 split해야 한다.

---

## 가까운 lane

### Carried post-v2 lanes
- **mux-visible launch / Claude Code live runtime** — mux는 delivery transport가 아니다. 실행되지 않던
  `tmux-live`는 2026-08-02 v2 contract/receipt에서 제거됐다. launch 뒤 Claude delivery는 meta-mailbox가 진다.
- ~~**recordless dormant pi resume**~~ — **#50 C4가 이 lane의 전제를 닫았다**: record가 유일한 주소
  권위이고(목표 ②), record-less socket은 시민이 아니라 진단 대상이다. 재오픈하려면 "record 없이
  resume authority"가 아니라 "그 resident를 record로 데려오는 경로"(재시작)를 설계해야 한다.
- **GC** (meta-record 누적) — `entwurf_peers` default live+recent+cwd 제한, dormant/meta 옵션화,
  stale marker·read body GC, record archive/TTL/lastSeen. **GC = 프로세스 자원 회수만, 데이터 삭제 아님.**
- **SE-3 readability** — 정직한 `replyable:false`가 버그로 오인되는 silent degraded addressability(가독성).
- ~~**`/gnew` T3 backend axis**~~ — **주제 소멸**: `/gnew`·`garden-new` 명령은 #50 C2에서 삭제됐다
  (id를 단속할 대상이 없다 — pi가 자기 세션 id를 민팅하고 record가 주소를 민팅한다). 인-프로세스
  new/fork/clone은 이제 pi 자신의 것이고 `session_start`가 새 시민으로 붙인다.

### mux launch / fresh creation lane
- **v1 removal — DONE (v2 core).** v1 entwurf verbs(`entwurf`/`entwurf_resume`/`entwurf_send`), pi-native
  `entwurf_send`, `/entwurf*` 명령은 모두 제거됐다. 현 MCP surface는 정확히 7개다:
  `entwurf_v2`, `entwurf_peers`, `entwurf_self`, `entwurf_inbox_read`, `entwurf_register_native`,
  `entwurf_fresh_call`, `entwurf_resume_call`.
- **visible mux lifecycle — SHIPPED.** tmux placement → fixed-runtime launch → callback-correlated fresh creation과
  record-authoritative visible same-id pi resume이 0.14.0에 착지했다. mux는 window/pane placement만 소유하고,
  garden identity·liveness·dispatch·lineage는 계속 entwurf가 소유한다. launch receipt는 runtime/task 성공이
  아니며 resume의 launch와 socket observation도 합치지 않는다.
- **driver optionality — deferred, not a current issue.** production은 tmux를 직접 호출하며 generic `DRIVERS`
  seam이나 zmx backend는 없다. 구체적인 두 번째 driver 수요가 생기기 전에는 비교·추상화를 재개하지 않는다.
  quota, system load, 예상 작업량, 과거 담당자 같은 선택 신호도 substrate/driver에 저장하지 않는다.
- **Copilot CLI — garden birth, outbound identity, owned receive, visible fresh 모두 한 호스트 LIVE.**
  #82 branch에서 실제 Copilot CLI 1.0.80 세션이 첫 프롬프트에 V3 record를 민팅했고, 자기
  garden id로 outbound `entwurf_v2`를 보내 `origin:meta-session`을 보존했다. Owned receive는
  2026-08-23 LIVE 수용으로 **D6**에 올랐다: garden `20260823T181316-d9f6ba`에서
  enqueue(`09:23:41.235Z`)→doorbell→drain→read-receipt(`09:23:56.480Z`) 사슬이 완결되고 모델이
  같은 record/native/gid 위에서 답했다(L4, Linux 한 대). Visible fresh (step 9 clause 7)는
  **별도 LIVE, 2026-08-25**: launch `@89`/`%89` nonce `mux-fresh-call-690529ae99f99faa2252aefb`,
  callback garden `20260825T085721-f68be0`, mailbox enqueue, `lastReadAt 2026-08-24T23:57:47.784Z`,
  same-gid reply, GLG footer visible. 그 행들은 합치지 않는다. `replyable:true`는 armed receiver
  marker가 있을 때의 사실이지 backend 상수가 아니다. 남은 것은 **D7 partial**, **D3 pending**,
  **D8 unproven**, experimental `EXTENSIONS` flag 내구성이다. D3/D8을 재개하지 않는다.
  Hidden `--ui-server`는 거절된 역사이며 다시 후보가 아니다. `ws.*`도 계속 금지다.
  Copilot visible-fresh LIVE는 operator-metered이며 기존 pi/claude release MUST에 넣지 않는다.
  Copilot은 GitHub 이슈/PR/CI와 model `auto`를 가진 별도 하네스이며, 그 역할은 dispatch 예절이지
  substrate role system이 아니다.

---

## 큰 방향 — entwurf-core / ACP plugin 아키텍처 split (GLG 결정 2026-06-16, 2026-06-22 갱신)

**0.12.0 rename cutover와는 *별개의 더 먼 좌표*다.** rename은 이름을 spine에 맞춘 것이고(같은 한 몸),
split은 한 몸인 코드를 *물리적으로 쪼개는* 것이다.
**언젠가 entwurf-core(v2 인터페이스)를 별 repo로 추출**해 ACP plugin과 분리할 수 있다 — 집중을 위해. 단
이것은 **deferred coordinate**(#38), 이번 lane이 아니다. 지금(그리고 rename 직후에도) 이 repo가 v2
dispatch substrate + meta-bridge + ACP plugin을 한 몸으로 들고 간다.

- v2(garden citizen에 대한 결정적 dispatch substrate: rail-specific liveness → control-socket /
  meta-mailbox / native-push)는 분리 시 새 `entwurf` repo에서 깨끗이 자랄 후보다.
- **entwurf-core** = identity / garden id / inbox / liveness / dispatch / replyability / evidence 추출이
  그 첫 몸.
- split 전까지 (그리고 rename 후) `entwurf` = **v2 core + meta-bridge + ACP plugin**(v1은 이미 제거됨,
  한 몸). ACP는 plugin, boundary 아님(#38).

---

## 동결 invariant — 넘으면 안 되는 선 (전부 #35)

- **Workshop, not factory.** 살아있는 소수 도제 = 재질문 가능, 상태는 세션 안 → 외부 DB(beads/dolt) 금지.
- **GC = 프로세스 자원 회수만, 데이터 삭제 절대 아님.** meta-record/transcript(denote-id 기억층) 보존.
- **garden-id = authority, tmux = ephemeral.** 세션명=path(grouping), window 번호 renumber.
- **Factory 작업 OUT.** worktree·merge-wall fan-out 없음 → 백엔드 자체 orchestrator로 위임.

### Deferred questions — documents, not OPEN issues

아래는 현재 실행 계약이 아니다. 묵혀 둔 tracker를 만들지 않으며, 실제 결손으로 재현될 때만 증거와 다음
측정을 갖고 이슈로 승격한다.

- 외부 native transcript는 참조만 한다. normalize·replay·fake pi session 합성은 금지한다.
- D8 잔여는 empirical missed-delivery probe와 unread-mailbox heartbeat다. 현재 수준은 `DELIVERY.md`가 진다.
- 1.0.0 demo gate는 render pipeline이 이 제품 층인지 먼저 판정한다. 아니라면 구현하지 않는다.
- recent-activity adapter는 그것 없이는 불가능한 dispatch 결정을 먼저 이름 대야 한다.
- core/plugin split은 due condition이 생기기 전까지 무기한 deferred다.
- remote identity/resume은 의도적으로 fail-fast다. 부활 시 child cwd는 saved session header와 맞춘다.
- 모델의 자기 capability 진술은 권위가 아니다. 실제 harness/tool schema와 `DELIVERY.md`가 진다.
- `check-fresh-cut-gate` G-cell의 3초 collision seed는 setup miss를 제품 실패로 오판할 수 있다. 실제 발화하거나
  이 축을 고치기로 결정할 때 seed 안착 증명 + `G SETUP MISS` 계약으로 승격한다.

---

## 핵심 아키텍처 — 데이터 4분리 + 한 동사

- **record(누구였나) / capabilities(무엇·어떻게 깨움) / mailbox(메시지·receipt) / probe(지금 살아있나,
  저장 안 함 — 매번 계산).** 상태를 저장하면 거짓말이 된다(denote-instinct 함정).
- **레인은 transport별로 KEEP:** pi socket/headless resume, Claude mailbox self-fetch, agy native-push.
  resume/send는 세션 type 문자열이 아니라 **각 rail에서 현재 측정한 liveness의 함수**다.
- **entwurf = 한 동사(`entwurf_v2`).** `entwurf_peers` = 읽기 전용 fact 표면
  (liveness/capability/identity/cwd-이력만) — `resumable`/`sendable` 같은 verb-routing을 fact 층에 굽지
  않는다. 기존 `entwurf`/`_resume`/`_send`는 제거 완료.
- **브레인 ↔ 핸드 분리(둘 다 TS).** 브레인 = TS fact 모듈(disk SSOT meta-record를 읽음, in-memory Map의
  형제-비가시성 대체). 핸드 = 기계적 실행. **최종 형제 선택은 에이전트, 모듈은 근거 제공.** 부가 신호
  (쿼터·시스템 부하)는 substrate가 아니라 에이전트 층 — substrate에 저장하지 않는다.

### meta-record V3 (nullable-at-birth) — #50 C1 hard cut
`{ schemaVersion:3, gardenId, backend, nativeSessionId, cwd, model:null, transcriptPath:null,
createdAt, recordUpdatedAt }`. `model`/`transcriptPath` nullable 근거 = 어느 백엔드도 birth stdin에
model 없음, pi backend는 birth에 transcript 미확정. `recordUpdatedAt` = record touch time(liveness 아님).

**프로덕션은 schemaVersion 3만 읽고, repo에는 legacy reader/migrator가 없다 (fresh-cut 뺄셈).**
읽지 못하는 record를 만나면 fail-loud로 fresh-cut 동사(`entwurf meta-bridge-fresh-cut`)를 이름으로
지목한다 — 이전 세대는 통째로 archive되고 빈 세대가 열린다. active store는 세대 간 주소/resume
연속성을 제공하지 않는다(세션은 흘러가고, 기억은 native transcript와 임베딩 축에 있다). 은퇴한
v2 필드 `parentGardenId`/`isEntwurf`는 **stray key로 거부된다** — 되살리지 마라(LOCKED PROTOCOL 6:
모든 record-backed 시민은 sibling이며 backend/transport로 존재 등급을 나누지 말고, `isEntwurf` 종 boolean 부활 금지).

---

## 동결 결정 (frozen decisions — 재설계 금지)

> 번호는 고정이다 — 코드가 "frozen decision N"으로 참조한다(4·7·8·9·10 등). 뒤집힌 항목은
> 지우지 말고 취소선으로 남긴다: 번호를 재조정하면 그 참조가 깨지고, 빈 자리가 "왜 없지"를 낳는다.

1. 능력 레지스트리 = 별도 `entwurf-capabilities.json`(launch allowlist와 별 관심사).
2. ~~v1→v2 = `parseMetaRecordV1/V2`→`normalizeMetaIdentity` dual-read + lazy normalize, 새 write는 v2.~~
   **#50 hard cut이 이 결정을 뒤집었고, fresh-cut 뺄셈이 완결했다 — 재설계 금지 대상 아님(오히려
   되살리는 것이 금지다).** 프로덕션은 V3-only, dual-read와 legacy reader/migrator는 repo에서 삭제됐다.
   읽지 못하는 store는 명시적 fresh-cut(`entwurf meta-bridge-fresh-cut`)으로 세대를 끊는다. 아래
   「meta-record V3」 절 참조.
3. ~~correlation = 소켓파일명 + tmux `@garden_id`; env probe 폐기; lineage는 launcher가 `PARENT_SESSION_ID`를
   명시 set.~~ **C1–C3가 이 correlation/lineage 설계를 대체했다.** 주소축은 meta-record 하나이고(LOCKED
   PROTOCOL 1), record엔 parent/lastCaller/worker tree가 없다(LOCKED PROTOCOL 5) — `PARENT_SESSION_ID`도
   tmux `@garden_id` correlation도 코드에 없다. socket은 record gardenId로 키잉되는 내부 transport일 뿐
   (C4, LOCKED PROTOCOL 3).
4. preflight/facts owner = **단일 TS 모듈**. launcher / global `project_trust` handler / MCP fact tool은
   결과만 소비, 누구도 prefix/trust 판정 재구현 안 함. **trust ≠ discovery**: trust는 launch-time 단일
   cwd만; peers/discovery는 trust 불필요.
5. untrusted controlled launch = **fail-fast**(조용한 `--no-approve` degraded 금지). trusted만 `--approve`.
   진짜 근거 = untrusted repo의 `.pi/settings.json`이 bridge로 적용되는 위험.
6. `project_trust` handler `remember` = **false**(prefix policy = SSOT). carve-out: 사람이 명시적으로
   상속-distrust를 덮어쓴 child override는 `remember:true` 저장.
7. prefix auto-approve roots = **operator policy, NOT package default**(public package 보안 footgun 방지).
   source = trusted operator surface만(`ENTWURF_PREFIX_ROOTS` env / user-global / agent-config). match =
   canonical path + separator boundary(bare `startsWith` 금지). GLG 기본 = `~/repos/gh`,`~/repos/work`,`~/org`.
8. **precedence 동결:** `saved false > saved true > prefix match > no-trust-inputs > fail-fast`.
9. **import surface = public root export만**(`getAgentDir`/`hasProjectTrustInputs`/`ProjectTrustStore`/
   `VERSION` + handler 타입). private subpath import 금지 = 공짜 drift 게이트. runtime은 `VERSION >= floor` fail-loud.
10. **공개 동사 먼저 축소(contract-lock) → fact-provider(facts only) → dispatch.** entwurf 공개 표면을 한
    동사로 줄이고 `entwurf_peers`를 읽기 전용으로 못박는 걸 fact-provider 빌드보다 먼저. 통합 dispatch는
    레거시 공존 새 이름(`entwurf_v2`)으로 additive. 레거시 3-verb 은퇴는 v2 증명 + 완전 전환 이후.

---

## 검증 원장 (measured, 재탐색 불필요)

- **pi 0.80 public export:** `hasProjectTrustInputs`/`ProjectTrustStore`/`getAgentDir`/`VERSION` 모두 index
  public export → TS 직접 import(재구현 불필요). floor = **0.85.1** (`>=0.85.1 <0.86`, next-minor 상한).
- **pi trust(0.79.1+):** `pi -p`는 trust에서 안 멈춤(비대화 미결정→`false` degraded). `--approve`(`-a`)=
  project 파일 로드, `--no-approve`(`-na`)=무시·degraded. `ProjectTrustStore.get`은 nearest-ancestor
  walk-up(조상 cwd 결정을 자식이 상속). `AGENTS.md`/`CLAUDE.md`는 0.79.1에서 trust input에서 제거(항상
  로드되는 context file). 우리 AGENTS 주입은 trust 무관 자체 경로.
- **pi resume = no-lock append:** `SessionManager`는 신규 첫 flush만 `openSync(wx)`(생성 가드). resume은
  plain `appendFileSync`(락 없음) → pi는 동시-resume self-guard 안 함 → v2는 target=존재 시민이라 항상
  resume → **per-gid lockfile이 유일 가드.**
- **pi liveness:** 소켓 = `~/.pi/entwurf-control/<gid>.sock`(파일명=garden_id, record가 키). LIVE/STALE
  authority = `probeSocketLiveness`(3-value connect probe) — 목록은 `scanSocketProbes`, GC는
  `gcStaleSockets`(#50 C4: `isSocketAlive`/`getLiveSessionsWithInfo` 소켓-스캔 lane은 삭제됨).
  `ss`/`kill -0`은 디버그 보조일 뿐 authority 아님.
- **pi tmux 부팅:** `pi --entwurf-control --approve --provider … --model …` → record가 주소를 민팅하고
  소켓 생성·trust prompt 없음·TUI ready (#50 C2: `--session-id` 주입 계약 은퇴). controlled
  invariant(`--approve` 주입) live-smoke 게이트화 가능.

---

## Backlog 트랙 (0.12.x 이후, GLG 재오픈 시)

- **🔴 OPEN — 번들 MCP readiness race (2026-07-24 검수에서 발견, GLG: "고치지 말고 더 지켜본다").**
  `pi --entwurf-control` resident의 첫 턴에서 번들 `entwurf-bridge` MCP 도구가 세션 tool schema에
  **가끔 없다.** 독립 2회 관측이며 **모델의 반응은 서로 달랐다 — 공통 원인이 가려지기 쉬웠던 지점이다**:
  - `smoke-acp-v2-send-live` (19:00) — 모델이 **호출했고** 런타임이
    `[tool:failed] … No such tool available: mcp__entwurf-bridge__entwurf_v2`로 답했다.
  - `smoke-acp-bundled-mcp-live` (aggregate, 19:30) — 모델이 **스키마를 먼저 읽고 호출하지 않았다**:
    "콜 가능한 도구는 Read/Bash/Edit/Write/Skill뿐 … 존재하지 않는 도구 호출 결과를 지어내지 않겠다."
  두 표본 모두 **도구가 세션 스키마에 없었다**는 사실은 같다. 격리 재실행은 3/3 PASS.
  부하 조건은 **표본마다 다르고 인과가 아니다**: 19:00 표본은 백그라운드 `pnpm check`와 실제로 동시였고,
  aggregate 표본은 앞선 라이브 턴 10여 개 뒤의 무거운 시퀀스 후반부였다 — 다만 순차 게이트는 이전 child를
  종료하므로 **그 실패 순간에 동시 프로세스가 있었다는 증거는 아직 없다.** load association은 상관일 뿐이다.
  dist rm/build race는 배제됨(dev-location branch는 항상 TS source 실행).
  - **구조**: claude-agent-acp 0.61.0 `createSession()`은 `await q.initializationResult()`만 기다리고
    즉시 반환(`acp-agent.js:3942-4058, 4174-4177`), 우리 backend는 model enforce 후 곧바로 prompt
    (`acp/backend.ts:718-790`). **configured MCP가 `connected`에 이르길 기다리는 층이 없다.**
    claude-agent-sdk 0.3.217은 `q.mcpServerStatus()`로 `pending|connected|failed|needs-auth|disabled`
    + connected 시 `tools[]`를 노출한다(`sdk.d.ts:1056-1097,2396`) — claude-agent-acp가 readiness에
    쓰지 않을 뿐이다.
  - **처방 옵션 (택일 전 관찰 중)**:
    ① **upstream/patch seam** — claude-agent-acp가 `createSession`에서 configured MCP별 connected +
       expected tool까지 bounded wait하고, 실패를 ACP `newSession` error로 올린다. 가장 정직하지만
       우리 손 밖이다.
    ② **adapter 확장** — MCP status를 ACP 확장으로 노출하고 entwurf backend가 prompt 전에 poll한다.
       우리 손 안이고 결정론적. 계약이 하나 늘어난다.
    ③ **재시도/두 번째 턴** — race 관측에는 유효하나 **결정론적 readiness 계약이 아니다.** 임시방편.
  - **스모크만 고쳐서는 preflight를 만들 수 없다**: `mcpServerStatus()`는 claude-agent-sdk 내부
    Query API이고, 우리가 받는 ACP `newSession` 응답에는 tool list/status가 없다.
  - **관찰 규율**: 이 결함이 다시 나오면 표본을 여기 누적한다 — 시각, 동시 부하, 어느 스모크,
    모델 발화. 인과가 서기 전에는 고치지 않는다(GLG 결정). MUST tier는 유지 — 실패는 **우리 결함**이며
    advisory로 내리면 그 결함이 묻힌다.
  - **표본 3 (2026-07-24 22:38 KST, 페블 검수 세션)** — `smoke-acp-bundled-mcp-live`,
    `LIVE=1 release-gate` @ `cbda097` 17스텝 중 16번째에서 FAIL (MUST 16/1/0, 나머지 ACP 10종 + v2-send 전부 PASS).
    **이번엔 머신이 조용했다** — 외부 동시 프로세스 없는 순차 aggregate 단독 실행. "외부 동시부하 필요" 가설은
    이 표본으로 약화; "무거운 라이브 시퀀스 후반부" 상관만 남는다. 모델 발화(자동 보존 transcript, 이날 랜딩한
    보존 장치의 첫 실전 작동): "현재 세션에 노출된 실제 도구 스키마에는 `mcp__entwurf-bridge__entwurf_self`가
    없습니다. Bash, Edit, Read, Skill, Write만 호출 가능한 상태라, 존재하지 않는 도구를 호출할 수는 없습니다."
    — 부재를 읽고 호출 거부(aggregate 표본과 같은 반응형). 턴 전 단언은 전부 GREEN(record birth, socket,
    get_info, prompt RPC 수락, extension_error 없음) — 정확히 tool schema만 비었다. 직후 격리 재실행 PASS
    (14 checks — 격리 누적 4/4 PASS). 원본 transcript:
    `~/.pi/agent/entwurf-readiness-race-samples/entwurf-smoke-acp-bundled-mcp-live-FAIL-2026-07-24T13-38-07-945Z.log`.
  - **표본 4 (2026-07-27 10:24–10:25 KST, pi 0.82.1 + claude-agent-acp 0.62.0 + claude 2.1.220)** — 핀 업 직후
    citizen 3종 순차 실행, **3/3 PASS**: `smoke-acp-socket-citizen-live` 10 checks,
    `smoke-acp-bundled-mcp-live` 14 checks(번들 bridge가 세션에 도달), `smoke-acp-v2-send-live` 15 assertions.
    조용한 머신(loadavg 1.24), 총 24초.
    **이 표본의 한계를 분명히 한다 — 상관 조건을 재현하지 않았다.** 실패 표본 3개는 전부 *무거운* 조건에서
    나왔다(19:00 백그라운드 `pnpm check` 동시, 19:30 라이브 턴 10여 개 뒤 aggregate 후반, 22:38 17스텝
    release-gate 후반). 24초짜리 3종 순차는 구조적으로 이미 4/4 PASS였던 **격리 재실행과 같은 조건**이다.
    따라서 이 표본은 격리 누적을 5/5로 올릴 뿐, "무거운 시퀀스 후반부" 상관에 대해서는 **아무 말도 하지 않는다.**
    green은 fix 증거가 아니다. 상관 조건을 실제로 치려면 `LIVE=1 ./run.sh release-gate <scratch> --cut` 전체(표본 3을 낳은 그것)를
    돌려야 한다. 아래 ordering probe는 표본을 늘리는 대신 **다른 질문**(이 서버가 지연된 MCP를 기다리는가)을 친다.
  - **현재 claude-agent-acp 노출면에 관측 경로가 없다는 실증 (2026-07-27).** claude-agent-acp 0.62.0 `dist`가 방출하는
    `sessionUpdate` 종류는 `agent_message_chunk` / `agent_thought_chunk` / `available_commands_update` /
    `config_option_update` / `current_mode_update` / `plan` / `session_info_update` / `tool_call` /
    `tool_call_update` / `usage_update` **전부이며 MCP 상태를 알리는 것은 하나도 없다.**
    즉 client가 prompt 전에 readiness를 *읽을* 방법은 현재 ACP 표면에 존재하지 않는다 —
    처방 ②는 "폴링을 추가한다"가 아니라 "없는 신호를 먼저 만든다"는 뜻이다.
  - **ordering probe 설계 (다음 한 걸음, 아직 미구현).** 간헐적 창을 관측하려 하지 말고 **입력 변수를 통제**한다.
    `scripts/fixtures/probe-mcp-server.ts`에 env 기동 지연(`PROBE_MCP_STARTUP_DELAY_MS`)을 넣는다.
    **probe 단위는 단발 delayed run이 아니라 paired control/intervention이다.** 단발로는 아무 판정도 서지 않는다:
    A처럼 보여도 `newSession`의 다른 작업이 우연히 더 걸린 것일 수 있고, B처럼 보여도 `delay=0`에서 이미
    실패했을 수 있으며, D는 probe가 스스로 만든 timeout일 수 있다 — 턴의 wall-clock 경계는 30초
    **셋뿐**이고 전부 bootstrap이다(`INITIALIZE_TIMEOUT_MS` · `NEW_SESSION_TIMEOUT_MS` ·
    `SET_MODEL_TIMEOUT_MS`, `pi-extensions/lib/acp/backend.ts`). **prompt에는 production 경계가 없다**
    (0.13.1: 진행 중인 턴을 elapsed time으로 죽이지 않는다). probe의 `PROBE_PROMPT_OBSERVATION_MS`는
    측정 harness의 observation horizon일 뿐 production 계약이 아니다.
    따라서 ⑴ 동일 pin/config/fixture의 `delay=0` **control**(기대 도구가 visible **그리고** callable),
    ⑵ newSession·set-model 두 30초 경계보다 충분히 작은 `D` **intervention**, ⑶ **A 판정에는 nonzero D가
    최소 2개(`D1`,`D2`) 필수** — "latency가 D를 따라 이동"이 판별자인데 점 하나로는 scaling을 못 본다.
    D 하나면 ordering 관측까지만이고 wait 판정은 **유보**한다(B·C·D는 첫 intervention에서 읽어도 된다),
    ⑷ 모든 이벤트에 `runId`를 실어 결합.
    **production sequence의 중간 단계를 계측에 넣어라:** 실제는 `newSession → enforceModel(setSessionConfigOption)
    → prompt`이고, 지연된 MCP가 `enforceModel` 동안 해소되거나 거기서 fail-loud할 수 있다. newSession/prompt만
    마킹하면 그 둘을 C나 D로 오독한다. 최소 ACP-side 마커 =
    `newSession start/end → setSessionConfigOption(model) start/end → prompt start/end`.
    **판정 공간 밖에 run-invalidating state가 둘 있고 어느 것도 D가 아니다.** **P0(INVALID BASELINE)**:
    `delay=0` control 자체가 실패(거기서의 `initialize` 실패 포함) → 중지, intervention 판정 안 함.
    **I0(INVALID RUN)**: control은 통과했는데 *intervention* run이 `initialize`에서 실패 → injected delay가
    그 phase에 닿을 수 없으므로 환경 drift다. intervention 판정 중지, artifact 보존, 같은 pair **1회 재실행**.
    재발하면 더 돌리지 말고 environment·initialize 원인 규명으로 전환한다. (P0는 원인명이 아니라 "control이
    판정 가능한 baseline이 아니다"라는 **상태명**이므로 artifact에 `reason=initialize|tool-unavailable|…`를 남긴다.)
    **먼저 id를 실측하라 — hardcode 금지.** provider-bound tool id는 source MCP 이름과 다르다 — 이 repo 실측이
    source `entwurf_v2` → runtime `mcp__entwurf-bridge__entwurf_v2`다. delayed run에서 모델이 bare `probe_nonce`를
    추측 호출해 `No such tool`을 받아도 실제 provider-bound id는 schema에 있었을 수 있으며, 그건 alias·model
    오류이지 absence가 아니다.
    **두 layer는 request-id namespace를 공유하지 않으므로 우리가 통제하는 argument로 correlate한다.** ACP
    `tool_call`의 `toolCallId`는 Claude tool-use id이고(`acp-agent.js`가 `toolUse.id`/`tool_use_id`/`message.uuid`로
    만든다), fixture가 보는 JSON-RPC id는 MCP client가 따로 민 것이다 — `acp-agent.js`에 `jsonrpc`는 **0회**
    등장하므로 둘이 같다는 보장 자체가 없다. "request id로 join"은 측정이 아니라 가정이다. 대신
    ⓐ probe fixture tool에 **필수 correlation field**(`probeRunId`)를 둔다 → ⓑ prompt가 이번 run의 unique
    `probeRunId`를 **정확한 argument로** 넣어 호출하게 한다 → ⓒ control의 ACP `tool_call`(provider-bound tool
    name + `rawInput.probeRunId`)과 fixture `tools/call.params.arguments.probeRunId`를 **`runId` + `probeRunId`**로
    join한다 → ⓓ 그 ACP 이벤트에서 관측한 provider-bound tool name을 **`expectedProviderToolId`**로 저장한다
    (실측, hardcode 금지). ACP `toolCallId`와 MCP JSON-RPC id는 artifact에 보존하되 **cross-layer equality·join
    key로 쓰지 않는다.** 아래 모든 absence 주장은 그 실측값과 비교한다.
    **P0 승격은 서사가 아니라 마커로 판정한다** — "과거 표본과 같아 보인다"는 판정 술어가 아니고, 그 추론이야말로
    이 probe가 대체하려는 것이다:
    ⑴ `tools_list_response_forwarded` 없음 → MCP handshake/fixture/config 후보, **승격 금지** /
    ⑵ 기대 도구의 `tools/call`이 fixture에 도달했으나 실패 → dispatch는 이미 성립했고 실행 실패이지
    schema absence 아님, **금지** / ⑶ `tools_list_response_forwarded` **그리고** 명시적 호출 프롬프트 전송
    **그리고** fixture `tools/call` 마커 **없음** **그리고** 런타임 `No such tool available: <id>`의
    `<id> === expectedProviderToolId` → **직접 schema-absence 증거**, pre-turn assertion·config 유효 시
    **승격 가능** / ⑷ 같은 조건인데 `<id>`가 bare 이름이나 다른 alias → model·alias mismatch, **금지** /
    ⑸ call marker 없음 + 직접 런타임 에러 없음 + 모델이 "도구가 없다"고 말만 함 → model-compliance·증거불충분,
    **모델 발화 단독 승격 금지** / ⑹ **같은 `runId`·같은 prompt request에 귀속된** provider-bound schema
    snapshot을 `tools_list_response_forwarded` **이후**에 떠서 `expectedProviderToolId` 부재 확인 →
    ⑶과 동급으로 허용. 순서 `forwarded < snapshot`을 닫아야 한다 — prompt 이후 임의 시점의 캡처는 dynamic
    update 때문에 같은 주장이 아니다. 가능하면 snapshot은 provider가 모델 요청에 실제로 넘긴 tool-definition
    set이어야 하며 재구성이 아니어야 한다.
    나열되지 않은 조합은 기본값 **P0/inconclusive**. ②/③의 경계는 에러 문구가 아니라 fixture `tools/call`
    마커의 유무로 갈린다.
    순서는 ⓐ `P0` 사실로 artifact 보존·기록 → ⓑ setup/pin/config/fixture/model-compliance 분류 →
    ⓒ 위에서 승격 가능한 행일 때만 이 원장의 새 표본으로 **승격**. control 실패를 B나 D에 섞는 것도 금지다.
    A: delayed run이 ordering을 유지하고 **동시에** `newSession` latency가 `D1`,`D2`를 따라 이동 → 이 서버·이
    경로의 wait 증거(일반 보증 아님) / B: control은 callable PASS인데 delayed run은 `newSession`/`enforceModel`/
    prompt가 wire-availability보다 앞서고 absence·`No such tool` → delay window가 failure mode에 **충분** /
    C: control PASS, delayed run이 앞서지만 이후 direct tool-call 마커 성공 → client fence 없이 late·dynamic
    readiness / D: 경계보다 충분히 작은 D인데 error·timeout → fail-loud 관측이며 **반드시 phase 이름을 붙이되,
    delay가 실제로 닿는 phase만 D다**(어느 wire request id/method가 timeout했는지로 이름 붙인다):
    `D-newSession` / `D-enforceModel` / `D-prompt`(도구 부재와 별도 분류. prompt phase에는 production
    경계가 없으므로 여기서의 horizon 만료는 production kill의 모사가 아니라 **inconclusive** 관측이다).
    `INITIALIZE_TIMEOUT_MS`도 기록은 하되 거기서의 실패는 위 P0·I0이지 **D가 아니다**.
    **B가 나와도 2026-07-24 3표본의 원인이 확정되지는 않는다** — controlled delay가 같은 증상을 만들 수 있다는
    causal sufficiency와 과거 incident attribution은 다른 주장이다. 도구 present 1회로는 A와 C를 구분하지
    못해 기제를 전면 반증하지도 못한다.
    **따라서 probe는 계측을 동반해야 한다:** fixture 프로세스 기동 → delay start/end → MCP transport
    connect/initialize/tool-list/tool-call, 그리고 client 쪽 **전체** ACP 시퀀스 — `newSession` start/end →
    `setSessionConfigOption(model)` start/end → prompt start/end. 여기서 set-model을 빠뜨리면 `enforceModel`
    정지가 C나 D로 오독된다.
    probe 자체의 호출 마커와 런타임 `No such tool`을 분리한다 — 모델 발화만으로 schema ordering을 추론하는 것이
    원래 3표본을 읽기 어렵게 만든 바로 그 실수다.
    **마커 정의가 A/C를 가른다 — 그리고 이걸 "ready"라고 부르지 않는다:** `server.connect()`도 initialize
    *수신*도 아니고, **fixture handler의 return도 아니다**(직렬화와 write에 걸리는 만큼 마커가 앞당겨진다).
    구현 가능한 한 점으로 고정한다 — **`tools_list_response_forwarded`** = MCP-side wire proxy가 기대 도구가
    담긴 `tools/list` 응답 프레임 **전체**를 downstream stdio에 `write()`하고 **write callback을 받은 시점**.
    이것은 **wire-availability proxy**이지 readiness가 아니다(바이트를 넘겼다는 뜻이지 client가 파싱·설치했다는
    뜻이 아니다) — 모든 기술에서 계속 wire-availability로 부른다. **실제 callability는 오직** 기대 도구에 대한
    `tools/call` 요청이 fixture에 도달한 별도 마커로만 확정한다. 그래서 ACP 쪽 proxy와 **별도로** fixture/MCP 쪽
    wire 계측이 필요하다. 최소 비교는
    한 타임라인 위의 `tools_list_response_forwarded ↔ newSession end ↔ prompt request start`다. 모든 참여 프로세스는
    하나의 append-only NDJSON event log(`runId` + 공유 wall-clock + pid + monotonic per-process counter)에 쓴다.
    **client seam을 명시하지 않으면 이 계측은 실행 불가능하다** — 제품 turn loop를 고치지 않기로 했으므로
    ⓐ **ACP stdio wire proxy**(자식 stdio에 개입해 JSON-RPC 프레임을 타임스탬프; 실 production 경로를 관측)
    또는 ⓑ **probe 전용 raw client**(`smoke-acp-raw-turn-live`가 이미 하는 방식; 단 production sequence와
    동일한 호출·인자·순서임을 게이트로 묶어야 한다 — 아니면 lookalike를 재는 것) 중 하나를 명시적으로 고른다.
    `session ready` progress notice를 읽고 타이밍을 추정하는 것은 금지 — probe가 대체하려는 바로 그 간접추론이다.
    **probe가 답하는 질문은 좁다:** "이 서버는 지연된 MCP를 기다리는가, prompt가 먼저 열리는가, fail-loud인가."
    모든 처방이 이 사실에 의존하므로 값어치가 있지만, 이것은 인과 질문의 **입력**이지 결론이 아니다.
    probe는 backend 무관(operator MCP 서버 + paired control/intervention run)이라 `cortex acp serve`에도 그대로 겨눠 rail readiness 축의 "미측정"
    질문을 대칭 가정 없이 잴 수 있다.
- **repair/v2-core-debt 승격분 (2026-07-24):**
  - **[GLG 결정 대기 — 에이전트 무접촉] `core.hooksPath` 이중화.** 이 리포 `.git/config`의
    `core.hooksPath=.husky/_`가 전역 안전 레일(`~/repos/gh/agent-config/git-hooks`)을 덮는다.
    husky엔 `pre-push`가 없어 push 시 identity/secret 스캔이 0회 돈다(공개 리포라 원래 strict 대상).
    방향 ⓐ husky 훅이 전역 스캐너를 역방향 호출, ⓑ hooksPath를 전역으로 되돌리고 husky를 그 아래
    체인(전역 훅이 이미 `_delegate.sh`로 repo-local을 부르게 설계됨 — 설계 의도에 부합). 어느 쪽도
    에이전트가 임의로 바꾸지 않는다(AGENTS: hooksPath 변경은 GLG 명시 요청). 대체물 = push 전
    `bash ~/repos/gh/agent-config/git-hooks/_scan.sh range origin/<branch> HEAD` 수동 실행.
  - **[아는 채로 두는 한계] `check-fresh-cut-gate`의 Claude sentinel 봉인.** PATH-local
    sentinel(나머지 PATH 유지)이 store 게이트 회귀 시 Claude 접촉을 기록·차단(D8)하지만, 그 개입
    자체가 이 게이트의 어떤 셀도 claude floor 너머를 검증하지 못하게 한다 — 회귀 시 게이트는
    어차피 A/D8로 RED이므로 수용. 더 깨끗한 봉인은 없다: claude만 PATH에서 빼면 node/python3까지
    잃고, 통과하는 fake claude를 주면 셀의 의미가 바뀐다.
  - `@earendil-works/pi-ai/providers/all` loader alias 이행 검토 — pi 0.81+가 추가한 4번째 alias.
    `/compat`이 살아있어 강제 아님(deprecated 주석만 그쪽을 가리킴). 별도 단독 cut.
  - identity 계약 cut: `check-entwurf-session-identity`의 256-id 유일성 단언은 생일충돌 ~0.2%/run의
    확률 주장(2026-07-24 pre-commit 실발화 1회). 게이트 계약 재정의 vs 프로덕션 mint same-second
    충돌 가드(file-exists 재시도) 중 택일 — 후자면 게이트가 그 가드를 검증.
  - **기계가 말하는 장치:** 게이트별 마지막 PASS 시각을 기록하고 커밋이 건드린 rail과 대조해
    "X를 건드렸는데 X를 덮는 MUST 게이트 마지막 PASS가 N일 전"을 자동으로 말하게 한다 —
    A3(라이브 3종이 한 달 죽어 있던 사건)의 근본 처방. MUST-tier 신선도는 사람 규율(A4/VERIFY)만으로는 재발한다.
  - `smoke-agy-native-push-live` 실행(살아있는 `AGY_CONVERSATION_ID` 필요) + H7 이후 agy 배선 확인
    (claudecode GREEN이므로 확인만 남음).
  - C4 tail(선택): `PI_SESSION_ID` seam(pi host env → 번들 브릿지 envelope)의 결정적 게이트화 —
    live 증거는 `smoke-acp-bundled-mcp-live`가 이미 보유.
- **Post-0.10 meta-bridge:** #34 잔여(empirical probe 4종 + unread-mailbox heartbeat), Phase 4 GC 자동화
  (`--apply`/TTL/liveness 코드화), step 7 `entwurf_peers(includeMeta)` 발견성.
- ~~**Carried 0.9**~~ — 세 항목 전부 **주제 소멸**: `/gnew` T3 확장과 `/gnew` empty-session GC는
  명령이 #50 C2에서 삭제되며 대상을 잃었고, `entwurf.ts` source guard refinement는 v1 본체가 0.12
  cutover에서 제거되며 같이 사라졌다.
- **Dep bump(별도 트랙):** claude-agent-acp / ACP SDK bump는 `check-acp-sdk-surface`와 raw LIVE로 잠근다.
  ~~준비선 0.61.0 / 1.3.0~~ → **랜딩 완료(2026-07-24 `5f5a18d`, pi 0.82.0은 `dfa3967`)** — 다음 bump부터 이 트랙 절차 재사용. model forcing은 `session/set_config_option(configId="model")`.
  - **2026-07-27 bump — claude-agent-acp 0.61.0 → 0.62.0 (ACP SDK는 1.3.0 유지).** 이 트랙 절차대로 잠갔다:
    ⑴ `check-acp-sdk-surface`를 0.62.0 / claude-agent-sdk 0.3.219로 이동(핀·lock peer-resolution·runtime probe)
    후 PASS, ⑵ `LIVE=1 ./run.sh smoke-acp-raw-turn-live` **2026-07-27 10:49:15 KST 실행 → PASS**
    (launch source = `package:@agentclientprotocol/claude-agent-acp`, PATH fallback 아님; model `claude-sonnet-5`,
    `stopReason=end_turn`, NDJSON 32,593 bytes 캡처, EXIT=0). **성격: dependency refresh.** upstream `dist/`는 0.61.0과 바이트 동일이고
    변경은 선언 의존성뿐(claude-agent-sdk 0.3.217→0.3.219; devDep anthropic sdk는 우리에게 닿지 않음).
    `@anthropic-ai/sdk 0.100.1`은 유지 — 0.3.219의 peer floor를 실측했고 `>=0.93.0`으로 불변이라
    기계적 상향을 취하지 않는다(`@modelcontextprotocol/sdk ^1.29.0` → 1.29.0, `zod ^4.0.0` → 4.3.6 충족).
    **readiness race와 무관하다**: 0.62.0은 explicit readiness wait를 추가하지 않는다. 다만 transitive
    SDK가 움직였으므로 MCP startup timing이 동일하다고 주장하지 않는다 — 새 fence가 없다는 것만 확정이다.
  - **2026-07-30 bump — claude-agent-acp 0.62.0 → 0.63.0 + pi 0.82.1 → 0.83.0 (ACP SDK는 1.3.0 유지).**
    **성격이 직전 bump와 다르다: dependency refresh가 아니라 adapter-code 릴리즈다.** packed tarball
    137,294 → 142,084 bytes이고 `dist/acp-agent.js`·`dist/tools.js`·`dist/acp-agent.d.ts`가 모두 움직였다
    (upstream #923 denied-tool resolution, #916 tool_progress heartbeat keying, #917 Bash terminal meta keying;
    claude-agent-sdk 0.3.219→0.3.220). 그러므로 0.61→0.62의 byte-identical 논거를 재사용하면 안 된다.
    **우리 표면 도달은 좁고, 그것도 실측이다**: `backend.ts`가 `clientCapabilities: {}`를 보내고 어댑터는
    terminal meta를 `clientCapabilities._meta.terminal_output === true`로, subagent transcript를 대응 capability로
    게이팅하므로 둘 다 off. 다만 opt-in 아닌 metadata(`_meta.claudeCode.title`/`.subagent`)와 #916의 재키잉된
    heartbeat는 wire에 올 수 있고 현재 mapper가 무시할 뿐이다 — "전부 미도달"로 쓰지 않는다.
    `@anthropic-ai/sdk 0.100.1` 유지 — 0.3.220의 peer floor를 재실측했고 `>=0.93.0`으로 불변이다.
    pi 천장은 실측으로 올렸다: `packages/coding-agent/src/core/extensions/loader.ts`와 `packages/ai/src/compat.ts`가
    v0.82.1..v0.83.0 sha256 동일. **readiness race와 무관한 것은 이번에도 같다** — 세 fix 중 어느 것도
    readiness fence가 아니고 `mcpServerStatus()`는 여전히 호출되지 않는다.
    동반 계약 변경: pi 0.83의 `"pending"` stop reason과 `rawStopReason`을 채택해 ACP terminal set을 정직하게
    닫았다(§ACP stop reason 게이트 + `acp-stop-reason` mutant lane 6종).
  - **2026-07-31 bump — claude-agent-acp 0.63.0 → 0.64.0 (ACP SDK 1.3.0·claude-agent-sdk 0.3.220 유지).**
    **성격: 단일 기능 릴리즈.** upstream checkout(release `9cc5a09`)에서 직접 대조했고 기능 델타는
    `src/elicitation.ts` **+14줄 하나뿐**이다(commit `d7a65ce`) — AskUserQuestion form의 "Other" 자유입력
    필드에 공유 마커 `_meta._askUserQuestionCustomAnswer`를 붙여 Codex/Claude 브리지가 같은 표식을
    알아보게 한다. 배포 패키지 unpackedSize 529,638 → 530,740 B, fileCount 24 → 24. **런타임 의존성은 동일**
    (`@agentclientprotocol/sdk` 1.3.0, `@anthropic-ai/claude-agent-sdk` 0.3.220)이고, upstream lock의
    `@modelcontextprotocol/sdk` 1.29.0 → 1.30.0은 **그들의 dev 트리**다 — 우리 해석은 1.29.0 그대로다(실측).
    `@anthropic-ai/sdk 0.100.1` peer 해석도 재실측으로 불변.
    **도달성은 "기본 off"보다 강하다 — 소스 변경 없이는 닿을 수 없다.** `backend.ts`의
    `clientCapabilities: {}`는 config seam이 없는 하드코딩이라 upstream이 `elicitationSupport.form = false`를
    계산하고, `acp-agent.ts:5358`이 `AskUserQuestion`을 금지하며 `:5449`가 그 목록을 **concat**으로 합치므로
    오퍼레이터 `disallowedTools`로 제거할 수 없다. 방출 분기(`:4558`)도 같은 플래그에 걸린다. 유일한 레버인
    `clientCapabilities`를 entwurf가 설정으로 노출하지 않는다. **이 델타에 한정된 주장이고 다른 축으로
    일반화하지 않는다.** readiness race와도 무관하다 — elicitation 마커는 fence가 아니다.
  - **2026-08-07 bump — claude-agent-acp 0.64.0 → 0.65.0 + pi 0.83.0 → 0.84.0 (ACP SDK 1.3.0·claude-agent-sdk 0.3.220 유지).**
    **성격: adapter-code 릴리즈이되 선언 런타임 의존성은 움직이지 않았다.** 이건 앞선 두 성격 어느 쪽도
    아니다 — 0.61→0.62(dist 바이트 동일 + dep 이동)도, 0.62→0.63(dist 이동 + dep 이동)도 아니다.
    **앞의 논거를 재사용하지 않는다.** packed tarball 142,307 → 144,665 B, `dist/acp-agent.js`
    350,538 → 360,823 B·`dist/acp-agent.d.ts` 61,181 → 62,224 B만 움직였고 나머지 dist 파일
    (elicitation/index/lib/settings/tools/utils, .js+.d.ts)은 전부 바이트 동일, fileCount 24 → 24.
    선언 의존성은 동일(`@agentclientprotocol/sdk` 1.3.0, `@anthropic-ai/claude-agent-sdk` 0.3.220, `zod` 동일).
    - **순 기능 델타는 둘뿐이다**(upstream checkout `v0.64.0..v0.65.0`). `src/` 아래 **런타임/프로덕션
      소스**로 움직인 것은 `src/acp-agent.ts` 한 파일(+280줄)뿐이다 — repo 전체 diff는 이보다 크고
      그걸 비었다고 주장하지 않는다(`src/tests/acp-agent.test.ts`, 신규 706줄 `examples/simple-client.ts`,
      CI/release manifest, lockfile). 그 어느 것도 배포 tarball에 실리지 않는다(파일 수 24 불변):
      #930 `08a62ed`(0.64.1) 구조화된 permission 변경을 option-level `_meta.permission`으로 노출하고 버튼을
      Deny/Allow Once/Always Allow로 재라벨링, #958 `a84b810`(0.65.0) **steered turn을 interrupt의 result가
      아니라 SDK `idle`에서 settle**. #938 ExitPlanMode Markdown은 0.64.1에 들어왔다 0.64.2에서 되돌려졌으므로
      (`4302a4b`) 0.65.0 기준 순 델타 0 — 건너뛴 중간 버전에 숨은 변화는 없다.
    - **도달성은 기능별로 따로 실측했다.** #930은 **우리 wire에 실제로 온다** — entwurf는
      `session/request_permission`을 답한다. 그럼에도 무해한 이유는 실측된 것이다: 우리
      `resolvePermissionResponse`는 라벨이 아니라 **`kind`**(`allow_once`/`allow_always`)로 고르고, 0.65.0도
      그 kind와 optionId(`reject`/`allow`/`allow_always`)를 그대로 낸다(`acp-agent.ts:4885-4890`).
      즉 "기능이 off"가 아니라 **라벨 독립성** 주장이다. #958은 **구조적으로 미도달**이다 —
      새 분기는 전부 `isSteering(turn)` 가드이고 `steeredEchoes`는 `session/steer` 핸들러
      (`agent.steer`, `:1922`/`:7880`)에서만 채워지는데 entwurf ACP 클라이언트는
      initialize/newSession/prompt/setSessionConfigOption/cancel만 보낸다. 가드 아닌 유일한 수정
      (`owesTrailingIdle`)도 비-steering에서 `true`로 접혀 이전 조건과 동치다.
      (entwurf MCP의 `mode:"steer"`는 우리 control-socket 주입 방식이고 ACP steering과 무관하다.)
      공개 export `describeAlwaysAllow` 제거도 미도달 — 우리는 어댑터 심볼을 import하지 않고 bin만 spawn한다.
    - **pi 천장은 실측으로 올렸고, byte-identical 논거는 이번엔 성립하지 않는다.** `packages/ai/src/compat.ts`는
      v0.83.0..v0.84.0 sha256 동일(`c1212487…`)이지만 **`loader.ts`는 다르다**(`2498fc18…` → `288a8842…`).
      그 diff 내용으로 올렸다: alias 표 불변(4개 그대로, `pi-ai` → compat 엔트리), `readPiManifest`는
      `core/pi-manifest.ts`로 이동한 순수 리팩터(같은 `pi.extensions` 계약), `registerMarkdownTransformer`는 가산,
      새 jiti `virtualModules`/`tsconfigPaths` 분기는 **pi 자신이 .ts 소스로 돌 때만** 걸린다. 유일한 행위 변화인
      `ExtensionAPI.events`의 liveness assert + `invalidate` 해제는 entwurf에 닿지 않는다 — 우리는 event-bus
      핸들러를 하나도 등록하지 않는다(실측).
    - **pi 런타임 별자리가 커졌다.** `pi-coding-agent`의 `@earendil-works` caret 집합이 0.83.0의
      {agent-core, ai, tui}에서 0.84.0의 {agent-core, ai, **client**, **protocol**, tui}로 늘어,
      `check-pack-install`이 `pi-client`/`pi-protocol`을 처음으로 핀한다(미핀 시 float — 2026-07-21 사건과 같은 부류).
    - `@anthropic-ai/sdk 0.100.1` 유지 — 0.3.220의 peer floor를 **재실측**했고 `>=0.93.0`으로 불변이다
      (`@modelcontextprotocol/sdk ^1.29.0` → 1.29.0, `zod ^4.0.0` → 4.3.6 충족). 기계적 상향을 취하지 않는다.
    - **readiness race와 무관하다** — 두 기능 어느 것도 readiness fence가 아니고 `mcpServerStatus()`는 여전히
      호출되지 않는다. 다만 `dist/acp-agent.js`가 10KB 움직였으므로 런타임 타이밍이 동일하다고 주장하지 않는다.
    - **streamSimple hook 계약 (#63, 실측 종결).** pi 0.84가 `ProviderConfig.streamSimple` 구현 의무로 문서화한
      `onPayload`/`onResponse`(upstream #7372 → PR #7576, `f27aaf66c`)는 **JSDoc-only 변경**이고, 동기는 HTTP
      status/headers 기반 telemetry 확장(pi-otel)이 커스텀 provider에서 조용히 죽는 사고다 — 비-HTTP transport
      의미론은 upstream 어디에도 없다. entwurf의 채택: **onPayload는 진실한 매핑** — 실제 provider request인
      ACP `session/prompt` `{sessionId, prompt}`를 send 직전(new/reuse 양쪽)에 넘기고 replacement를 wire에 쓰되,
      non-null·non-array object + bootstrapped sessionId 불변 + 비어있지 않은 prompt array를 fail-closed로
      요구한다. **onResponse는 의도된 로컬 비-HTTP
      exemption** — `ProviderResponse`는 `{status, headers}` 하드타입이고 ACP terminal result는 body(알림) 소비
      **후**에 오므로 어떤 호출도 HTTP 증거 날조다; 절대 호출하지 않고 그 부재를 `check-acp-stream-hooks`가
      behavioral하게 결박한다(`acp-stream-hooks` mutant lane 10종). reuse 턴에서 payload-rewriting 확장이 backend
      세션 기억과 pi transcript를 어긋나게 할 수 있는 것은 built-in에도 동일하게 주어진 upstream 권한이며,
      새 fence를 세우지 않고 여기 기록만 남긴다.
  - **2026-08-07 bump — pi 0.84.0 → 0.84.1 (claude-agent-acp 0.65.0·ACP SDK 1.3.0 유지).**
    **성격: patch 릴리즈, 도달 계약 전부 불변/가산.** compare `v0.84.0...v0.84.1`(release `53fa77c`)은
    30 commits/137 files이지만 load-bearing 파일들이 compare set에 아예 없다 — `packages/ai/src/compat.ts`,
    coding-agent `core/extensions/loader.ts`·`core/agent-session.ts`·`core/session-manager.ts`, 그리고 #63
    hook 배선인 `core/sdk.ts`·`core/extensions/runner.ts` 전부 바이트 동일. `SimpleStreamOptions`/
    `ProviderResponse` 타입 불변(ai/types.ts 델타는 `qwen-token-plan-individual` KnownProvider 가산 하나).
    reachable 후보 판정: `ToolCallEventResult.terminate`(가산; 우리는 tool_call 핸들러 미등록),
    `Agent.reset()` active-run 거부(미호출), tool prompt contribution export 리팩터+PI-env 문구 완화
    (pi-native 표면), `pi auth check` preflight/auth-command 리팩터(CLI 전용; 우리 고정 argv는 help-text
    델타뿐), `ModelRuntime.refreshOnCreate`(opt-in 가산) — 전부 미도달. Qwen Individual/SQLite backend
    (별도 패키지, coding-agent 의존성 아님)/TUI/Harness factory/Bun 바이너리는 소스+패키지 별자리로
    out-of-surface 확인. npm 실측: 외부 의존성 버전 전부 동일(openai 6.26.0, @anthropic-ai/sdk 0.91.1,
    typebox 1.3.7 등), caret 멤버십 불변({ai, tui, client, protocol, agent-core}+telemetry), coding-agent
    fileCount 956→968(+86,748B), pi-ai 725→734(Qwen 모듈). **하드 미니멈 판정: floor를 당시 exact
    devDep 0.84.1 + next-minor ceiling 0.85로 기계적 이동**(run.sh가 devDep에서 peer 유도,
    `check-dep-versions`가 오라클, `check-pack-install` 6-row 핀 이동). 새 behavioral gate 불요 —
    entwurf가 진술하는 계약 변화 없음. (현재 certified floor는 이후 항목의 0.84.3.)
  - **2026-08-08 bump — claude-agent-acp 0.65.0 → 0.66.0 (pi 0.84.1·ACP SDK 1.3.0·claude-agent-sdk
    0.3.220 유지).** **성격: 선언 런타임 의존성 불변의 adapter-code 릴리즈 + 신규 optional extension
    모듈.** 릴리즈 델타 3건 — #960 dev-dep `globals` 17.8→17.9(그들의 dev 트리, 우리 해석 무관),
    #964 provider-neutral ACP goal extension 노출(신규 `dist/goal-extension.{js,d.ts,d.ts.map}` 3파일,
    initialize 응답 top-level `_meta.goal`로 `_session/goal` control method 광고), #967 goal
    publish/replace 신뢰성 fix(우리가 안 쓰는 goal 경로 내부). npm 실측: unpackedSize 542,197 →
    554,124 B, fileCount 24 → 27(+goal-extension 3종), 런타임 deps 동일(zod range 포함).
    **도달성은 축별로 갈린다 — "전부 미도달"이 아니다.** ⑴ 발신: entwurf는 `_session/goal`을 보내지
    않고 initialize `_meta` 확장 광고를 소비하지 않는다 — #958 steering과 같은 구조적 미도달.
    ⑵ **`/goal` prompt 경로 — 비치환·가산적(가로채기 아님)**: 어댑터는 `/goal`을 local-only 명령
    집합(`/context`·`/heapdump`·`/extra-usage`)에 넣지 않았고, 프롬프트는 `session.input.push`로
    **무조건 모델에 그대로 전달**된다. `publishGoalFromPrompt`는 그 push **뒤에** `session_info_update`
    알림 하나를 추가로 낼 뿐 input을 치환/억제하지 않는다(acp-agent.js L290/L993/L995 실측; Opus B1
    정정 2026-08-08 — 최초 기록과 커밋 `6929148` 메시지의 "모델에 전달되는 대신 가로챈다"는 문장은
    코드가 구현하지 않는 메커니즘이며 **이 원장이 SSOT로 대체한다**). 발신·prompt 두 축은
    미도달로 접히고, 남는 것은 ⑶의 수신 알림 하나뿐이다 — 그것도 wire에는 오를 수 있으나 mapper가
    무시해 무해(inert)하다. 행동 변화 없음. ⑶ 수신:
    Claude runtime `active_goal` → `sessionUpdate: "session_info_update"` + `_meta.goal`은 wire에 올 수
    있고 우리 event-mapper switch의 `default: break`가 무시한다(#916 heartbeat와 같은 부류, 실측).
    readiness와 무관 — goal extension은 fence가 아니고 `mcpServerStatus`는 0.66.0 소스에도 부재.
    peer 재실측: claude-agent-sdk 0.3.220 불변이므로 `@anthropic-ai/sdk 0.100.1` peer-pin 유지
    (vitest L2 lane이 lockfile bytes로 결박). pnpm minimumReleaseAge가 어제 릴리즈를 게이트해
    `pnpm-workspace.yaml` exclude 항목이 추가됐다(도구 생성, 커밋에 포함).
  - **2026-08-16 bump — claude-agent-acp 0.66.0 → 0.68.0 + pi 0.84.1 → 0.84.2 (ACP SDK 1.3.0 유지,
    claude-agent-sdk 0.3.220 → 0.3.232).** Issue #79 certification. **성격: 이중 런타임 핀 이동 +
    AIR typed-failure 서버 능력 가산(미광고) + Claude Agent SDK patch 점프.**
    ⑴ **pi 0.84.2** — patch monorepo cut. installed dist sha256 prefixes (16 hex):
    `loader.js` `0fd56e37765a0e43`, `sdk.js` `225053853f1a0bee`, `runner.js` `b39d59b8f86693b9`,
    `agent-session.js` `9f065b4a277857db`, `session-manager.js` `af809d47818a3bf6`,
    pi-ai `compat.js` `cde63dcc0cd41976`. `assertValidSessionId` + `--session-id` 잔존; session-manager의
    user-facing 문자열만 `APP_NAME` 치환 — identity mint/동기 반환 표면 불변(mux-launch-rail §6에
    0.84.2 한 줄 append). `sendMessage`는 `triggerTurn:true` 분기 유지(우리 delivery 경로); `false`
    수정은 미도달. `defaultTools`는 settings-manager 키로 존재하고 extension tool 보존 fix가 릴리즈
    노트에 명시 — pack consumer + extension 등록 gate로 잠금. caret 별자리 불변
    `{agent-core,ai,client,protocol,tui}@^0.84.2` (+telemetry 전이). floor 기계 이동: exact devDep
    `0.84.2` + peer 하한 0.84.2·상한 next-minor + `check-pack-install` 6-row + baseline docs.
    (당시 표기를 range 선언 패턴에서 뺐다 — `check-dep-versions`는 baseline doc의 range 선언 전부를
    현재 핀과 대조하므로, ledger 역사 줄은 그 패턴을 그대로 실으면 다음 bump에서 거짓 red가 된다.)
    ⑵ **claude-agent-acp 0.68.0** — 0.67.0 포함 11 commits. 선언 deps 실측:
    `@agentclientprotocol/sdk@1.3.0`, `@anthropic-ai/claude-agent-sdk@0.3.232`,
    `zod ^3.25||^4`. lock peer-resolve: `claude-agent-acp@0.68.0(@anthropic-ai/sdk@0.100.1…)` +
    `claude-agent-sdk@0.3.232(@anthropic-ai/sdk@0.100.1…)` (vitest L2). cas peers 재실측:
    `@anthropic-ai/sdk >=0.93.0` 불변 → pin `0.100.1` 유지; MCP `^1.29.0` → L2c 1.29.x; zod `^4`
    (tree already `4.3.6`). **AIR:** `supportsAirSessionFailures(capabilities)`는 JetBrains
    `_meta` extension version+capability 광고를 요구; entwurf `clientCapabilities: {}` → false →
    레거시 `RequestError.internalError` rawDetail 경로 유지. `session-failure-extension.js` 신규
    모듈은 서버 측 존재하나 미광고 클라이언트에는 미활성. `mcpServerStatus` 0.68.0 dist 부재.
    plan/Skill `_meta`/model-fallback은 mapper forward-compat. AIR enable은 별도 feature(non-goal).
    ⑶ **#72 비청구** — typed failure ≠ retained-child mid-tool-loop death. 이 bump로 #72를 닫거나
    약화하지 않는다.
    ⑷ pnpm `minimumReleaseAgeExclude`에 0.84.2 / 0.67.0 / 0.68.0 추가.
  - **2026-08-19 bump — claude-agent-acp 0.68.0 → 0.70.0 (pi 0.84.2·ACP SDK 1.3.0·claude-agent-sdk
    0.3.232 유지).** Issue #81 support-contract 인증. **성격: 비활성 minor 2개를 한 인증에 접음 —
    별자리 이동 없음.** 이전 bump의 논거를 재사용하지 않고 0.69.0/0.70.0 각각을 재측정했다.
    ⑴ **선언 deps 실측(0.68.0 = 0.69.0 = 0.70.0, 완전 동일)**: `@agentclientprotocol/sdk@1.3.0`,
    `@anthropic-ai/claude-agent-sdk@0.3.232`, `zod ^3.25||^4`, `engines.node (upstream major 22)`. lock peer-resolve
    재측정: `claude-agent-acp@0.70.0(@anthropic-ai/sdk@0.100.1(zod@4.3.6))(@modelcontextprotocol/sdk@1.29.0…)`
    + `claude-agent-sdk@0.3.232(@anthropic-ai/sdk@0.100.1…)`. anthropic peer pin `0.100.1` 유지,
    MCP 1.29.0 / zod 4.3.6 유지. **dependency constellation 불변 + Entwurf reachable default
    behavior 불변**이 이 bump의 주장이다 — upstream 자체는 0.69/0.70에서 기능을 추가했으므로
    "동작 변경이 없다"고 뭉뚱그리지 않는다. 아래 ⑵⑶이 각 기능의 비도달 근거를 따로 세운다.
    ⑵ **0.69.0 — AIR `agentFileChangeReport`(opt-in).** `file-change-audit.js:supportsAgentFileChangeReport(caps)`가
    `caps._meta`의 JetBrains AIR extension version + capability 광고를 요구한다. entwurf는
    `clientCapabilities: {}` (backend.ts:1228) → `air?.version === AIR_EXTENSION_VERSION`이 false →
    비활성. #79의 AIR typed-failure와 정확히 같은 gate 구조이므로 default path 비도달.
    ⑶ **0.70.0 — loaded session의 `providers/list`·`providers/set`·`providers/disable`.**
    adapter 소스 주석 실측: "Advertised unconditionally; there is no client capability prerequisite
    for the provider methods" (acp-agent.js:708-710). 즉 **capability gate가 없다** — AIR와 다르다.
    도달성은 호출 여부로 갈린다: entwurf 소스 전체에서 `providers/*` 및 `logout` 호출이 0건(유일한
    grep hit은 무관한 CLI argv 픽스처 `check-probe-cli-shim.ts:539`). 이 메서드들은 client가 부르는
    것이고 우리는 부르지 않으므로 process-wide provider 상태 전이가 일어나지 않는다. **"gate가
    없으니 안전하다"가 아니라 "호출하지 않으므로 비도달"이 이 칸의 논거다** — 앞으로 우리가
    provider 전환을 쓰기로 하면 이 판단은 즉시 무효가 된다.
    ⑷ **#72 비청구**: 이 bump는 retained-child mid-tool-loop death를 닫거나 약화하지 않는다. MCP
    readiness fence도 여전히 없고(11-7), AIR 채택도 non-goal 그대로다.
    ⑸ pnpm `minimumReleaseAgeExclude`에 0.69.0 / 0.70.0 추가. 버전 선언 이동: `package.json`
    dependency, `test/acp-sdk-surface.contract.test.ts` PINS + L2 lock regex, `smoke-acp-raw-turn-live.ts`
    헤더, `docs/acp-backend-rail.md` 지원 matrix + 11-7.
  - **2026-08-25 bump — pi 0.84.2 → 0.84.3 (claude-agent-acp 0.70.0·ACP SDK 1.3.0·claude-agent-sdk
    0.3.232 유지).** 0.15.0 전 GLG 지정 dependency checkpoint. **성격: patch monorepo cut —
    별자리만 이동, 새 제품/게이트 설계 없음.** upstream tags `v0.84.2=914cf147` → `v0.84.3=4e58f324`
    (checkout `/tmp/pi-v0843-impact-review-703071`; Terra 리뷰 `20260825T122349-bb39ac` 판정을 이
    세션이 해시로 재측정).
    ⑴ **`packages/ai/src/compat.ts` 양 tag sha256 `c1212487…` 바이트 동일.** `loader.ts`는
    `288a8842…`→`1cf00caa…`로 움직였고 디프를 직접 판독했다: Bun 한정이던 virtualModules를
    SEA/bundled-node 이진으로 일반화 + extension factory 등록의 transactional화(loading 중 등록을
    buffering 후 commit/discard, 실패 시 API 비활성 throw). alias map 불변, entwurf extension의
    도달 계약(등록→session_start 활성)은 보존으로 판정 — 성공 로드 경로에서 commit이 즉시 불린다.
    ⑵ `session-manager.ts` 델타는 branch_summary `fromId` 북키핑 한 건(분기 전 leaf 기록) —
    identity mint / `--session-id` / 동기 id 반환 표면 불변 (mux rail §6 재확인 문단에 .3 추가).
    ⑶ GoogleThinkingLevel rename: repo import 0건 (Terra 실측 상속; grep 재확인).
    ⑷ 기계 이동: devDep exact `0.84.3` + peer 하한 0.84.3·상한 next-minor, pnpm-lock 7-패키지 별자리
    (agent-core/ai/client/coding-agent/protocol/telemetry/tui) 0.84.3 정렬,
    `minimumReleaseAgeExclude` 7종에 0.84.3, `check-pack-install` 직접 핀·leak 단언·주석,
    게이트 소유 baseline 문서 5곳(`check-dep-versions` BASELINE_DOCS = AGENTS.md·README.md·
    ROADMAP.md·docs/setup-clean-host.md·demo/README.md). `docs/acp-backend-rail.md`도 갱신했으나
    이는 게이트 입력이 아닌 live 지원 프로스다. 게이트 신설 없음 — `check-dep-versions`/runtime
    range 게이트의 도출이 그대로 authority.
    ⑸ 독립 리뷰가 이 bump와 무관하게 잠복해 있던 false-green을 찾았다: `check-pack-install`의
    pin-leak matcher가 무경계 substring(`grep -v '@0\.84\.x'`)이라 `@0.84.30` lookalike를
    통과시켰다. 경계 있는 matcher(`@0\.84\.3(_|$)`, pnpm .pnpm 표기 실측)로 수리하고 합성
    lookalike 자기시험 셀 `[QK:PACK-INSTALL-PIN-MATCHER-BOUNDED]` + `pack-install` mutant lane
    1종(무경계 복원)으로 kill-proof를 세웠다.
  - **2026-09-02 bump — claude-agent-acp 0.70.0 → 0.73.0 + ACP SDK 1.3.0 → 1.4.0 + claude-agent-sdk
    0.3.232 → 0.3.257 (pi 0.84.4 유지).** Issue #93 accounting 수리의 **전제**다 — refresh가 아니다.
    **성격: adapter-code 릴리즈 3개 minor를 한 인증에 접음.** upstream tags `v0.70.0..v0.73.0`
    16 commits, `src` 46 files `+19,504/−7,290` (checkout `~/repos/3rd/claude-agent-acp`).
    이전 bump의 논거를 재사용하지 않고 0.71.0/0.72.0/0.73.0을 각각 재측정했다.
    ⑴ **선언 deps 실측(tag별로 다르다)**: 0.70.0 = `sdk 1.3.0`·`claude-agent-sdk 0.3.232`·
    `zod "^3.25.0 || ^4.0.0"` → 0.71.0 = `1.3.0`·`0.3.238`·`zod "^4.0.0"` → 0.72.0 = `1.4.0`·`0.3.252`·
    `^4.0.0` → 0.73.0 = `1.4.0`·`0.3.257`·`^4.0.0`. `engines.node (upstream major 22)` 전 구간 불변.
    **zod 하한이 0.71.0에서 좁혀졌다**(`7c66108`, v4 directory import 실패 회피) — 우리 lock은
    `zod@4.3.6`으로 이미 그 안에 있어 이동 없음. lock peer-resolve 재측정:
    `claude-agent-acp@0.73.0(@anthropic-ai/sdk@0.100.1(zod@4.3.6))(@modelcontextprotocol/sdk@1.29.0(zod@4.3.6))`
    (`pnpm-lock.yaml:1506`) + `claude-agent-sdk@0.3.257(@anthropic-ai/sdk@0.100.1…)` (`:1543`).
    anthropic peer pin `0.100.1` 유지 — `>=0.93.0` floor 불변이라 기계적 상향을 취하지 않는다.
    ⑵ **adapter 16 commits 중 도달하는 변경은 정확히 하나다(SDK 축은 ⑸에서 따로 판정):
    `fad4d10` "report per-model token usage on prompt responses"
    (#1037, 0.71.0).** 이것이 `_meta.quota.model_usage` = `turnQuotaMeta()`를 낳았다. 실측:
    `git grep -c turnQuotaMeta -- src`가 v0.70.0에서 **0 hits**, v0.71.0/v0.72.0/v0.73.0에서 2 hits.
    #93의 `readTurnAccounting()`이 소비하는 numerator가 곧 이것이므로, **핀 이동 없이는 그 수리의
    주 경로가 죽는다** — 커밋 순서가 핀 → accounting이어야 하는 이유.
    ⑶ **도달하지 않는 신규 표면(호출 0건, 광고만)**: native subagents + async tasks (#1017),
    message-specific session forks (#1046), AI 생성 session title (#984), permission mode kinds (#1025),
    Claude modes / clear-context planning (#1004), per-model effort settings (#1065).
    `providers/*` trio와 같은 등급 — call-site 규율로만 unreachable이다.
    ⑷ **readiness 재측정(§11-7 갱신).** `mcpServerStatus` 호출이 `src/acp-agent.ts`에서 v0.70.0 0건 →
    v0.73.0 2건으로 **새로 생겼다**(`0cbbaf3`, MCP OAuth/LLM-25012). 두 site를 직접 판독
    (`v0.73.0 src/acp-agent.ts:1618`, `:1711`): 둘 다 `supportsMcpOAuth(query)` 뒤에 있고, polling 쪽은
    이미 `needs-auth`를 보고한 서버 하나만 기다린다 — `newSession` 전에 선언된 전체 MCP를 막는
    fence가 아니다. **결론은 유지되지만 근거는 새로 측정한 것이고, entwurf 쪽 호출은 여전히 0건**
    (`pi-extensions/`·`mcp/`·`scripts/` 실측). #72는 여전히 닫히지 않는다.
    ⑸ **ACP SDK 1.3.0 → 1.4.0의 도달 판정(별도 축).** 1.4.0은 스키마 표면을 **둘** 싣는다:
    `dist/schema/types.gen.d.ts:3001`의 `StopReason`은 여전히 닫힌 5-리터럴이고,
    `dist/v2/schema/types.gen.d.ts:3607`은 `… | "cancelled" | string`으로 **열려 있다**.
    후자는 package `exports`의 `./experimental/v2`로만 닿고, entwurf는 bare specifier를 import해
    `./dist/acp.js`(v1)로 해석된다(실측). 따라서 `mapAcpStopReason`의 "터미널 집합은 닫혀 있다"는
    주장은 1.4.0에서도 유지되지만 **그 근거가 바뀌었다** — 이제 bare import가 유지되는 동안에만
    참이다. `backend.ts`와 `check-acp-stop-reason.ts` 주석에 그 조건을 명시했다.
    ⑹ **트랙이 지정한 잠금 2종 실행.** `check-acp-sdk-surface`(vitest 7/7 PASS: PINS·L2 lock
    peer-resolve·L2b/L2c runtime probe가 1.4.0/0.73.0/0.3.257로 이동) + **`LIVE=1 ./run.sh
    smoke-acp-raw-turn-live` 2026-09-02 17:01 KST 실행 → PASS**
    (launch source = `package:@agentclientprotocol/claude-agent-acp`, PATH fallback 아님;
    model `claude-sonnet-5`, `protocolVersion=1`, `stopReason=end_turn`, NDJSON 58,189 bytes 캡처,
    EXIT=0). `check-dep-versions`도 green(pi 0.84.4 coherent).
    ⑺ 기계 이동: `package.json` 두 dependency, `pnpm-workspace.yaml`
    `minimumReleaseAgeExclude`에 0.71.0/0.72.0/0.73.0 + claude-agent-sdk 0.3.257 9종(플랫폼 optional
    포함), `pnpm-lock.yaml`, `test/acp-sdk-surface.contract.test.ts` PINS + L2 lock regex + L2b/L2c
    runtime probe, `docs/acp-backend-rail.md` 지원 matrix + §11-7, `scripts/smoke-acp-raw-turn-live.ts`
    헤더. 게이트 신설 없음 — `check-acp-sdk-surface`/`check-dep-versions`의 도출이 그대로 authority.
  - **2026-09-06 bump — pi 0.84.4 → 0.85.1 (0.85.0 은 건너뛴다).** #104. `~/repos/3rd/pi/pi-mono`
    `v0.84.4..v0.85.1`. **0.85.0 은 랜딩 대상이 아니다:** `[측정]` `npm view` 로 읽은 0.85.0
    pi-coding-agent 의 `exports` 가 `./client` 와 `./experimental/plugin` 을
    `dist/*` 로 광고하는데 그 파일들이 publish 에 없다. 벤더 CHANGELOG 0.85.1 이 그것을 "SDK import
    failures caused by unintentionally publishing internal experimental code and dependencies in
    0.85.0" 로 이름 붙이고 두 서브패스를 `source` 전용으로 되돌린다. 우리 import 0건이라 도달하진
    않지만 좌표는 0.85.1 이다.
    ⑴ **하중 파일 sha256 (0.85.0→0.85.1, 앞 12; 0.84.4→0.85.0 논거 재사용 없음):** SAME
    `ai/src/compat.ts` `c1212487653e` · `coding-agent/src/core/extensions/loader.ts` `7e0e3a709946` ·
    `.../runner.ts` `6d5101ab0551` · `.../api.ts` `e3b0c44298fc` · `.../sdk.ts` `938f9f3d4845` ·
    `.../pi-manifest.ts` `cdeed96fef83` · `.../agent-session.ts` `23e4acac8446` ·
    `.../session-manager.ts` `57bc70a75156`. DIFF 하나 — `ai/src/types.ts` `7f2a2d650ff8` →
    `ae0427bfba13`, **전량 22줄 JSDoc 2 hunk**(GPT-5.6+ prompt-cache 문구), 타입 멤버 변경 0.
    0.85.0→0.85.1 규모 13 commits / 68 files / +751 −390.
    ⑵ **도달한 것 — upstream 미선언 breaking 1건(우리가 실측):** `pi-tui` `Container` 가
    0.85.x 에서 `private mouseLayout?` 를 얻었다(`dist/tui.d.ts:198`; 0.84.4 의 `Container` 는
    private 멤버가 아예 없었다). `Box` 는 자기 소유의 별개 `private mouseLayout` 을 선언하므로
    TypeScript 의 private-멤버 동일선언 규칙에 걸려 `Box → Container` 구조적 할당이 TS2322 로 깨졌다
    (`entwurf-control.ts:551` `buildSentMessageBox` 반환 타입). upstream Breaking 절은
    `createGatewayBindingFetch` 만 이름한다 — 이건 **미선언**이고, #99 정찰의 "계약 파손 후보 8개
    전부 미도달"이 `packages/tui` 를 안 읽어서 놓친 자리다. 수리는 벤더 계약이 실제로 요구하는
    인터페이스로 좁힌 것: `MessageRenderer` 는 `Component | undefined` 를 원한다
    (`pi-coding-agent dist/core/extensions/types.d.ts:889`). `Container` 는 애초에 필요하지 않았다.
    ⑶ **별자리가 `pi-` 밖으로 커졌다 — 게이트 구멍 하나 동봉 수리.** `@earendil-works/chord` 는
    0.85.0 신규이고 pi-coding-agent · pi-agent-core · pi-client · pi-protocol 의 runtime
    `dependencies` 다(`[측정]` `npm view <pkg>@0.85.1 dependencies`). `[측정]` 실제 0.85.1 설치
    트리의 `.pnpm` 목록에 `@earendil-works+chord@0.85.1` 이 있고, `run.sh` 의
    `pack_install_leaked_pi` 는 `^@earendil-works+pi-` 접두사라 그것을 **못 본다** —
    `run.sh:3394` 의 "covers ... any package a future pi bump adds to the closure" 주석이 거짓이
    되는 자리다. matcher 를 org 접두사로 넓히고 chord 를 8번째 명시 핀으로 넣었다. 부수 측정:
    peer-hash 접미사가 `_ws@8.21.3` 이라는 새 모양으로 나오는데 `(_|$)` 경계가 그대로 흡수한다 —
    두 모양 다 픽스처에 박았다. 새 claim `[QK:PACK-INSTALL-PIN-MATCHER-COVERS-CLOSURE]` +
    mutant 1종(접두사를 `pi-` 로 되돌림) 신설, 기존
    `[QK:PACK-INSTALL-PIN-MATCHER-BOUNDED]` 는 새 경계로 이동. 뮤턴트 368 → **369**, lane 40 불변.
    ⑷ **부수 하나 — esbuild.** chord 의 유일한 의존이 esbuild 라 `pnpm install` 이
    `ERR_PNPM_IGNORED_BUILDS` 로 결정을 요구했다. `allowBuilds: esbuild: false` (기존 두 항목과
    같은 거부). 우리는 esbuild 를 실행하지 않는다.
    ⑸ **기계 이동:** `package.json` devDep 3종 exact `0.85.1` + peer `>=0.85.1 <0.86` 3종,
    `pnpm-workspace.yaml` `minimumReleaseAgeExclude` 7종 + chord 행 신설, `run.sh`
    pack-install 핀 7→8행 · matcher · 자기시험 2셀 · `:3394` 주석 · `check-dep-versions` 주석,
    `scripts/mutants/pack-install.json`, `scripts/check-gate-qualification.ts` lane inventory,
    `pnpm-lock.yaml`, baseline 문서 5곳(AGENTS/README/ROADMAP/setup-clean-host/demo) +
    `docs/acp-backend-rail.md` 지원 matrix + `VERIFY.md`(그 자리는 어느 게이트도 읽지 않아
    0.84.3 세대에 멈춰 있었다 — BASELINE_DOCS 밖이라 두 번의 bump 를 그냥 지나쳤다).
  - **2026-09-06 bump — claude-agent-acp 0.73.0 → 0.75.1 (ACP SDK 1.4.0 · claude-agent-sdk
    0.3.257 유지).** #104, pi 범프와 같은 랜딩이지만 **다른 원인**이다.
    ⑴ **선언 deps 를 태그별로 실측 — 네 태그 전부 불변:** v0.73.0 / v0.74.0 / v0.75.0 / v0.75.1 모두
    `@agentclientprotocol/sdk 1.4.0` · `@anthropic-ai/claude-agent-sdk 0.3.257` · `zod ^4.0.0` ·
    `engines.node (upstream major 22)`. **움직이는 핀은 `claude-agent-acp` 하나뿐**이다. claude-agent-sdk 가
    제자리이므로 그 `>=0.93.0` anthropic peer floor 도 불변 → `@anthropic-ai/sdk 0.100.1` 유지
    (기계적 상향 금지, 0.62.0 bump 규율 그대로). lock 재측정:
    `claude-agent-acp@0.75.1(@anthropic-ai/sdk@0.100.1(zod@4.3.6))(@modelcontextprotocol/sdk@1.29.0(zod@4.3.6))`
    (`pnpm-lock.yaml:1663`).
    ⑵ **8 commits / `src` 18 files +6354 −491 중 도달하는 변경은 정확히 하나:** `f74a517`
    (0.75.0, #991) 압축의 ACP tool lifecycle 화. `[측정 2026-09-06]` LIVE `/compact` 한 턴이
    `tool_call(kind:"think", "Compact conversation")` → `tool_call_update` 두 알림을 내고, 그
    알림을 프로덕션 `applyAcpSessionUpdate` 에 그대로 재생하면 `[tool:start]`/`[tool:…]` 공지 쌍이
    된다. 타입 파손 아님(`renderToolUpdate` 는 kind 무관), `_meta.contextCompaction` 은 매퍼가
    버리므로 회계 경로 무관. **바뀐 것은 운영자가 보는 것**이다. 영수증·한계(성공 분기 미관측):
    `scripts/raw-acp-compaction-measure/README.md`, 계약은 `docs/acp-backend-rail.md` §11-8.
    ⑶ **도달하지 않는 신규 표면:** `authStatus` 확장(0.75.0 #1080), usage markdown 렌더
    (0.75.0 #1085), session fork 복구(0.75.1 #1089). `--hide-claude-auth` 구독 거부
    (0.74.0 #1079)는 **우리가 그 플래그를 넘기지 않아서**(repo grep 0건) 두 겹으로 unreachable.
    ⑷ **#96 근거 재측정 — 0.75.1 에서도 동일.** 설치 아티팩트 직독: 4분할 구성 `:3853-3866`,
    다음 emit `:3867-3878` 은 여전히 스칼라 `used` + `size` 뿐 `_meta` 없음, 이 파일의 `_claude/*`
    `_meta` 키는 여전히 셋(`sdkMessage`/`origin`/`rateLimit`)이고 **`_claude/usage` 없음**.
    `sessionUsage()`(`:6444-6452`)·`turnQuotaMeta()`(`:6476-6485`) 는 0.73.0 과 텍스트 동일.
    ACP 표면 전수 대조도 동일(sessionUpdate 리터럴 11종, agent 메서드 7종, `stopReason` 집합).
    ⑸ **readiness 재측정(§11-7 갱신, 0.70→0.73 논거 재사용 없음).** `mcpServerStatus` 호출은
    `src/acp-agent.ts` 에서 v0.73.0 **2건** / v0.75.1 **2건**으로 불변이고, 두 site 를 새 좌표
    `v0.75.1:1736`·`:1829` 에서 다시 읽었다 — 하나는 `supportsMcpOAuth` 뒤 `needs-auth` 만 훑고,
    다른 하나는 이름 하나짜리 서버를 OAuth deadline 안에서 polling 한다. 선언된 전체 MCP 를
    `newSession` 전에 막는 fence 가 아니다. 결론 유지, 근거는 새로 측정.
    ⑹ **기계 이동:** `package.json` 한 dependency, `pnpm-workspace.yaml` exclude 에 0.74.0/0.75.0/
    0.75.1, `pnpm-lock.yaml`, `test/acp-sdk-surface.contract.test.ts` PINS + L2 lock regex,
    `docs/acp-backend-rail.md` 지원 matrix + §11-7 + 신설 §11-8, 그리고 0.73.0 dist 줄번호
    provenance 주석 **11곳**(`check-acp-usage-accounting.ts` 6 · `acp-client.ts` 2 ·
    `backend-adapter.ts` 2 · `backend.ts` 2 · `event-mapper.ts` 2 · `smoke-acp-raw-turn-live.ts` 1).
    `AGENTS.md:189` 도 정정했다 — `check-dep-versions` 는 **pi 전용**이고 ACP 핀을 한 줄도 읽지
    않는다(`run.sh:1820-1919` 전문 독파). ACP 핀의 오라클은 `check-acp-sdk-surface` 이고 그것은
    `scripts/` 게이트가 아니라 vitest 계약 `test/acp-sdk-surface.contract.test.ts` 다.
    게이트 신설 없음(pi 쪽 ⑶ 의 한 claim 은 pi 레인 몫).
- **Standing focus — Mitsein over MCP:** plain external(non-replyable) vs garden-native meta-session
  (replyable by garden id) 구분이 agent 발화에 정직히 반영되는가. native Claude meta-session이
  external-mcp로 퇴행하거나 `wants_reply=true`를 비대칭 거절하면 버그.
- **Session continuity hygiene:** `incompatible_config`가 너무 넓음 → 축별 diff 출력 + reason taxonomy
  (`auth-profile`/`auth-epoch`/`system-prompt`/`mcp`/`transcript-missing`/`emacs-socket`/`tool-surface`).
  `emacsAgentSocket` 누락이 대표 footgun.
- **#25 bridge hygiene(OpenClaw audit lessons):** transcript pre-flight(backend jsonl verifier), session
  cache hygiene(idle timeout/LRU/max-N), single-turn lock per session.

---

## Deprecated — closed, do not reopen

- **OpenClaw track(2026-06-10 종료):** `plugins/openclaw` deprecated & unmaintained. Claude/Gemini가 ACP
  네이티브 지원 → wrapper 존재 이유 소멸. npm `@junghan0611/openclaw-pi-shell-acp@0.0.1` deprecate 마킹,
  소스 reference 동결.
- **Gemini CLI(2026-06-18 deprecated):** Google AI Pro/Ultra·무료 tier 대상 종료 → Antigravity CLI 이관.
  repo는 Gemini 어댑터 코드를 **호환성용 잔존**, README는 더 이상 추천 setup 경로로 제시 안 함.
- **Long-term/separate coordinates:** #11 remote SSH resume cwd(원격 entwurf identity는 의도적 fail-fast),
  #10 broader ontology RFC, #8 ACP `entwurf_v2` message visibility UX, #2 pi-first context meter, L5 long soak. 이 좌표들은
  OPEN backlog가 아니다. 현재 실행 가능한 결손으로 재현될 때만 새 이슈가 된다.

---

## Reference paths

- 본체: `~/repos/gh/entwurf/` · Consumer: `~/repos/gh/agent-config/` · NixOS: `~/repos/gh/nixos-config/`
- 미래 split 대상(#38, rename과 별개): entwurf-core(v2 interface)를 ACP plugin에서 떼어낸 별 repo
