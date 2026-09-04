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
- [ ] **4. 코디네이터에게 리뷰 요청 → amendment 한 번들** ← CURRENT: 요청 보냄, 회신 대기
- [ ] **5. standalone `check-gate-qualification` 1회 + frozen candidate `check:full` 1회 (둘 다 tmux)**
- [ ] **6. 산문 스윕 → GLG 승인 뒤 `commit` 스킬** — 푸시는 GLG 몫

현재 좌표: 1–3 완료 → 4 리뷰 회신 대기

# NOW

- **Current:** candidate 굳음. 코디네이터(20260904T213456-dfdfc4)에게 리뷰 요청을 보냈고 회신 대기.
- **Next:** (1) amendment 번들 수령·반영 → (2) tmux 에서 `./run.sh check-gate-qualification`
  standalone 1회(awk strftime 타임스탬프, scratch 로그) → (3) frozen candidate 위 `pnpm run check:full`
  1회 → (4) GLG 승인 뒤 `commit` 스킬.
- **Blocker:** 리뷰 회신. floor 는 그 전에 열지 않는다.
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
