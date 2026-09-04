# NEXT — #102 CI qualification budget stage 1 (`ci/99-stage1`)

> 브랜치 전용 boot sector. 머지 전에 삭제한다. 사람 말 정본은 **#102 본문**,
> 측정 정본은 **#99 Opus 5 측정 댓글**과 그 아래 코디네이터 결정 댓글이다.
> 본문과 스레드가 어긋나면 스레드가 이긴다.

# RAIL — 현재 좌표

- [x] **1. 원본 읽기 + 브랜치 개설** — #102 본문, #99 스레드 전문, `check-gate-qualification.ts`,
      `mutation-qualify.ts`, `check-release-gate-outcomes.ts`, `release-gate.json`,
      `bridge-command-boot.json`, `ci.yml`, `package.json` `check:*`. `ci/99-stage1` @ `67c4086`.
- [x] **2. 조각 넷 구현 + 새 claim/뮤턴트** — P1 머리 게이트(`--manifests-only` → `run.sh
      check-gate-manifests`) · P3 · P6a · C1. 새 claim 4개, 뮤턴트 364→368, lane 39→40.
- [x] **3. inner loop (바뀐 게이트만)** — typecheck 0 · lint 0 · `check-gate-manifests` 0 (8.06s) ·
      `check-release-gate-outcomes` 0 · `check-omp-birth-hook` 0 · `check-shell-quote` 0 ·
      `check-install-surface` 0 (git add 후). 전체 바닥 미개봉.
- [x] **4. 독립 리뷰 → amendment 한 번들** — Blocker 0 / Defect 2 / Observation 3. D1(두 tier 산문 정정),
      D2(#102 acceptance 2 의 "51 그룹" 은 코디네이터 산술 오류, 이슈 본문 정정됨), 셀 9 전제 주석 한 줄 반영.
- [x] **5. standalone qualification 1회 + frozen candidate `check:full` 1회 (둘 다 tmux)** —
      **368/368 KILLED, exit 0**, 38.9분(22:47:31→23:26:24), 52 그룹, control 816.4s / 뮤턴트 1506.2s.
      `pnpm run check:full` **exit 0, 472s**. 워크트리·index 는 두 실행 내내 불변.
- [x] **6. 산문 스윕 → GLG 승인 뒤 커밋** — 커밋 `8649967` (floor 가 본 트리 그대로).
- [ ] **7. GLG 아침 판단** ← CURRENT: main 머지 여부 + 2단계(P2/P5/P6b) 분할. 푸시 없음.

현재 좌표: 1–6 완료 → 7 GLG 판단 대기 (푸시·머지 금지)

# NOW

- **Current:** 1단계가 브랜치에 랜딩했다 — `8649967`. 두 축 모두 초록. 푸시·머지 없음.
- **Next:** GLG 가 아침에 (1) `ci/99-stage1` 을 main 에 머지할지, (2) 2단계(P2 이벤트 좁히기 /
  P5 잡 분리 / P6b 느린 그룹 재배치)를 어떻게 쪼갤지 정한다. 머지 전에 이 파일을 삭제한다.
- **Blocker:** 없음. 대기만 남았다.
- **Read:** `#102` 본문 · `#99` 댓글 5541060606(측정)과 그 아래 결정 댓글 ·
  AGENTS.md "Verification scheduling" / "Kill-proof discipline" / "When changing a contract/gate".
- **Do not touch:** 본체 qualification 의 뮤턴트 실행 계약 · P2(이벤트 좁히기) · P5(잡 분리) ·
  P6b(느린 그룹 재배치) · `check:full`/`check-gate-qualification`/`release-gate` 를 약화하는 어떤 변경.
  워크트리 안에 로그를 남기지 않는다(scratch 전용). 하네스 백그라운드 도구로 긴 명령을 돌리지 않는다.

# RECENT

- [2026-09-04] 측정에서 온 사실(전부 **[외부: #99 Opus 5 댓글]**): 549 run 중 qualification 이
  잡은 5건 전부가 뮤턴트 실행 **이전**(머리 8초 3건, control-pre 2건)에서 나왔다 · semver 태그
  push run 66/66 이 이미 빌드된 SHA 재빌드, 브랜치 run 에 없던 사실 0건 · 뮤턴트가 지목하는
  run.sh 게이트 48 중 47이 `check:full` 안, 예외는 `check-omp-birth-hook` 하나 ·
  `bash scripts/smoke-agy-install-state.sh` 와 `bash run.sh smoke-agy-install-state` 가 서로 다른
  그룹이 되어 control 1쌍(63.8s)을 두 번 낸다.
- [2026-09-04] **여기서 측정** — 착수 시점 인벤토리: 364 뮤턴트 / 52 그룹
  (`python3` 로 `scripts/mutants/*.json` 의 gate argv 를 집계). **그룹 수는 52로 불변이다** —
  P6a 가 −1(agy 중복 제거)이고 P1 이 +1(`check-gate-manifests` 새 그룹)이다. 절감은 비싼
  control 쌍을 싼 쌍으로 바꾸는 것이지 그룹 수를 줄이는 것이 아니다(#102 acceptance 2 정정 완료).
- [2026-09-04] **여기서 읽음** `scripts/check-setup-qualification.sh:3-6` — 이 게이트는
  뮤턴트 매니페스트가 **직접** 부르고 "deliberately NOT a run.sh subcommand and NOT in any check
  tier" 라고 자기 소스에 적혀 있다. 따라서 P3 의 계약은 "모든 게이트가 `check:full` 안"이 아니라
  "`check:full` 안에서 돌거나, 자기 소스가 그 제외를 문장으로 말한다"여야 한다.

# LEDGER

- 브랜치: `ci/99-stage1` @ base `67c4086` (main).
- acceptance 는 #102 의 6개. acceptance 2 의 control 초는 #99 A-1 의 856.8s 와 **절대값으로
  비교하지 않는다** — 같은 로그에서 그룹 수(52→51)와 control 합계를 뽑아 상대로 보인다.
- 커밋은 GLG 승인 뒤 `commit` 스킬로만. 푸시 없음.

# 리뷰 요청 시점의 측정 (2026-09-04, oracle, 전부 여기서 측정)

- 뮤턴트 364 → **368**, lane 39 → **40**, 그룹 52 → **52**.
  P6a 가 −1(agy 중복 그룹 제거)인데 P1 이 +1(`check-gate-manifests` 라는 새 gate argv 그룹)이라
  순증감 0이다. **#102 acceptance 2 의 "그룹 51개" 는 산술이 틀렸다** — 코디네이터 판단 대기.
  절감은 실재한다: control 쌍이 agy **64.5s**(32.0+32.5) 에서 머리 **16.1s**(8.0+8.1) 로 바뀐다.
- 새 claim 4개 전부 실제 러너로 KILLED:
  `MANIFEST-SET-INTEGRITY-REFUSED` 7.5s · `LANE-INVENTORY-DECLARED` 4.6s ·
  `MUTANT-GATES-INSIDE-FULL-FLOOR` 0.9s · `CI-TAG-PUSH-NOT-REBUILT` 0.9s.
  인접 claim 2개(`QUALIFICATION-SCHEDULING-REACHABLE`, `CI-FULL-FLOOR-QUALIFIED`)도 각자 이유로
  KILLED — 셀 순서 충돌 없음. P6a 로 옮긴 3개도 새 argv 그룹에서 KILLED, control ok.
- `check-gate-manifests` 단독 **8.06s**, exit 0.
- **여기서 읽음** `scripts/check-setup-qualification.sh:3-6` — 이 게이트는 자기 헤더로 tier 밖임을
  선언한다. 그래서 `[QK:MUTANT-GATES-INSIDE-FULL-FLOOR]` 는 "check:full 안이거나 자기 소스가
  제외를 말한다"로 썼다(셀 7 의 `DOCUMENTED_EXCLUSIONS` 관용구).
- 산문 이동이 기존 claim 을 건드린 유일한 지점: `[QK:QUALIFICATION-SCHEDULING-REACHABLE]` 의
  VERIFY needle 을 "on every push" → "on every branch push" 로 같이 옮겼다.

# 랜딩 증거 (2026-09-04, oracle, 전부 여기서 측정)

- **candidate `8649967`** 위에서 두 축을 각 1회씩만 돌렸다.
  - `./run.sh check-gate-qualification` standalone: **368/368 KILLED, exit 0**, wall 38.9분
    (22:47:31 → 23:26:24), 스냅샷 411 파일, origin HEAD `67c40869b6ce`,
    `origin checkout: HEAD + work-surface content hash identical before/after`.
    로그: scratch `qual102.log` (워크트리 밖, awk strftime KST 타임스탬프).
  - `pnpm run check:full`: **exit 0, 472s**. 그 안에서 `check-omp-birth-hook` 124 assertions ok,
    `check-gate-manifests` 368 mutants / 40 lanes ok 를 확인했다.
- **그룹 816.4s / 뮤턴트 1506.2s / 104 control 실행 / 52 그룹.** #99 A-1(control 856.8s,
  뮤턴트 1461.4s, 52 그룹)과 **절대값으로 비교하지 않는다** — 두 실행의 호스트 부하가 다르다.
  같은 로그 안에서 읽는 상대값: control 비중 37.0% → **35.1%**, 그리고 이번 실행 자신의 요율로
  agy control 쌍 66.2s 하나가 사라지고 머리 쌍 16.4s 하나가 들어왔다.
- 산문 스윕 두 축 완료: "on every push" 4곳 + CONTRIBUTING.md · entwurf-release SKILL.md ·
  run.sh release_gate 주석 · AGENTS/VERIFY floor bullet. 은퇴 어휘 신규 없음.
- 이 파일의 최종 좌표 갱신만 floor 이후에 이뤄졌다. 그래서 별도 커밋으로 분리했다 —
  `8649967` 은 floor 가 본 트리와 바이트 동일하다.
