# NEXT — `ci/99-stage2` (#103 조각 1)

> 브랜치 전용 disposable boot sector. **머지 전에 삭제한다** (#102 의 stage-1 NEXT 는
> 삭제가 늦어 머지에 딸려 갔다 — 그 실수를 반복하지 않는다).

# RAIL — 조각 1 좌표

- [x] **0. 브랜치 개설** — `ci/99-stage2` @ `c9db6c7` (푸시된 main 위).
- [x] **1. 설계 단락 → 코디네이터(Fable) 리뷰** — 승인(D1 → 새 셀 8c, D2 → headSha 무조건
      유지 + `event=` 표기). 이슈 본문의 "8a 확장"은 스레드가 이겼다.
- [x] **2. 구현** — 5파일(예상 4 + `check-gate-qualification.ts` 의 lane 인벤토리 선언).
- [x] **3. inner loop** — `check-release-gate-outcomes` exit 0 · `check-install-surface` exit 0
      (`git add` 뒤) · `check-gate-manifests` 370/40 green · tsc(scripts) · biome. 손 뮤턴트
      1회로 KILL 확인: `[QK:RELEASE-SHA-QUALIFIED-IN-CI]` 로 red(exit 1), 복원 후 control exit 0.
- [x] **4. candidate 동결 → Fable 독립 리뷰 1회 → amendment 한 번들** — Blocker 0 / Defect 5
      (D-1 원격 브랜치 헤드 · D-2 dispatch run bounded poll · D-3 블록 헤더 THREE claims ·
      D-4 VERIFY.md:79 라이브 산문 · D-5 이 RAIL), 한 번들로 반영.
- [ ] **5. `check-gate-qualification` standalone 1회 + `pnpm run check:full` 1회** ← CURRENT
      (둘 다 tmux, 도는 동안 HEAD·인덱스·워크트리 이동 금지). 370 전부 KILLED 이어야 한다.
- [ ] **6. GLG 승인 뒤 `commit` 스킬. 푸시는 GLG.**

# 조각 1 범위 (이슈 #103 본문 그대로)

1. `.claude/skills/entwurf-release/scripts/verify-exact-ci.sh` — required 튜플에 **네 번째 축**:
   그 run 의 `check` 잡 안에서 `./run.sh check-gate-qualification` 스텝이 실행되어 success 였는가
   (skipped 는 실패). dispatch run 이면 `headSha == SHA` 재확인.
2. `.claude/skills/entwurf-release/SKILL.md` land L3 / make M2 — 본체가 그 SHA 에서 안 돌았으면
   `gh workflow run ci.yml --ref <branch> -f qualify=true` + 대기 + 오라클 재실행.
   **ASCII 전용 파일** (`scripts/check-install-surface.ts:494` S7e, 오라클은 :495 S7g).
3. `.github/workflows/ci.yml` — `workflow_dispatch` 에 `qualify` 입력. **본체 스텝의 `if` 는
   조각 2 몫이다 — 여기서 넣지 않는다.**
4. `scripts/check-release-gate-outcomes.ts` + `scripts/mutants/release-gate.json` — 네 번째 축을
   지운 오라클이 초록으로 통과하면 KILL 실패. `[QK:<claim>]` 라벨 + exact-once 뮤턴트.

**조각 1 만으로 커밋 가능해야 한다** — 조각 2 없이 오라클이 더 엄격해질 뿐 아무것도 약해지지 않는다.

# 측정해 둔 것 (구현 전 실측)

- **네 번째 축은 추가 API 호출이 필요 없다** [측정 2026-09-06]:
  `gh run view 34027762637 --json jobs` 가 각 잡의 `steps[]` 를 이미 실어 온다 —
  `{"name":"Run ./run.sh check-gate-qualification","conclusion":"success","number":7}`.
  오라클이 이미 부르는 그 한 번의 `gh run view` 에서 읽으면 된다.
- **`find_run` 의 `--event push` 가 dispatch run 을 배제한다** [읽음
  `verify-exact-ci.sh:21-30`]. 조각 1 의 복구 경로(dispatch)를 오라클이 보려면 이벤트 축을
  넓혀야 한다. `headSha == SHA` 는 :29 와 :60 에 **이미** 있고, dispatch 를 들이는 순간
  그 검사가 비로소 하중을 받는다(`gh workflow run --ref` 는 SHA 를 못 받는다).
- **셀 10 은 `on:` 블록을 2칸 들여쓰기 키로 훑는다** [읽음
  `check-release-gate-outcomes.ts:538-560`]. `workflow_dispatch:` 를 `pull_request:` **뒤**에
  두면 `push:` 의 nextKey 는 그대로 `pull_request:` 라 셀 10 은 무사할 것으로 본다 — inner loop 에서 확인한다.
- **`check-install-surface` S7g** 는 이미 오라클이 `headSha` + 잡 3개를 묶는지 본다
  [읽음 :512-522]. 네 번째 축을 거기 또 넣지 않는다(계약 하나에 오라클 하나).

# Do not touch

- 본체 스텝의 `if` (조각 2) · 경로 판정 스크립트 (조각 2) · `schedule` (조각 2).
- 셀 8b 의 순서 계약 · 셀 10 · P5 잡 분리 (범위 밖, 증거 정책 결정).
- main 의 `NEXT.md`.

# Observation (일 안 연다)

- **행동 오라클은 보류.** 8c 는 문자열 오라클이다(S7g 와 같은 등급). 분류기를 별도 파일로 빼면
  S7a/S7g 의 "오라클 파일 하나를 index 에서 읽는다" 계약까지 손대야 하고, `RUN_JSON` env seam 은
  실제 릴리즈에서 gh 를 우회하는 세탁 경로가 된다. 둘 다 이 축의 값보다 비싸다 (Fable 결정, 2026-09-06).
- **`check-gate-qualification` 에는 lane 좁히기 옵션이 없다** [측정: `--manifests-only` 와
  `--attribution-self-test` 뿐, `scripts/check-gate-qualification.ts:74,169`]. 전수는 candidate
  동결 뒤 1회(tmux).
- **이벤트 필터를 되돌리는 회귀는 fail-closed 다** — `--event push` 로 되돌리면 dispatch run 을
  못 찾아 "no push- or dispatch-triggered run" 으로 ABORT 한다. 조용히 통과하지 않으므로
  claim 을 새로 만들지 않았다.
