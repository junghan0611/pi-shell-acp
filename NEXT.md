# NEXT — OMP as one garden sibling (실무 잠수함)

> NEXT는 disposable boot sector다. 완료 이력은 issue/git이 지고, 방향은 ROADMAP,
> 운영 규율은 AGENTS가 진다. 새 하네스 입학 경로는
> [docs/adding-a-harness.md](./docs/adding-a-harness.md)다.

# RAIL — 현재 좌표

- [x] **1. OMP measurement·audit·LIVE + Bundle A admission hardening** — backend registration, TUI-only birth, visible status, native MCP hand, sender identity, four-root/package/doctor hardening 완료.
- [x] **2. Operator deploy + real outbound acceptance** — 2026-08-28 oracle: 재설치·shared reader 재배포·doctor 4종 green, `check:full` exit 0, outbound LIVE 4건(그중 1건은 GLG가 직접 연 세션). `tools.xdev` 방언 발견과 문서화 포함.
- [x] **3. Bundle B: addressed receive / roundtrip** — **대칭이 생겼다.** receiver 확장, bounded arm defer, `/new`·watch-error·vanished-signal·overlapping-edge fail-closed, install/uninstall/doctor, `check-omp-receive-arm` + `scripts/mutants/omp-receive.json`(11 mutants, 전부 정확한 이유로 kill), `smoke-omp-receive-state`, `smoke-omp-receive-live`. registry `self-fetch`/`D6`, DELIVERY 행 신설. 단언 개수는 게이트가 세는 것이지 증거가 아니므로 여기 박지 않는다 — 영수증은 `raw-omp-measure/README.md` §M7 이다.
- [x] **4. Bundle A+B land** — `a809ee7 feat(omp): receive addressed native messages` (26 paths). 체크포인트 commit; push·cut 없음.
- [x] **5. Bundle C: visible fresh + admission release-stop** — 구현이 한 candidate로 동결되고 independent review까지 끝났다(2026-08-30, architecture blocker 0 / **Defect 3** / observation 1). `entwurf_fresh_call`이 네 번째 backend로 omp를 연다. clause 7 LIVE(`smoke-omp-fresh-live`, release-gate MUST)는 **green** — 2026-08-30, 21 assertions, omp 18.0.0 / `openai-codex/gpt-5.6-sol`, callback sender garden `20260830T192913-df52b9`. 영수증 정본은 DELIVERY.md의 OMP 행이고, 그 근거로 DELIVERY/README의 라벨은 이미 이동해 있다. **한 호스트·한 모델·한 번의 수용이다** — multi-host도, multi-model도, 한 프로세스 안의 반복 fresh도 주장하지 않는다. review amendment 한 번들(Defect 1–3)은 2026-08-31에 `5bb1d50`으로 반영됐다 — same-id `session_switch` epoch 무효화, creator 소유 `ctx.setTimeout`/`ctx.clearTimer` readiness 타이머(취소 불가 빌드는 arm 거부), 산문 정렬, 뮤턴트 21→23. closure review 잔여 O-D1r은 defect 등급으로 승격되어 `153f9f4`에서 닫혔고(뮤턴트 23→24), 첫 standalone qualification이 `fd5e462`에서 manifest 부채를 측정으로 정산했다 — `check-gate-qualification` 324/324 KILLED, `check:full` exit 0 (430s).
- [x] **6. 0.16.0 cut** — 태그·릴리즈 완료.
- [x] **8. #72 진단·수리** — 원인은 entwurf가 아니었다. oracle에 다른 하네스(openclaw acpx, PR #245)용으로 손설치된 `acp-zombie-reaper.service`가 벤더 프로세스 이름 `claude-agent-acp`를 **argv 부분문자열**로 골라 900초 넘은 것을 SIGTERM한다. entwurf는 child를 턴 사이에 **retain**하므로 그 나이는 세션의 나이다 — 15분 넘은 세션은 5분마다 저격당했다. 벤더 핸들러가 그 시그널을 `dispose(); exit(0)`으로 지워서 exit 0/무시그널로 도착했고, 그래서 세 번의 진단이 후보 4개를 폐기하고도 놓쳤다. 두 boot에 걸쳐 **12/12** 대응(pid+시각 이중 잠금, 이슈를 연 2026-07-30 샘플과 2026-08-16 원조 필드 리포트 포함). 수리는 `ca52fdd` — 울타리 안에서 (a) vendor를 **같은 프로세스로 import**하는 entwurf 소유 launcher(재시작할 child가 없으므로 supervisor가 될 수 없다), (b) exact full-line 프레임으로 실린 typed signal observation. 게이트 `check-acp-launch-namespace` 신설 + CELL 12–15, mutant 8개 전수 KILLED, live receipt는 `scripts/raw-acp-child-exit-measure/README.md`.
- [x] **7. 0.16.0이 남긴 원커맨드 구멍 메우기** — 닫혔다(`4076498`, `c3d5b2a`), pi floor 0.84.4까지 함께(`5c1bda5`). 원래 본문: **v0.16.0은 OMP를 admit했지만 `setup`은 OMP를 합성하지 않았다.** GLG의 thinkpad(설치 안 된 호스트)에서 `entwurf setup`이 green을 찍는데 OMP는 확장도 mcp.json도 status line garden id도 없었다 — 유닛 게이트는 유닛만 묻고, admission 게이트는 registry↔fresh만 물어서, "유닛이 있다 → 원커맨드가 거기 닿는다" 간선을 아무 게이트도 소유하지 않았다. 이번 세션에서 (a) `setup_all`에 omp 4유닛(birth→MCP→`tools.xdev` 설정→receiver) presence-driven 합성, (b) 설정값 writer `install-omp-config`/`uninstall-omp-config` 신설(정확히 자기가 넣은 줄만 소유, 운영자의 명시적 `xdev: true`는 덮지 않고 이름 불러 거부), (c) `smoke-setup-verdict` S-8(스텁 벤더로 실제 합성 구동 + install-state 4종 + agent dir 산출물 + `xdev-off` 유효 판독 + 2회차 멱등) 및 S-1의 `OMP_BIN` absent 핀, (d) `docs/adding-a-harness.md` **step 10**(온보딩은 setup이 합성해야 끝난다)까지 닫았다. 남은 것: 버전 범프·CHANGELOG 승격은 `entwurf-release` prepare 몫(GLG 승인).

<details><summary>6의 원래 본문 (릴리즈 준비 기록)</summary>

CHANGELOG `## Unreleased`가 구현 범위 `v0.15.1..19ad90c` **30커밋** 전수로 채워져 있었다. CHANGELOG `## Unreleased`가 구현 범위 `v0.15.1..19ad90c` **30커밋** 전수로 채워져 있다(릴리즈 준비 커밋은 그 위에 따로 쌓이므로 `v0.15.1..HEAD`의 수는 계속 커진다 — 기준은 항상 범위이지 숫자가 아니다). 섹션 승격·버전 범프·lockfile·release-gate 수치는 `entwurf-release` **prepare** 몫이고, land/prepare/make/publish는 모드마다 별도 GLG 승인이다.

</details>

- [x] **9. ACP Claude를 메인 레일로 — 계기판 수리(#93)** — main에 랜딩됨 (`4d6fe4c` 및 선행 3커밋).
  본문 설계(`extractTurnUsage?` seam → 네 필드에 4분할 투영)는 2026-09-02 측정으로 **기각**됐고,
  실제로 랜딩한 것은 그 기각의 실행이다. #93·#92·#96 모두 닫혔다 — #92는 2026-09-03 두 번째
  호스트 재현으로, #96은 캐리어 없이 선 대체 계측으로. 이월된 관측은 CARRIED에 있다.
  독립 리뷰 D1(재청구 하한의 스코프 혼합)은 `9479750`에서 닫혔다.

- [x] **10. 0.17.0 cut** — 태그·GitHub 릴리즈 완료(`v0.17.0` @ `934acb9`). npm에는 올라가지 않았다.
      세 번의 재컷이 `cut: BLOCKED`로 끝났고 GLG가 네 번째를 금했다 — 그 구멍은 CHANGELOG 0.17.0
      Verification에 이름으로 적혀 있고, 반올림하지 않았다.

- [x] **11. 0.17.2 cut + npm** — `v0.17.2` @ `c82576c`, GitHub 릴리즈 + **npm `latest` = 0.17.2**
      (GLG가 직접 publish, 2026-09-03). 0.17선이 처음으로 레지스트리에 올랐다. #94·#98을 실었다.
- [x] **12. #101 랜딩 · 0.18.0 컷 + npm** — 한 pid 안의 세션 전환이 만든 유령 시민과 거짓 배달을
      닫은 커밋 7개(`3ca8220 → 5763bfa`)가 main에 올라가고 **`v0.18.0` @ `2934807`**로 컷됐다.
      GitHub 릴리즈 공개 + **npm `latest` = 0.18.0**. exact-SHA CI run `33866330016` 3잡 초록,
      LIVE 게이트 `cut: OK`(MUST 23/0/0, qualification 364/364). 발행된 integrity가 수용 candidate의
      것과 동일해 리팩이 없었음이 레지스트리에서 확인된다. npm 토큰이 만료돼 있어 발행은 GLG가
      직접 했다(0.17.2와 같은 방식).
- [x] **13. #102 1단계 main 랜딩** — `ci/99-stage1`이 fast-forward로 main에 담겼다:
      `8649967` (ci(qualification): move the head into the floor and stop tag pushes rebuilding).
      머리 게이트 `check-gate-manifests`가 `check:hermetic`으로 들어가고, semver 태그 push가
      이미 빌드된 SHA를 재빌드하지 않는다. #99·#102 닫힘. **2단계는 #103** — P2(이벤트 좁히기) /
      P5(잡 분리) / P6b(느린 그룹 재배치). 브랜치 NEXT(`NEXT--ci-99-stage1.md`)는 이 커밋에서 삭제됐다
      (머지 전에 지웠어야 했다).
- [ ] **14. 버전 범프 레인 — pi 0.85.1 + claude-agent-acp 0.75.1 (+ #91 OMP 채택 규칙)**
      ← CURRENT: **#104**. 정찰 → GLG grant → 구현이 main 위에 있다. 남은 것은 코디네이터 리뷰
      한 번 → amendment 한 번들 → 동결 candidate 위 `check-gate-qualification` 1회 +
      `check:full` 1회 + `check-pack-install` + `check-install-container`. 릴리즈는 #102 와
      합본 **0.18.1** 이고 버전 범프·절 승격은 `entwurf-release` prepare 몫이다. 푸시 금지.

현재 좌표: 1–13 완료 → 14 구현 완료·검증 대기 · **0.16.1 make는 열린 채 PAUSED**. 푸시·태그는
`entwurf-release` 4모드 몫이다 (CalVer `tag-release`가 아님).

# NOW — #104 구현이 main 위에 있다, 검증 남음

- **Stem:** 세 상류 이동을 한 레인으로. 원인은 셋이고 acceptance 도 셋이지만, 셋 다
  `run.sh` 핀 · `check-acp-sdk-surface` · lockfile 이라는 같은 표면을 건드려 스케줄링 계약상
  qualification 1회 + `check:full` 1회를 각자 부른다. GLG 결정으로 한 번만 지불한다.
- **Current:** 조각 A(pi)·B(acp)·C(#91 문서)·D(ledger·CHANGELOG) 구현 완료, main 워크트리에
  있다. `check-dep-versions` · `check-acp-sdk-surface`(7/7) · `check-pack-pin-matcher` ·
  `check-gate-manifests`(369/40) · `pnpm check`(exit 0, 48s) · `check-install-surface` green.
- **Next:** ① 코디네이터(`20260904T213456-dfdfc4`)에게 리뷰 요청 1회 → ② amendment 한 번들 →
  ③ 동결 candidate 위에서 tmux 로 `check-gate-qualification` 1회 + `check:full` 1회 +
  `check-pack-install` + `check-install-container`(Docker) → ④ 커밋. **푸시는 GLG.**
- **이 레인이 실제로 잡은 것 두 가지 (정찰이 예고하지 못한 것):**
  1. **pi 0.85.x 의 미선언 breaking 하나.** `pi-tui` `Container` 가 `private mouseLayout?` 를
     얻어(0.84.4 의 `Container` 는 private 멤버가 없었다) `Box → Container` 구조적 할당이
     TS2322 로 깨졌다. upstream Breaking 절은 `createGatewayBindingFetch` 만 이름한다.
     수리는 벤더가 실제로 요구하는 `Component` 로 좁힌 것 — `Container` 는 애초에 필요 없었다.
  2. **`0.85.0` 은 깨진 publish 다.** `./client`·`./experimental/plugin` 을 tarball 에 없는
     `dist/*` 로 광고했고 0.85.1 이 source-only 로 되돌렸다. 랜딩 좌표는 0.85.1 뿐이다.
- **A항(chord) 은 실물 트리로 닫혔다.** 실제 0.85.1 `.pnpm` 목록에 `@earendil-works+chord@0.85.1`
  이 있고 옛 `pi-` 접두사 matcher 는 그것을 못 봤다. matcher 를 org 접두사로 넓히고 chord 를
  8번째 핀으로 넣었으며, 새 claim `[QK:PACK-INSTALL-PIN-MATCHER-COVERS-CLOSURE]` + mutant 1종으로
  kill-proof 를 세웠다(뮤턴트 368→**369**, lane 40 불변, 두 mutant 모두 자기 signature 로 죽는 것을
  손으로 확인).
- **B-4 는 LIVE 로 봤다.** `/compact` 한 턴 → `tool_call(kind:"think", "Compact conversation")` →
  `tool_call_update`, 그 알림을 프로덕션 매퍼에 재생하면 `[tool:start]`/`[tool:failed]` 공지 쌍.
  타입 파손 아니고 회계 경로 무관. **한계: 성공 분기(`completed` + preTokens/postTokens)는
  미관측** — 세션이 짧아 벤더가 "Not enough messages to compact." 로 끝냈다. 영수증은
  `scripts/raw-acp-compaction-measure/README.md`, 계약은 `docs/acp-backend-rail.md` §11-8.
- **#91 은 문서 절이 랜딩하면 닫는다.** 규칙은 `docs/setup-clean-host.md` §4b — floor 없음이
  계약이고, weak floor 는 LIVE 영수증이 있는 마지막 버전(`18.1.10`), 센티널은
  `smoke-omp-fresh-live` + `smoke-omp-receive-live`. 랜딩 SHA 로 닫는 댓글은 이 세션이 쓴다.
- **미측정 (넘기는 것):** 압축 `completed` 분기 · `usage-markdown.ts`(#1085) 소비 경로 ·
  pi 0.85.1 + acp 0.75.1 을 함께 넣은 트리의 `@anthropic-ai/sdk` 두 사본 재확인 ·
  `packages/chord` 내용물이 우리 표면에 닿는지 · 이 레인의 LIVE 릴리즈 축 전체.
- **Read:** #104 본문과 코디네이터 grant 댓글(스레드가 본문을 이긴다) · ROADMAP
  **Dep bump(별도 트랙)** 의 이번 두 항목 · `docs/acp-backend-rail.md` §11-8.
- **Do not touch:** 푸시 · 빨간 floor 를 고치는 것(멈추고 보고) · 워크트리 안에 로그(scratch 전용) ·
  긴 명령을 하네스 백그라운드 도구로(tmux) · `.claude/skills/entwurf-release/SKILL.md` 에 비-ASCII ·
  `check-install-surface` 는 git index 를 읽는다(`git add` 후 재실행).

<details><summary>0.18.0 착지 직후의 NOW (레인 닫힘 — 이월 관측은 여기 남는다)</summary>

## Archived NOW — 0.18.0 착지 후 (다음 stem 대기였던 자리)

- **Stem: 없다. GLG가 고른다.** 0.18.0이 태그·GitHub 릴리즈·npm `latest`까지 전부 닫혔다
  (`v0.18.0` @ `2934807`, 2026-09-04). 이 리포에 지금 열려 있는 릴리즈 레인은 없다.
- **이 레인이 실은 것:** `fix/101-session-switch` 커밋 7개(`3ca8220 → 5763bfa`). 한 pid 안에서 세션을 갈아타면 처음 열렸던 빈 세션이 계속 "살아있는
  형제"로 등록돼 있어 편지가 허공으로 갔다 — 그 유령을 은퇴시키고, 배달 가능 판정을 "지금도 그
  주소를 듣고 있는가"로 좁히고, 거절이 이유를 말하게 하고, 형제 목록에 `receiver=`/`transcript=`
  두 컬럼을 붙였다. 사람 말 정본은 **#101 종결 댓글**이다.
- **버전이 minor였던 이유:** `entwurf_peers` 줄의 컬럼 두 개와 거절 이유 문장은 **additive surface
  변경**이다. 제거도 의미 변경도 없으므로 patch가 아니라 minor.
- **Upgrade note (CHANGELOG에 실렸다, SSOT는 거기다):** 이 릴리즈는 `pi-extensions/lib/meta-session.ts`와 Claude 훅을
  바꾼다 → **네 install 경로**(`install-meta-bridge` / `install-omp-bridge` / `install-omp-receive` /
  `install-copilot-bridge`)의 배포 writer가 동시에 낡는다. **업그레이드 명령은 `entwurf setup` 하나**다.
  0.17.2에서 Claude 레일만 재설치했다가 첫 `--cut`이 `smoke-omp-receive-live`로 BLOCKED된 그 교훈
  그대로이며, CHANGELOG 0.17.2 Upgrade note가 그 SSOT다.
- **이 레인은 닫혔다.** 다음 stem은 GLG가 고른다. 남아 있던 후보는 여전히 유효하다 — codex 핀
  범프(`smoke-meta-async-drift` drift=1), 0.16.1 make(prepare 끝, make만 대기), #98 P4 관측창
  승격 결정, #94 잔여 관측 둘, 별건 마이그레이션 둘(`lastDeliveredAt` 제거,
  `stampMailboxReceipt` 2-writer lost-update).
- **이월 관측 (#101이 남긴 것 — 수정이 아니라 다음 레인 재료):**
  1. **omp-host 후보 조건 하나 더.** sender↔receiver 교차검증은 지금 `ownerKind = claude-code-cli`로
     스코프된다. OMP `unarm`의 marker 삭제 실패는 catch 후 진행하고
     (`meta-bridge-receive-omp.ts:610-636`) omp에는 reader-side join이 없어 방어막이 writer 하나뿐이다.
     lane을 넓히려면 이 비대칭부터 측정한다. Copilot은 구조적으로 제외다 — receiver marker owner가
     포크된 확장 자식의 pid이고 sender marker는 CLI의 ppid라 영구 `mailbox-undeliverable`이 된다.
  2. **observe seam footgun.** custom `metaEntries`를 주면서 observer를 주입하지 않으면 기본
     관측자가 다른 루트를 stat한다. 새 caller/gate는 `observe` 주입이 규율이고, 이유는 provider
     헤더에 있다.
  3. **원인 미상 1건 — 열린 채로 둔다.** `smoke-entwurf-chain-live` 1회가 hop3에서
     `rejected: mailbox-undeliverable (observed liveness: unsupported)`로 실패했다
     (2026-09-04 16:58 KST). 앞뒤 두 번은 통과, 재현 안 됨. start-key 레이스와 idle owner 조기
     종료는 측정으로 배제됐고, OOM 가설은 저널에 근거가 없다(Fable 측정: journalctl 16:50–17:02에
     OOM/kill 줄 없음, systemd-oomd kill 기록 없음, earlyoom 비활성). 다음 발생 때 갈라줄 자리는
     체인 시작 전 fixture 단언과 `terminus fixture at timeout: ownerPid=… alive=… ownerAlive=…
     watchArmed=…` 줄이며, 그 계측은 `f4dbe32`·`69bee12`로 이미 들어가 있다.
     **리드 하나 (영수증 아님, 2026-09-04 릴리즈 레인에서 나옴):** Claude Code 하네스의
     **저메모리 워치독**이 커널 OOM과 무관하게 백그라운드 도구 호출을 죽인다 — 릴리즈 담당
     세션에서 `Background command … was stopped because the system is running low on memory`,
     직후 `free -h` **available 13Gi**, 저널에 OOM/kill 0건. Fable 세션(dbf654)도 같은 날 같은
     문구로 두 건, 직후 available **12996 MB**. 저널에 흔적이 없는 경로가 커널이 아니라
     워치독이라면 위의 OOM 반증 측정은 전부 참이면서도 다른 킬러를 본 것이 된다.
     **미측정:** 그 chain-live가 백그라운드 도구 호출 안에서 돌았는지, 워치독이 실제로 idle
     owner를 골랐는지. 확인하려면 그 세션의 killed-task 알림 유무를 본다.
- **#99로 넘길 재료:** claude 훅에 처음 생긴 뮤턴트 lane(17 claim)과, "전수 뮤턴트를 언제 돌릴
  것인가"의 실측 — 오늘 전체 바닥 **완주 5회 / 3회**, 한 번에 약 35분. 대부분이 산문 수정 뒤
  재검증이었다. 수치 정본은 #101 종결 댓글 §비용.
- **이번 컷이 남긴 운영 교훈 (반복 방지, 전부 이번에 실제로 당한 것):**
  1. **릴리즈 게이트가 도는 동안 커밋을 만들지 않는다.** 첫 `--cut`이 50분을 쓰고
     `origin HEAD changed during qualification`으로 무효화됐다 — 게이트 중간에 온 커밋 요청을
     즉시 처리한 결과다. 워킹트리 편집은 무해하고, HEAD 이동만 치명적이다. 규율은
     `entwurf-release` 스킬 P5에 박아뒀다.
  2. **`.claude/skills/entwurf-release/SKILL.md`는 ASCII 전용이다.** `check-install-surface`의
     S7e가 `skillIsAscii`로 전 코드포인트 ≤127을 요구한다(`scripts/check-install-surface.ts:494`).
     그 스킬에 한글이나 em dash(—)를 한 글자라도 넣으면 `check:full`이 exit 1이다. 이번에
     실제로 그랬다 — Fable의 지시 문장을 그대로 옮겨 적다가 em dash 두 개가 들어갔고, prep 커밋을
     amend해서 고쳤다(`dea16d5` → `2934807`). **규율 한 줄을 추가하는 일조차 게이트를 깬다.**
  3. **그 게이트는 워킹트리가 아니라 git index를 읽는다.** `readCandidate`가
     `git show :<file>`이다(`check-install-surface.ts:436-445`). 파일만 고치고 재실행하면
     영원히 빨간 것처럼 보인다 — `git add` 후에 다시 돌려야 한다.
  4. **`entwurf setup`을 LIVE 게이트 **전에** 돌린다.** 게이트 직전 doctor 4종을 쳤더니 셋이
     STALE이었다(`installed=dd9df442d945 vs source=796aa7630133`). 0.17.2가 첫 `--cut`을
     `smoke-omp-receive-live`로 날린 그 축이고, 이번엔 50분을 쓰기 전에 잡았다.
  5. **긴 명령은 tmux로.** 이 하네스의 저메모리 워치독이 백그라운드 도구 호출을 죽인다 — LIVE
     게이트 1회를 그렇게 잃었다. tmux 세션은 그 밖이라 끝까지 간다.
- **Read:** #101 종결 댓글(사람 말 정본) · `scripts/raw-claude-session-switch/README.md`
  (S1–S6 훅 로그 verbatim, UPS native id 8/8) · `entwurf-release` 스킬.
- **Do not touch:** 0.17.0/0.17.1/0.17.2 태그와 그 CHANGELOG 절 ·
  `mux-launch.ts`/`mux-placement.ts` import fence ·
  이 호스트의 `~/.pi/agent/meta-mailbox/20260904T093135-ac7a1a/` 편지·표식·기록(#101 재현 증거) ·
  `source` 값에 분기하는 로직(로그로만 남긴다 — 호스트 독립성이 이유다).

</details>

<details><summary>0.17.1의 원래 NOW (C1b 원인 닫힘 — 태그·GH 릴리즈 완료, npm 미발행)</summary>

## Archived NOW — 0.17.1: C1b 원인을 닫고 npm까지

- **Stem:** 0.17.0은 태그까지 갔지만 세 번의 재컷이 `cut: BLOCKED`였고 npm에 오르지 않았다.
  0.17.1은 그 BLOCKED의 원인을 **측정으로 닫고** 처음으로 0.17선을 레지스트리에 올린다.
- **지금 서 있는 자리:** `main` = `665191d`, origin과 동일, exact-SHA CI 3잡 초록
  (run 33697821117 — `check` 34m20s, `install-surface`, `artifact-consumer`).
  릴리즈 범위는 두 커밋이다: `a3563bc`(진단) → `665191d`(원인 수리).
- **닫힌 원인 (C1b).** 스모크가 pi의 락 stale 창과 **정확히 같은 값**을 기다리다 148ms 차이로
  졌다. pi는 `auth.json`/`models-store.json`을 `proper-lockfile`로 잠그고 모든 boot이 그 락을
  거쳐 읽는다(`dist/core/auth-storage.js`, `staleMs = 30_000`). `terminateChild`의 SIGTERM은
  release가 돌기 전에 프로세스를 끝내므로 그 창에 들어간 kill이 락을 고아로 남긴다(kill 오프셋
  24개를 훑어 +375ms에서 재현). 고아 락 상태의 boot→record는 **30,148ms**, 인수 직후 같은 조건은
  **1,114ms**. `BOOT_TIMEOUT_MS = 30_000`은 레코드가 태어나기 148ms 전에 보기를 그만둔다.
  두 실패 컷 모두 호스트 audit 로그가 "자식은 30초 내내 살아 있었다"를 확증한다.
  통제군은 같은 세 런 안에 있었다 — `smoke-entwurf-chain-live`는 같은 2-레지던트 구조에
  `45_000`이고 3/3 PASS였다.
- **수리.** `PI_BOOT_TIMEOUT_MS = 45_000`이 측정 영수증과 함께
  `scripts/lib/pi-record-discovery.ts`에 있고, 30초 절벽에 앉아 있던 다섯 스모크가 전부 거기서
  파생한다. `describePiLockResidue()`는 실패 시점의 pi 락을 이름으로 찍되 **읽기만** 한다 —
  고아와 산 홀더는 바깥에서 구별되지 않고, 중재는 pi 자신의 stale 프로토콜 몫이다.
  제품 레일(birth/mux-launch)은 건드리지 않았다. 스모크 bound가 수리였다.
- **정정 하나 (기록으로 남긴다).** 조사 중간 보고는 "30→45는 실측으로 반증됐다"고 썼다. idle
  boot 1.1s만 보고 여유 25배로 읽은 것인데, 실패는 느린 boot이 아니라 30초짜리 락 대기였고
  bound가 하필 그 창과 같은 값이었다. 반증된 것은 "부하로 느려진다"이지 bound 자체가 아니었다.
- **아직 열린 것:** mux pi-native nonce 300s는 **이 버그가 아니다**(창의 10배이고, 같은 런에서
  코덱스 레일은 chain-live·omp-fresh로 건강했다). 이번에 들어간 pane forensics —
  pane pid 생존 · `list-panes` · `capture-pane` 마지막 40줄 — 이 다음 발생 때 답한다.
- **초록 컷 (0.17.0이 세 번 못 받은 것).** `LIVE=1 ./run.sh release-gate
  /tmp/entwurf-release-gate-0.17.1.hb5Q5j --cut` — **MUST PASS=23 FAIL=0 SKIP=0**, BEHAVIOR PASS=1,
  exit 0, `cut: OK`. 2026-09-03 09:46:37 → 10:35:42 KST, `665191d` 위. qualification 347/347 KILLED,
  `check:full` 451s. **막았던 두 셀이 같은 런에서 함께 통과했다** — matrix-live C1b, mux-lifecycle
  pi-native nonce.
- **Next:** `entwurf-release make 0.17.1` → `publish 0.17.1 <candidate.tgz> latest`.
  npm에 0.17.0은 없으므로 이 publish가 0.17선의 첫 `latest`다.
- **Read:** CHANGELOG `## 0.17.1` Verification(재현 조건과 수치) · `scripts/lib/pi-record-discovery.ts`
  의 `PI_BOOT_TIMEOUT_MS` 주석 · CHANGELOG 0.17.0의 세 BLOCKED 컷 기록(그 자리에 그대로 둔다).
- **Do not touch:** 0.17.0 태그(`v0.17.0` @ `934acb9`) · CHANGELOG 0.17.0 절 · 제품 레일을 이
  레인에 섞는 것 · `mux-launch.ts`/`mux-placement.ts` import fence · 0.16.1 make를 이 레인에
  섞는 것 · #92를 구현 이슈로 취급하는 것.

</details>

<details><summary>OMP 레인의 직전 NOW (0.16.1 make 대기 — 열린 채 보류)</summary>


- **Stem:** OMP TUI 하나를 독립 형제로 세우되, 그 안의 서브에이전트에는 garden id를 주지 않는다.
- **이제 되는 것 (측정, 2026-08-30 oracle, omp 18.0.0):** OMP TUI가 열리면 citizen 하나를 mint하고, 상태줄에 garden id를 보이고, 자기 이름으로 보내고, **다른 harness의 메시지를 받는다.** idle 세션이 타이핑 0회로 깨어나 `entwurf_inbox_read`로 스스로 드레인하고 같은 native 세션에서 답한다. `/new`는 옛 시민의 doorbell을 회수하고 새 시민에게 arm한다. task subagent는 여전히 아무것도 mint·arm하지 않는다.
- **C에서 새로 되는 것:** `entwurf_fresh_call(backend=omp)`이 세 public surface 전부에서 열린다 — bare `omp` runtime, **positional prompt 없는 two-stage bootstrap**(고정 등록 플래그 `--entwurf-bootstrap`이 `{v,target,nonce,task}`를 나르고, 설치된 birth 확장이 callback tool이 실제로 부를 수 있게 된 뒤 callback-only 프롬프트를 보낸 다음 성공한 `tool_result`를 보고서야 다음 `turn_end`에 task를 넘긴다) + 명시적 `--approval-mode yolo`, callback tool `mcp__entwurf_bridge_entwurf_v`, 그리고 **5축** pre-mutation preflight(다섯째는 omp 고유의 `tools.xdev !== true`). launch seam에서 `PI_SESSION_ID`/`PI_AGENT_ID`를 scrub한다(모든 backend). positional은 선택이 아니라 측정 결과다 — `[LIVE 2026-08-30]` positional 후보는 도구가 존재하기 ~830ms 전에 턴을 시작해 `ACK`만 답했다.
- **아직 안 되는 것:** clause 7 LIVE는 green이지만 **한 번, 한 호스트, 한 모델**이다. multi-host·multi-model·반복 fresh는 증거가 없고, 그 한계는 CHANGELOG Notes에 그대로 적혀 있다. closure review·qualification·full floor는 닫혔다(`153f9f4`, `fd5e462`). 남은 미지는 릴리즈 축뿐이다 — 버전 트리 위의 `LIVE=1 ./run.sh release-gate <scratch> --cut` 집계와 릴리즈 커밋 정확 SHA의 CI 3잡(`check`·`install-surface`·`artifact-consumer`).
- **새 일반 규칙 (C가 만든 것):** 새 하네스는 branch에서 partial evidence가 가능하지만, release package는 step 9까지 닫혀야 한다. unsupported 표기는 partial-release 허가가 아니다. deterministic 반쪽은 `check-harness-admission-parity`(check:full), LIVE 반쪽은 첫 release의 clause 7 MUST step. Copilot의 기존 operator-metered exclusion은 소급 재설계하지 않는다.
- **운영자 필수 설정 — 이제 손으로 넣지 않는다:** `~/.omp/agent/config.yml`의 `tools: xdev: false`는 `entwurf setup`이 `omp-config` 유닛으로 쓴다. 기본값에서는 doorbell이 모델이 부를 수 없는 도구를 알리게 되고, LIVE 스모크가 이걸 선행 조건으로 검사한다. 운영자가 **명시적으로** `xdev: true`를 적어 뒀다면 그건 결정이지 drift가 아니므로 writer가 덮지 않고 이름을 불러 거부하고, setup은 그것을 component FAIL로 세운다.
- **`config.yml` 리더 결함 하나 (측정, 2026-08-31 thinkpad):** 벤더 자신의 settings writer가 쓰는 `modelRoles:` + 들여쓴 `{}` 형태를 `scripts/omp-tool-surface.py`가 파일 전체 `unreadable`로 읽어 `doctor-omp-mcp`가 `tools.xdev`와 무관한 이유로 RED였다. flow collection을 값 자리와 자식 블록 자리 양쪽에서 파싱하도록 고쳤다. TS 리더(`readOmpConfigFlag`)는 원래 정상이었으므로 fresh preflight는 영향이 없었다 — 두 리더의 **합치**만 보는 셀은 이 결함을 영원히 통과시킨다(둘 다 unreadable/true를 "not false"로 접기 때문). 그래서 `[QK:OMP-XDEV-VENDOR-SHAPE-READABLE]` 직접 단언을 넣었다.
- **Copilot 1.0.81 행 문법 (측정, 같은 호스트):** `copilot plugin list`가 `(v0.1.0) (enabled)` + 들여쓴 `from <path>`를 찍게 바뀌어 버전이 `0.1.0) (enabled`로 읽혔고, 멀쩡히 설치·enabled인 호스트에서 `setup`이 `copilot-birth: FAIL`을 냈다. 상태 토큰 하나만 정확히 허용하도록 문법을 넓혔다.
- **컷 게이트는 이제 실제 왕복을 요구한다:** `smoke-omp-receive-live`가 registry를 읽고 `self-fetch`를 보면 더 이상 SKIP하지 않는다 — `LIVE=1`에서 실제 tmux omp TUI를 띄우고 11개 단언을 요구한다. 하드코딩된 통과가 아니다.
- **Next:** (1) **0.16.1 make** — prepare는 끝났다(CHANGELOG 승격·`0.16.1`·lockfile 무변경). `LIVE=1 ./run.sh release-gate <scratch> --cut`의 실측 MUST/BEHAVIOR 수치를 릴리즈 절에 적고, 그 다음이 `entwurf-release make 0.16.1`(push·tag·GitHub release — 모드별 GLG 승인). (2) **cross-harness leg의 deterministic 반쪽 배선** — post-contract 시민 backend마다 cross-harness LIVE step이 wired거나 선언된 metered 예외인지 `check-harness-admission-parity` 옆에 검사(규칙은 `docs/adding-a-harness.md` release stop에 박혀 있고, 게이트가 없는 동안은 prose다 — 별도 grant). (3) **#72 후속 둘** — between-turns 공지(`backend.ts`의 `previous … ended between turns`)에 `launchObservation`을 싣기(턴 사이에 외부 TERM이 오면 지금은 exit 0만 보인다, 한 줄 수리), 그리고 **reaper 수리는 openclaw 레인** — 청소기가 자기 것만 죽이도록 positive own-marker(`/proc/<pid>/environ` 또는 자기 pid registry)로 좁히는 게 primary이고, 우리 launcher는 defense-in-depth다. 이름 분리의 대가도 기록됐다: 이제 호스트 청소기는 entwurf의 **진짜** leak도 못 본다 — 그 cleanup은 entwurf가 소유한다.
- **Read:** #87 thread · `scripts/raw-omp-measure/README.md` §M7 (수용의 근거가 된 5셀 측정) · `docs/setup-clean-host.md` §4b · `docs/adding-a-harness.md` step 7.
- **Do not touch:** `mux-launch.ts`/`mux-placement.ts`(import fence) · omp용 managed launcher shell(근거 없음) · registry `supported` 필드(새 authority 금지) · #76/#78 · #87/#89 close. (Pi 0.84.4는 2026-09-01에 해제되어 랜딩됐다 — `5c1bda5`.)


</details>

# RECENT

- **2026-09-01 (ACP 메인 레일 판정, oracle):** GLG의 질문 "ACP로 클로드를 쓰면 손해 보나"가 세 번 재정의되며 깊어졌고, 마지막 형태는 **"400–500k 깊이에서 턴이 견고하게 유지되는가"**였다. 세 감사자(glm-5.3 · gpt-5.6-sol · kimi-k3)가 붙어 **근거 여섯 개를 회수**했다 — 그중 넷이 내 것이다. 남은 판정: 정상 reuse 구간에서 ACP와 네이티브는 **구분되지 않고**(같은 리포 통제 비교), 깊이 내구성은 **양 레일 모두 확보**돼 있으며(API 에러 턴 NATIVE 0.05% vs ACP 0.00%), 주 변수는 레일이 아니라 **사용 연속성**이다. 라이브 코디네이터가 관측 최대치 `415,541`을 돌파해(→ 475k+, resets 0) "그 값은 #72의 외부 janitor가 끊은 지점"이라는 의심을 반증했다. 같은 시각 네이티브 코더는 574k에서 리셋 0으로 돌았다 — "append-only는 ACP의 구조적 이점"이라는 프레이밍은 그 앞에서 계속 약하다. 가장 값진 것은 결론이 아니라 **공유 맹점**이었다: "compact 마커 양 레일 전수 0개"는 네이티브 **1,796파일 중 3파일**만 보고 쓴 것이었고, 두 세션이 그걸 함께 통과시켰다. 제3 감사자를 부른 이유가 정확히 그것이다. 이슈 큐 규율도 이 세션에서 두 상한(총 10 / 구현 5)으로 갈렸다.

- **2026-09-01 (#72 닫힘, oracle):** 여덟 달 서 있던 "ACP Claude child가 tool-loop 중간에 죽는다"가 **entwurf 결함이 아니었음**이 측정으로 닫혔다. 아무도 열지 않았던 아티팩트 하나 — 호스트 자신의 systemd user journal — 가 답이었고, 연결 고리는 처음부터 서명 안에 있었다: `(node:<pid>)`는 node `emitWarning`이 찍는 그 프로세스 자신의 pid다. 세 번의 진단이 주범으로 지목했다가 반례로 폐기한 그 경고 줄이, 내내 범인의 pid를 달고 있었다. 형제 둘이 붙어 각각 내 결론을 한 번씩 깼다 — GPT-5.6-terra는 "막을 수 없고 감별만 가능하다"를 launch shim으로 반증했고(시그널을 막는 게 아니라 **이름 매칭에서 빠지는** 층), Claude Fable 5는 프레임 필터가 개행 없는 마지막 말을 삼키는 회귀를 확정하고 live receipt를 만들었다. 이슈 코멘트 3건(진단·pid addendum·독립 검토)과 영수증 디렉터리가 남았다.

- **2026-08-31 (릴리즈 준비):** closure review 잔여가 닫히고(`153f9f4`) 첫 standalone qualification이 Bundle C 바이트 위에서 manifest 부채 네 갈래를 측정으로 정산했다(`fd5e462` — 324/324 KILLED, `check:full` exit 0 430s). cross-harness leg는 규칙과 첫 영수증을 함께 얻었고(`07349bd`, claude-code ↔ omp 양방향 live turn), 다섯 backend 비교표가 admission 문서 머리에 섰다(`7828bbc`). 업스트림 0.84.4 공개로 `check-pack-install`의 lockfile 없는 임시 설치가 pi-telemetry를 띄워 CI가 붉어졌고 transitive 핀으로 닫았다(`19ad90c`). CHANGELOG `## Unreleased`는 구현 범위 `v0.15.1..19ad90c` 30커밋 전수로 채워졌고, 릴리즈-정합 산문 정리가 뒤따랐다.
- **2026-08-30 (Bundle C candidate):** visible fresh가 붙었고, 그와 함께 **GLG가 찾은 release 구멍이 exit code가 되었다.** 원인은 닫힌 parity loop 두 개 사이에 간선이 없었던 것 — registry↔citizens와 surfaces↔fresh set을 각각 지키는 게이트는 있었지만 두 상수를 함께 import하는 파일이 0개였고, 그래서 omp는 D6 시민이면서 fresh 불가인 채로 모든 게이트를 green으로 통과했다. `check-harness-admission-parity`가 그 간선이다(추가 직후 `Unaccounted: omp`로 실제 RED, C 완성 뒤 green). agreement 게이트(`check-omp-fresh-preflight`)는 첫 실행에서 내 config reader의 fail-OPEN 오독(`tools.nested.xdev`를 `tools.xdev`로 읽음)을 잡았다. tmux env 누수도 실측 — server env의 `PI_SESSION_ID`가 새 pane에 그대로 상속되어(`SID=[leaked-uuid]`) 형제의 bridge child가 남의 신원으로 집에 전화할 수 있었고, launch seam에서 scrub한다. B의 packaging 누락 1건도 함께 고쳤다(`pi/omp-receive/entwurf-receive-omp/package.json`이 `files[]`에 없어 installed package에서 `install-omp-receive`가 죽었다).
- **2026-08-30:** Bundle B candidate. GLM 독립 검수 결과 architecture blocker 0 / Defect 3, 그 amendment까지 반영했다 — 가장 무거운 것은 `onEdge`의 `cancelRetry()`가 ctx 없이 불려 **핸들만 버리고 벤더 타이머는 계속 돌던** 결함이다(겹치는 birth edge마다 고아 타이머 하나). 인자를 필수로 바꾸고 겹침 셀과 exact-once mutant로 고정했다. D5 5셀 LIVE probe가 벤더 wake 표면을 처음으로 실측했다 — `pi.sendUserMessage`는 factory에 있고(ctx 아님), idle에서 턴을 시작하며(+31ms), `ctx.setInterval`은 idle에서 돌고 취소는 `ctx.clearTimer`뿐이다(`clearInterval` 없음 → `?.` 호출은 조용한 no-op). 확장 핸들러 순서가 디렉터리명 collation을 따르고, birth보다 먼저 도는 유닛은 sender marker를 못 본다는 것도 실측(20ms). D3 격리는 살아있는 omp 시민 2개로 증명 — Copilot 행이 아직 PENDING으로 두고 있는 셀이다.
- **2026-08-28 (오후):** oracle에서 Bundle A를 실제로 설치·배포·수용. stale writer 두 축(omp 확장, Claude shared reader)을 doctor가 잡아 재배포. LIVE outbound 4건, subagent zero-mint, inbound fail-closed 모두 재현. OMP `tools.xdev` 기본값이 MCP 도구를 `xd://`로 감싸 거짓 발신 보고를 만든다는 것을 벤더 바이너리·트랜스크립트로 측정하고 3개 문서에 반영.
- **2026-08-28 (오전):** #87 Bundle A source, package and doctor hardening reviewed independently; qualification and final deterministic floor were green on the final candidate.
- **2026-08-27:** OMP vendor measurement and real TUI/subagent observations closed the Bundle A admission basis.

# CARRIED

- **`release_gate()` does not run `check-pack-install`** — measured 2026-09-06 while landing #104
  (`awk` over the function body: 0 hits; the gate is `prepublishOnly` + the CI install-surface
  job). That is how an OMP-absent fixture gap sat red on any omp-carrying host from 0.16.0 to
  0.18.0 without a single floor noticing. Whether the heavy gate belongs in the release MUST tier
  is an evidence-policy question, not this lane's — it sits beside #103, and it is recorded here
  rather than opened, because nothing about it is currently broken.

- **#78** macOS/native-Windows portability — separate grant; do not mix into #87.
- **#76** cortex gate slice — separate lane. (#72 is closed: `ca52fdd`.)
- **ACP 깊은-컨텍스트 내구성 — #92 CLOSED (2026-09-03), 관측만 이월.** thinkpad 코퍼스 1,022파일 전수로
  (a)가 두 번째 호스트에서 재현되고(peak `585,001`, 500k 초과 5세션 중 4개가 resets 0) 마지막까지 열려
  있던 (e) 갭 노출이 닫혔다 — ACP도 TTL 재작성을 지불하며 그 비율은 같은 호스트 네이티브와 구별되지
  않는다(1–2h 75% vs 85.6%, 2h+ 100% vs 80%). 구조적 우위는 warm(<5분) 구간뿐이고 거기서 29배
  (0.01% vs 0.29%). 깊은 ACP 리셋 29건 중 22건이 60분+ 유휴 직후, 7건은 아니며 그 7건은 전부
  2026-06-14 이전이다(원인 미측정). **열린 관측:** (f) pi 재시작 재구축 · (g) organic compaction 뒤
  의미·품질(recall probe) · `SessionModelLockedError` 미재현 · 585k–1M · 위 7건의 원인.
- **ACP 계측 — #96 CLOSED (2026-09-03), 캐리어 없이 대체 계측으로.** 업스트림 0.73.0도 왕복별 4분할을
  버린다(measured: `dist/acp-agent.js:3279-3284` 계산 → `:3286-3297` 스칼라만 emit, `_claude/usage` 없음).
  0.17.0이 `usage.acp` + `cache miss ≥Nk re-billed` 공지로 그 신호를 자체 확보했고, 남은 것은 TTL이 왕복
  사이에 만료될 때 bound가 약한 floor가 된다는 한계뿐이다(`backend.ts:1286-1288`). 계약은 산문이 아니라
  `scripts/mutants/acp-usage-accounting.json` 12뮤턴트가 지킨다. **agent-config 쪽 두 줄은 아직 고아다** —
  기본 pi 푸터로 복귀 금지, 캐리어 착지 시 `nocache` 가드 필요. 항구적 자리는 `glg-footer.ts` 헤더 주석.
- **컴팩션 소유권 반환 — #94, 커밋 `3bb0f9e`+`2f53a97` (푸시 전). 0.17.2에 실린다.**
  `autoCompactEnabled` / `env.DISABLE_AUTOCOMPACT`가 managed → retired로 옮겨졌다. 무엇을 왜는
  이슈 #94와 두 커밋이 진다.
  **prepare가 CHANGELOG로 올릴 것:** `env.DISABLE_AUTOCOMPACT`는 Claude 2.1.259에서 **no-op였다**
  (벤더가 읽는 이름은 밑줄 있는 `DISABLE_AUTO_COMPACT`/`DISABLE_COMPACT`, 우리 이름은 0회 등장).
  실제로 억제하던 것은 `autoCompactEnabled: false` 하나뿐이었다. 측정과 계보는 이슈 #94 §정정.
  **열린 후속 둘:** (a) `overlay.ts:29-33`의 `hooks:{}` LIVE 관측 1회 — 주석의 컴팩션 사유가
  `settingSources: []` 아래에서 stale일 가능성. (b) doctor가 retired NOTE를 화면에 못 보여준다
  (`meta-bridge-doctor.sh:121`이 stdout을 버린다) — 고치면 오라클 needle이 움직이므로 별건.
- **#98 딜리버리 투명성 — 커밋 `6306f93`(Phase 1 랩) + `c10b904`(Phase 2 제품), 푸시 전. 0.17.2에 실린다.**
  형제 우편이 도착하고 읽혔는데 사람 화면에는 `Stop hook feedback` 한 줄만 뜨던 것을 닫았다.
  무엇이 왜 들어갔는지는 두 커밋 메시지와 이슈 #98이 진다 — 여기서 되풀이하지 않는다.
  **Upgrade note (CHANGELOG 필수):** pull 뒤 **`install-meta-bridge` 1회**. 플러그인 템플릿에
  `rewakeSummary`/`rewakeMessage`가 생겨서, 안 하면 doctor가 `installed manifest DIFFERS … Re-run
  ./run.sh install-meta-bridge`로 빨개진다. 열린 Claude 세션은 옛 manifest를 캐시하므로 재시작
  전까지 옛 화면이다. oracle이 첫 대상.
  **열린 후속 둘:** (a) control-socket이 죽어 mailbox로 re-resolve된 `fallback-sent` 경로가
  `messagePath`를 버린다 — `entwurf-v2-send.ts:221`, `sendViaMailbox`의 반환에서 `success`만 읽는
  자리다. 발신자에겐 같은 우편인데 파일명이 없다. (같은 모양의 `:212`는 control-socket 재전송이라
  애초에 이름 붙일 파일이 없다 — 거기는 결함이 아니다.)
  (b) P4 관측창(`mailbox-watch.py`)의 제품 승격 여부는 GLG 결정 — `scripts/`로 옮겨 `run.sh`에
  넣거나, 랩에 둔 채 수동 실행.

  **별건 둘:** `lastDeliveredAt` 필드 제거는 마이그레이션이고(리더가 이중으로 엄격 + 매 도장마다
  재파싱, 온디스크 v1 180여 개), `stampMailboxReceipt`의 2-writer lost-update는 오늘 이미 있는 경합이다.
- **0.16.1 make** — prepare는 끝났고 make는 GLG 승인 대기. 오늘 요청 없었다.

# LEDGER — land 전에 정할 것

- **B에서 닫힌 것:** L1(두 state smoke가 `check:hermetic`에 편입, 이제 receive 짝까지 셋), L3(doctor가 `tools.xdev`를 읽고 LIVE 스모크도 선행 검사), L4(`entwurf_self`의 mailbox 렌더가 이제 참이다 — 드레인하는 프로세스가 실제로 있다).
- **B가 일부러 닫지 않은 것 (정직하게 기록):** event loop wedge 셀. marker는 "살아있는 소유자가 arm을 시도했다"까지만 뜻하며 watch 등록 ack이 아니다 — Claude 레일이 `meta-bridge-hook.ts:279-280`에서 같은 문장으로 이미 인정한 잔여 위험이고, OMP는 새로 만드는 게 아니라 물려받는다. 닫으려면 marker heartbeat + 리더 쪽 max-age가 필요하고 그건 claude·copilot 레일을 동시에 움직이므로 별도 이슈감이다.
- **런타임 extension reload/disable 셀은 미측정**이다. doctor 노트로만 남아 있다.

- **L2 CHANGELOG — 닫힘:** `## Unreleased`가 구현 범위 `v0.15.1..19ad90c` 30커밋 전수로 채워졌다(그중 `ec311a2`·`c3894be`·`7e45057`·`1143177` 4개는 v0.15.1 이후 이미 origin/main에 있던 것). 그 위에 쌓이는 릴리즈 준비 커밋은 이 30에 포함되지 않으므로, 범위를 다시 셀 때는 `v0.15.1..HEAD`가 아니라 이 끝점을 쓴다. 섹션 승격·버전 범프·release-gate 수치는 prepare 몫이고, Verification의 release-gate 줄은 일부러 빈 슬롯으로 남겼다. 이 리포의 릴리즈 도구는 CalVer `tag-release`가 아니라 SemVer `.claude/skills/entwurf-release`의 4모드다.
- **L5 claude 시민의 model 필드 — 답 나옴, 고치는 일만 남음 (#90 CLOSED):** 설치된 Claude Code **2.1.245**에서 우리 훅 stdin을 캡처한 결과, interactive `SessionStart` 봉투는 `model`을 **문자열**로 보낸다(`claude-opus-5[1m]`). print 모드(`claude -p`)는 아예 안 보낸다. 우리 리더(`meta-bridge-hook.ts:184-191`)가 객체 `.id`/`model_id`만 받아 그 문자열을 버리므로 claude-code 레코드는 0/353이다. 남은 일: 리더를 문자열 수용으로 넓히고 birth-hook fixture로 고정하되 **print 모드의 부재도 같이 고정**한다. 벤더 버전이 오르면 캡처를 다시 떠야 답이 유지된다. 별도 grant.
- **L8 OMP child가 bridge 권한을 물려받는다 (측정, GLG 세션 2026-08-28):** OMP task child의 `entwurf_self`는 **부모의 garden id**를 반환한다(두 번째 주소 없음 — §3.5 요구사항 충족, 게이트가 증명하는 그대로). 그러나 그 빌린 신원으로 `entwurf_v2`와 `entwurf_fresh_call`을 호출할 수 있다. §3.5(b)가 도구 차용을 의도적으로 허용하므로 깨진 불변식은 아니다. **열린 질문은 C에서 닫혔다 — 판정이 아니라 원칙으로:** `docs/adding-a-harness.md` §3.5의 principal doctrine이 visible host citizen을 가든 principal로 두고, 내부 위임과 그 책임을 그 시민·벤더 소유로 명시하며, Entwurf가 내부 ACL·subagent provenance·시민 아래 authority 축을 만들지 않는다고 못박았다. 빌린 신원의 dispatch는 principal이 자기가 고른 delegate를 통해 보낸 것이다. 따라서 아래 울타리 측정은 참고 자료로만 남는다. 값싼 울타리 후보 측정: omp 18.0.0에 subagent의 MCP 접근을 막는 `mcp.*` 키는 없으나 `task.enableLsp`(기본 false)가 **subagent별 개별 도구 차단 기제가 존재함**을 증명한다. 자체 tool set을 든 custom agent 정의는 미검증 단서.
- **L6 벤더 드리프트:** 이 호스트는 아직 **omp 18.0.0**이다(2026-08-30 측정: `omp --version`). 벤더는 **18.0.11**을 알린다(TUI 배너). `mode === "tui"` 판별자, `xd://` 동작, 그리고 이제 §M7의 다섯 셀(호출 자리·idle wake·`clearTimer`·핸들러 순서)이 업그레이드 시 재측정 대상이다.
- **L7 ROADMAP:** "현재" 절이 아직 측정 단계로 적혀 있다.

# DURABLE LINKS

- #72 (ACP child가 외부 SIGTERM으로 죽던 건 — 원인 닫힘, 수리 랜딩): https://github.com/junghan0611/entwurf/issues/72

- #87: https://github.com/junghan0611/entwurf/issues/87
- #90 (claude-code model 필드, CLOSED — 측정 완료, 리더 수정만 남음): https://github.com/junghan0611/entwurf/issues/90
- #98 (딜리버리 투명성 — `6306f93` 랩 영수증 + `c10b904` 제품, 푸시 전): https://github.com/junghan0611/entwurf/issues/98
- #101 (세션 전환 유령 시민과 거짓 배달 — 수리 랜딩, 0.18.0에 실린다): https://github.com/junghan0611/entwurf/issues/101
- Admission path: `docs/adding-a-harness.md`
- OMP operator boundary: `docs/setup-clean-host.md` §4b
- OMP tool-surface dialect: `docs/external-mcp-host.md` OMP row
