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
- [x] **5. `check-gate-qualification` standalone 1회 + `pnpm run check:full` 1회** —
      **370/370 KILLED exit 0 (2392s)** · **check:full exit 0 (483s)**, 둘 다 tmux, 동결 트리 불변.
- [x] **6. 조각 1 커밋 + 푸시** — `92dc6dd`, `origin/ci/99-stage2` 신설, 어젠다 도장 1회.
      브랜치 push CI **run 34034426691**.

# RAIL — 조각 2 (경로 필터)

- [x] **7. 설계 단락 → Fable 승인** — `if` 를 `run` **뒤**에(8a 리터럴 + 조각 1 스텝 이름 동시 보존),
      claim 둘로 분리, fail-open ①~⑤, `fetch-depth: 0`, schedule 주 1회.
- [x] **8. 구현** — 아래 파일들.
- [x] **9. candidate 동결 보고 → Fable 리뷰 → amendment** — Blocker 0 / Defect 1
      (D-1 `qualify` 입력이 죽은 설정이었다: dispatch 를 값과 무관하게 fail-open 3 으로 보냈다.
      이제 `CI_QUALIFY=true` 만 본체를 돌리고, 그 외 dispatch 는 `run_body=false` + "floor-only
      rerun" 사유). Observation 4건은 아래.
- [x] **10. qualification + check:full 각 1회(tmux)** — 2회차 **372/372 KILLED exit 0 (2425s)** ·
      **check:full exit 0 (489s)**, 동결 트리 불변. **1회차는 RED 였고 그게 설계 결함을 잡았다** — 아래.
- [ ] **12. GLG 커밋 승인 대기** ← CURRENT. 승인 오면 `commit` 스킬로 한 커밋. 푸시는 GLG.
- [ ] **11. acceptance 5 준비** — 조각 2 커밋 **뒤** 별도 커밋 둘: (a) `.md` 한 줄(본체 skipped 기대),
      (b) 뮤턴트 매니페스트 `title` 한 글자(subject 불변 → kill 결과 불변, 본체 실행 기대). 푸시는 GLG.

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

# Observation — 조각 2 (일 안 연다)

- **8d 는 경로마다 bash+python 을 새로 띄운다**(약 70회, 지금 수 초). 인벤토리가 크게 자라면
  `--files-from` 에 여러 경로를 묶어 한 번에 도는 최적화 후보 (Fable, 2026-09-06).
- **8e 의 `if (wrong.length > 0) continue;`** 는 첫 결손 뒤 나머지 run 판정을 생략한다 —
  여전히 red 이고 이름도 부르지만 진단 정보가 준다. 손대지 않는다.
- **뮤턴트 A 의 kill 은 "글로브 밖 `signatureSource` 가 하나 이상 존재한다"에 기댄다.**
  언젠가 전부 글로브 안으로 들어가면 SURVIVED 로 드러난다 — 그게 qualification 의 일이다.
- **PR 은 three-dot 으로 좁힐 수 있으나 안 한다** (fail-open ⑤). 이 리포는 PR 을 거의 안 쓴다.
- **`scripts/ci-qualify-decide.sh` 와 `scripts/fixtures/` 가 npm 패키지에 실린다**(`files: scripts/`,
  447 → +2). `scripts/check-*` 선례와 같고 소비자 표면이 아니다. 별건.
- **`fetch-depth: 0` 실제 비용**은 첫 실관측 run 의 checkout 스텝 시간으로 보고한다.
- **8f 의 fixture 커밋에 `-c commit.gpgsign=false` 를 더하면 더 안전하다** — 전역 서명 설정이 있는
  호스트에서 그 커밋이 죽는다. [측정 2026-09-06: 이 호스트는 `commit.gpgsign` 미설정, CI 러너도
  없음 → 지금 red 위험 0] 다음에 이 게이트를 만질 때 코드와 함께 (Fable 결정, 이번 라운드 밖).

# 1회차 긴 게이트가 잡은 것 (2026-09-06 22:05→22:45)

**`check-gate-qualification` EXIT=1, 355/372 — release-gate lane 17개 전부 CONTROL-RED.**
원인: 셀 8e 가 리포 **히스토리**(2026-07/08 커밋 객체)를 읽었는데, qualification 은 게이트를
**자체 git baseline 을 가진 스냅샷** 안에서 돌린다 — 거기엔 그 커밋이 없다. "로컬 객체 없으면
이름 불러 red" 규칙이 운영자 클론에서는 옳고 스냅샷에서는 lane 전체를 죽였다.
[측정: `control-pre bash run.sh check-release-gate-outcomes: RED … /tmp/entwurf-qualify-RDwo8T/repo/...:531`]

**수리(설계 변경, Fable 승인 필요):**
- 픽스처가 **측정된 파일 목록**(`files`, `tipOnlyFiles`)을 진다 — 히스토리는 여기서 한 번 읽고
  커밋했다. 8e 는 `--files-from` 으로 그 목록을 매처에 먹인다 → 어디서든 돈다.
- 두-점 **읽기** 자체는 새 셀 **8f `[QK:QUALIFY-FILTER-READS-PUSH-RANGE]`** 가 진다 —
  임시 git 리포를 만들어(스크립트 사본 + 1항 매니페스트 동봉, seam 없음) tip 은 docs 뿐이고
  그 아래 커밋이 subject 를 건드리는 실제 결함 모양을 재현. 두-점 true / tip-only false 를 단언.
- **8e 는 뮤턴트를 갖지 않는다**(8b 선례). [측정] 다섯 range 전부 manifest-subject 히트가 있어
  어떤 단일 팔 제거도 8d 가 먼저 잡는다 → WRONG-REASON 이 된다. 주석에 그 이유를 박았다.
- lane 17 유지, 총 **372**.

**`pnpm run check:full` EXIT=1 (4s)** — biome format 에러 2건(`check-release-gate-outcomes.ts`,
`qualify-replay.json`). `--write` 로 고쳤다. 1회차가 이것도 잡았다.
