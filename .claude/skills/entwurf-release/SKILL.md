---
name: entwurf-release
description: "Operate entwurf SemVer releases through four explicit modes: land, prepare, make, and publish. Use for pre-version exact-SHA CI landing, CHANGELOG and package preparation, static and LIVE gates, prepared-HEAD CI, exact artifact acceptance, tag and GitHub release creation, repair-dist-tag publication, and post-publish registry proof. Each mode is a separate authority boundary. Triggers: release land, prepare-release, make-release, publish release, release cut, prerelease, repair release."
user_invocable: true
---

# entwurf-release

Repository: `~/repos/gh/entwurf`.

This skill is the shared release-operation SSOT that replaces the former
`.pi/prompts/prepare-release.md` and `.pi/prompts/make-release.md` files.
Claude Code discovers it natively under `.claude/skills/`; pi discovers the same
file through `.pi/settings.json` and its `"skills": ["../.claude/skills"]`
entry.

## Invocation

```text
# Claude Code - stable example
/entwurf-release land 0.12.8
/entwurf-release prepare 0.12.8
/entwurf-release make 0.12.8
/entwurf-release publish 0.12.8 /absolute/path/to/candidate.tgz latest

# pi - prerelease/repair example
/skill:entwurf-release land 0.12.8-repair.1
/skill:entwurf-release prepare 0.12.8-repair.1
/skill:entwurf-release make 0.12.8-repair.1
/skill:entwurf-release publish 0.12.8-repair.1 /absolute/path/to/candidate.tgz repair
```

Natural-language requests map to the same four modes.

- `land` pushes an already reviewed pre-version HEAD and waits for the required
  exact-SHA CI jobs. It never edits, versions, tags, or publishes.
- `prepare` edits release records, runs deterministic and LIVE gates, and creates
  the release-prep commit. It never pushes, tags, or publishes.
- `make` pushes the prepared HEAD, waits for exact-SHA CI, creates and accepts one
  preserved candidate, then tags, stamps, and creates the GitHub release. It
  never runs `npm publish`.
- `publish` publishes only the already accepted preserved candidate under an
  explicitly supplied dist-tag and proves the registry-installed result.

The invocation authorizes only the named mode. `prepare` is not `land`
authorization. `make` is not `publish` authorization. If the mode, version, or a
mode-specific required argument is missing, ask for it and stop.

## Shared version contract

Accept a normal SemVer release or prerelease. Reject a leading `v`.

```bash
VERSION="<user argument>"
case "$VERSION" in
  "") echo "ABORT: version required (for example 0.12.8 or 0.12.8-repair.0)"; exit 1 ;;
  v*) echo "ABORT: drop the leading 'v'"; exit 1 ;;
esac
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
  echo "ABORT: version must be SemVer, optionally with a prerelease suffix"
  exit 1
fi
```

Valid examples: `0.12.8`, `0.12.8-repair`, and `0.12.8-repair.0`.
`npm version` remains the final package-version validator.

## Exact-SHA CI oracle

The shared helper is the only release instruction that classifies the required
GitHub Actions run:

```bash
CI_ORACLE=".claude/skills/entwurf-release/scripts/verify-exact-ci.sh"
bash "$CI_ORACLE" "$(git rev-parse HEAD)" wait
```

It selects only a push-triggered `ci.yml` run whose `headSha` is the supplied
full SHA, waits when requested, and requires these exact jobs to conclude
`success`:

- `check`
- `install-surface`
- `artifact-consumer`

Use mode `verify` instead of `wait` when a prior run must already be complete.
Never replace this with a branch-level green badge or the newest unrelated run.

---

# LAND

`land` exists for a narrower release contract that requires a pre-version
implementation HEAD to receive its own CI run before release metadata changes.
It is not required for every ordinary release.

A `land <version>` invocation is explicit authorization for one ordinary push of
`main`. It is not authorization for version edits, tags, GitHub releases, or npm
publication.

## L0. Establish the landing boundary

1. Read `AGENTS.md`, `NEXT.md`, and `VERIFY.md` completely.
2. Read the `commit` skill because its push and post-push stamp rules remain in
   force.
3. Confirm that the current narrower contract actually requires a pre-version
   CI checkpoint. If it does not, stop and direct the operator to `prepare`.
4. Inspect and require a clean, non-diverged `main`:

```bash
git status --short --branch
git diff-index --quiet HEAD --
test "$(git branch --show-current)" = main
git fetch origin main
read -r BEHIND AHEAD < <(git rev-list --left-right --count origin/main...HEAD)
test "$BEHIND" = 0
test "$AHEAD" -gt 0
```

Confirm from the diff and log that HEAD contains only the reviewed landing set.
Do not absorb an unrelated local commit into a release push.

For a required pre-version checkpoint, the package must not already equal the
target version:

```bash
test "$(node -p "require('./package.json').version")" != "$VERSION"
```

## L1. Prove pushability and push main

```bash
SHA="$(git rev-parse HEAD)"
git push --dry-run origin main
git push origin main
test "$(git ls-remote origin refs/heads/main | cut -f1)" = "$SHA"
```

Never force and never bypass verification.

## L2. Stamp the pushed commit

Stamp only after the push succeeds, following the `commit` skill. If the stamp
fails, report the exact error and stop; do not write the agenda target by hand.

## L3. Require exact-SHA CI

```bash
CI_ORACLE=".claude/skills/entwurf-release/scripts/verify-exact-ci.sh"
bash "$CI_ORACLE" "$SHA" wait
```

The oracle requires four axes on one run at that exact SHA: the workflow
conclusion, the three job conclusions, and the `check` job's
`./run.sh check-gate-qualification` step concluding `success`. A skipped body is
not evidence, so it fails the same way a red one does.

If the oracle names the qualification step -- absent or skipped -- the body did
not run at this SHA. Force it, wait, and re-run the oracle. `gh workflow run`
takes a branch, never a SHA, so the branch must still point at `$SHA` when it is
dispatched; the oracle re-checks `headSha` afterwards and refuses a run whose
branch moved.

`gh workflow run --ref` runs the REMOTE branch head, so check that head, not the
local one. And do not sleep: until the dispatch run is registered, the oracle's
newest-run rule would pick the already-finished push run and ABORT on the same
axis. Wait for the run to appear, then hand it to the oracle.

```bash
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git fetch origin "$BRANCH"
test "$(git rev-parse FETCH_HEAD)" = "$SHA"

count_dispatch_runs() {
  gh run list --workflow ci.yml --event workflow_dispatch --commit "$SHA" \
    --limit 20 --json databaseId --jq length
}
BEFORE="$(count_dispatch_runs)"
gh workflow run ci.yml --ref "$BRANCH" -f qualify=true
for _ in $(seq 1 12); do
  sleep 5
  if [ "$(count_dispatch_runs)" -gt "$BEFORE" ]; then break; fi
done
test "$(count_dispatch_runs)" -gt "$BEFORE" || {
  echo "ABORT: no dispatch run appeared for $SHA within 60s" >&2
  exit 1
}

bash "$CI_ORACLE" "$SHA" wait
```

Report the SHA, workflow URL, the run event, all three job conclusions, and the
qualification-step conclusion. End with:

```text
Landing checkpoint complete. Ready for /entwurf-release prepare <version>.
```

---

# PREPARE

`prepare` edits, verifies, and commits. It does not push, tag, create a GitHub
release, stamp a release, notify, or publish.

## P0. Establish the release boundary

1. Read `AGENTS.md`, `NEXT.md`, and `VERIFY.md` completely. A narrower current
   release contract in those files overrides a generic instruction in this
   skill.
2. Read the `commit` skill before creating any commit.
3. Inspect the current state:

```bash
git status --short --branch
git diff --check
```

Do not mix pre-existing implementation or review fixes into the release-prep
commit. If a completed, clearly scoped fix is present and GLG has approved its
commit, close it as a separate atomic commit first. If scope is ambiguous or
unrelated, stop and ask.

If the current contract requires a pre-version landing checkpoint, verify it
before making any edit:

```bash
git fetch origin main
SHA="$(git rev-parse HEAD)"
test "$(git rev-parse origin/main)" = "$SHA"
bash .claude/skills/entwurf-release/scripts/verify-exact-ci.sh "$SHA" verify
```

A missing landing run is not a prepare failure to work around. Stop with the
exact next command: `/entwurf-release land <version>`.

Prepare may commit only release-prep files such as `CHANGELOG.md`,
`package.json`, `pnpm-lock.yaml`, and an evidence handoff explicitly required by
the current release contract.

Forbidden in prepare mode:

- pushes
- tags
- GitHub releases
- release agenda stamps
- notifications
- npm publication
- final candidate creation for a contract that requires post-commit CI first

## P1. Audit changes since the last release

```bash
LAST_TAG=$(git tag --sort=-version:refname | head -1)
printf 'baseline=%s\n' "$LAST_TAG"
git log "${LAST_TAG}..HEAD" --oneline
```

Compare the commit range and closed `NEXT.md` work with the existing
`CHANGELOG.md` `## Unreleased` section. Record only verified changes. Do not
rewrite historical release sections.

## P2. Promote the release section

Use the current KST date and transform the top of the changelog into this shape:

```text
## Unreleased

## <VERSION> - YYYY-MM-DD
```

Keep a fresh empty `## Unreleased` section above the promoted release body.
Preserve the repository's existing heading punctuation if it uses an em dash.

Release-gate paths and summaries may live in the release section or in an
explicit durable operator handoff, following the repository's current
convention. The paths and actual MUST/BEHAVIOR counts must not be lost.

## P3. Update package version and lockfile

```bash
npm version "$VERSION" --no-git-tag-version
pnpm install --lockfile-only
```

Inspect the resulting diff. Do not manufacture a lockfile change when the
resolver produced none.

## P4. Run the deterministic floor

```bash
pnpm run check:full
```

The FULL tier is the candidate floor; the everyday `pnpm check` core alone is
never release evidence. Do not summarize the aggregate as a fixed number of
gates. The current `package.json` check:* scripts are the SSOT. If any check
fails, stop at that axis, fix it, and rerun the complete aggregate.

The check chains carry only the qualification HEAD (`check-gate-manifests`) and
deliberately exclude the mutant-executing body `check-gate-qualification`: the
LIVE release gate (P5) runs the body as its own MUST step, and the exact-SHA CI
`check` job (M2) requires it on the release commit. Do not add a manual
qualification rerun here.

CI runs on branch pushes only. Pushing the release tag creates no run, so the
exact-SHA oracle above always reads the BRANCH push run for that commit.

## P5. Run the LIVE release gate from fresh scratch

Use the `tmux` skill because this command is long-running. Preserve the scratch
directory and complete log.

```bash
SCRATCH=$(mktemp -d "/tmp/entwurf-release-gate-${VERSION}.XXXXXX")
LOG="$SCRATCH/release-gate.log"
set -o pipefail
LIVE=1 ./run.sh release-gate "$SCRATCH" --cut 2>&1 | tee "$LOG"
```

The release gate has two tiers:

- `MUST` is release-blocking and owns the exit code. `FAIL` must be zero, and
  `--cut` enforces the other half: any MUST `SKIP` makes the run red, so a
  release run can no longer hide required LIVE work behind a skip. Each step is
  invoked and reports its own outcome (exit 0 PASS / 97 SKIP / else FAIL); a
  `[entwurf:skip]` line names the prerequisite that was missing. Drop `--cut`
  only for an unattended diagnostic pass, which is not acceptance.
- `BEHAVIOR` is advisory model-in-loop evidence. A failure does not block the
  release, but its PASS/FAIL counts and artifact path must be recorded.

Do not expect a fixed PASS count. Record actual output. Do not waive a MUST
failure without diagnosing and explicitly classifying the failing axis. Do not
hide a BEHAVIOR failure.

**Create no commit while the gate is running.** `check-gate-qualification` pins the origin HEAD it
started on and aborts with `origin HEAD changed during qualification` if that moves, discarding a
~50-minute run. Editing the working tree is harmless; moving HEAD is not. Queue any commit request
that arrives mid-run (including one from GLG) until the gate reports its verdict.

## P6. Apply release-specific pre-commit acceptance

`NEXT.md` and `VERIFY.md` may require gates beyond `pnpm run check:full` and the LIVE
release gate. Apply every requirement that belongs before the release-prep
commit.

For #51-style repair releases, do not create the final candidate here. The exact
candidate must be created from the clean prepared HEAD only after that exact SHA
has been pushed and all three CI jobs are green. `make` owns that post-CI
acceptance. A checkout pack-once result is not release-artifact evidence.

Never claim an unrun gate as passed.

## P7. Create the release-prep commit

Stage only release-prep files. Never pull preceding implementation changes into
this commit.

```bash
git status --short
git diff --check
git diff --cached --check
git commit -m "chore(release): prepare v${VERSION}"
```

Do not bypass hooks. A commit request does not authorize a push.

## P8. Final preparation check

```bash
test "$(node -p "require('./package.json').version")" = "$VERSION"
grep -qE "^## ${VERSION}([[:space:]]|$)" CHANGELOG.md
git diff-index --quiet HEAD --
```

Report:

- prepared version and commit SHA
- `pnpm run check:full` result
- release-gate scratch, log, and artifact paths
- actual `MUST: PASS=n FAIL=0 SKIP=n` (includes the `check-gate-qualification` MUST step)
- actual `BEHAVIOR: PASS=n FAIL=n`
- release-specific work deliberately deferred to `make`
- clean-tree result

End with both harness forms:

```text
Ready for /entwurf-release make <version>.
Ready for /skill:entwurf-release make <version>.
```

---

# MAKE

`make` operates only on an already prepared clean HEAD. It pushes that HEAD,
requires exact-SHA CI, creates and accepts the final candidate, then tags,
stamps, creates the GitHub release, and notifies. It does not edit release files
or run `npm publish`.

A `make <version>` invocation is explicit authorization for ordinary main and
tag pushes plus the GitHub release sequence. Read both the `commit` and
`tag-release` skills before proceeding so their push, safety, and stamp rules
remain active.

## M0. Preflight

Abort on the first failed check.

### Clean tree, version, changelog, gate evidence, and tag absence

```bash
git diff-index --quiet HEAD --
test "$(git branch --show-current)" = main
test -z "$(git tag -l "v${VERSION}")"
test -z "$(git ls-remote --tags origin "v${VERSION}")"
grep -qE "^## ${VERSION}([[:space:]]|$)" CHANGELOG.md
test "$(node -p "require('./package.json').version")" = "$VERSION"
pnpm run check:full
```

`pnpm run check:full` here is the full deterministic floor without
qualification; do not duplicate a manual `check-gate-qualification` run in
preflight. The exact-SHA
CI `check` job (M2) is the axis that requires it.

Confirm that a fresh release-gate scratch/log path and its actual MUST/BEHAVIOR
summary are present in the changelog or durable operator handoff. Do not proceed
when MUST has a failure, evidence is missing, or `NEXT.md` names an unresolved
pre-release blocker.

### GitHub identity and target

```bash
gh auth status
REMOTE=$(git remote get-url origin)
EXPECTED_REPO=$(printf '%s\n' "$REMOTE" | sed -E 's#^git@github(-[a-z]+)?\.com:##; s#^https://github.com/##; s#\.git$##')
GH_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
GH_PERM=$(gh repo view --json viewerPermission --jq .viewerPermission)
test "$GH_REPO" = "$EXPECTED_REPO"
case "$GH_PERM" in
  ADMIN|MAINTAIN|WRITE) ;;
  *) echo "ABORT: GitHub permission is $GH_PERM; WRITE or higher is required"; exit 1 ;;
esac
```

### Non-divergence and push dry-runs

```bash
git fetch origin main
read -r BEHIND AHEAD < <(git rev-list --left-right --count origin/main...HEAD)
test "$BEHIND" = 0
git push --dry-run origin main
git push --dry-run origin "HEAD:refs/tags/v${VERSION}"
```

## M1. Push the prepared HEAD and stamp that push

```bash
SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/main)"
PUSHED_MAIN=0
if [ "$REMOTE_SHA" != "$SHA" ]; then
  test "$AHEAD" -gt 0
  git push origin main
  test "$(git ls-remote origin refs/heads/main | cut -f1)" = "$SHA"
  PUSHED_MAIN=1
fi
printf 'prepared-sha=%s pushed-main=%s\n' "$SHA" "$PUSHED_MAIN"
```

If `PUSHED_MAIN=1`, immediately stamp the pushed commit according to the
`commit` skill before waiting on CI. If main already pointed at this SHA, do not
create a duplicate commit stamp. A stamp failure stops the mode even though the
push has already happened; report that half-complete state exactly.

## M2. Require exact-SHA CI

```bash
bash .claude/skills/entwurf-release/scripts/verify-exact-ci.sh "$SHA" wait
```

A CI failure stops make before candidate creation or tagging. This is the same
four-axis oracle L3 runs, including the qualification-BODY step: if it names that
step, dispatch the body exactly as L3 documents and re-run the oracle. Do not
create a candidate or a tag while that axis is unproven.

## M3. Create and accept one preserved exact candidate

Create the candidate only after exact-SHA CI is green. Keep the directory and
log; do not clean them automatically.

```bash
ARTIFACT_DIR=$(mktemp -d "/tmp/entwurf-release-candidate-${VERSION}.XXXXXX")
LOG="$ARTIFACT_DIR/acceptance.log"
bash scripts/with-dist-lock.sh npm pack --dry-run=false --pack-destination "$ARTIFACT_DIR"
CANDIDATE=$(realpath "$ARTIFACT_DIR/junghanacs-entwurf-${VERSION}.tgz")
test -f "$CANDIDATE"
SHA256_BEFORE=$(sha256sum "$CANDIDATE" | cut -d' ' -f1)
set -o pipefail
ENTWURF_REQUIRE_DOCKER=1 ENTWURF_CANDIDATE_TGZ="$CANDIDATE" \
  ./run.sh check-install-container 2>&1 | tee "$LOG"
SHA256_AFTER=$(sha256sum "$CANDIDATE" | cut -d' ' -f1)
test "$SHA256_AFTER" = "$SHA256_BEFORE"
grep -F "candidate mode: caller-preserved exact artifact (no repack)" "$LOG"
grep -F "candidate canonical-path=$CANDIDATE" "$LOG"
grep -F "artifact sha256=$SHA256_BEFORE" "$LOG"
grep -F "repoDigest=" "$LOG"
```

The handoff must preserve:

- candidate canonical path
- candidate SHA-256
- acceptance log path
- Node image ID
- repository digest
- exact prepared commit SHA

The accepted file is now the only file eligible for `publish`. Never repack it.

## M4. Recheck immutability, tag, and push the tag

```bash
test "$(git rev-parse HEAD)" = "$SHA"
git diff-index --quiet HEAD --
test "$(sha256sum "$CANDIDATE" | cut -d' ' -f1)" = "$SHA256_BEFORE"
git tag "v${VERSION}" "$SHA"
git push origin "v${VERSION}"
test "$(git ls-remote origin "refs/tags/v${VERSION}" | cut -f1)" = "$SHA"
```

Never force and never bypass verification. If tag push fails, stop before the
release stamp, GitHub release, or notification.

## M5. Stamp the release

```bash
REMOTE=$(git remote get-url origin)
REPO_URL=$(echo "$REMOTE" | sed -E 's|git@github(-[a-z]+)?\.com:|https://github.com/|;s|\.git$||')
REPO_NAME=$(basename "$REMOTE" .git)
REPO_TAG=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[-.]//g')
STAMP="$HOME/.pi/agent/skills/pi-skills/agenda/scripts/agenda-stamp.sh"
[ -x "$STAMP" ] || STAMP="$HOME/.claude/skills/agenda/scripts/agenda-stamp.sh"
"$STAMP" \
  "${REPO_NAME}: release v${VERSION} [[${REPO_URL}/releases/tag/v${VERSION}][v${VERSION}]]" \
  "pi:release:${REPO_TAG}"
```

If the stamp fails, report the exact command and error and stop. Do not invent a
manual fallback on the agenda target.

## M6. Create and verify the GitHub release

```bash
NOTES_FILE="/tmp/release-notes-v${VERSION}.md"
VERSION="$VERSION" python3 - <<'PY'
import os
from pathlib import Path

version = os.environ["VERSION"]
lines = Path("CHANGELOG.md").read_text().splitlines()
out = []
inside = False
for line in lines:
    if line.startswith(f"## {version} ") or line == f"## {version}":
        inside = True
        continue
    if inside and line.startswith("## "):
        break
    if inside:
        out.append(line)
Path(f"/tmp/release-notes-v{version}.md").write_text("\n".join(out).strip() + "\n")
PY

test -s "$NOTES_FILE"
gh release create "v${VERSION}" --title "v${VERSION}" --notes-file "$NOTES_FILE"
gh release view "v${VERSION}" --json tagName,name,url
rm -f "$NOTES_FILE"
```

Do not notify until `gh release view` verifies the expected tag.

## M7. Notify

Run only after the GitHub release is verified.

```bash
source ~/.env.local
gog chat messages send "$GOG_CHAT_SPACE_ID" \
  --account "$GOG_CHAT_ACCOUNT" \
  --text "entwurf v${VERSION} released
${REPO_URL}/releases/tag/v${VERSION}"
```

A notification failure does not undo an existing release, but it must be
reported exactly.

Report the release URL plus the preserved candidate path, SHA-256, acceptance
log, image ID, and repository digest. End with the exact publish command but do
not execute it:

```text
/entwurf-release publish <version> <absolute-candidate.tgz> <dist-tag>
```

---

# PUBLISH

`publish` is a separate authority boundary. It never creates a candidate. It
publishes only the exact file accepted by `make`.

A publish invocation requires:

1. version
2. absolute candidate path
3. explicit dist-tag

For example:

```text
/entwurf-release publish 0.12.8-repair.1 /tmp/entwurf-release-candidate-0.12.8-repair.1.X/junghanacs-entwurf-0.12.8-repair.1.tgz repair
```

## U0. Verify release and candidate identity

```bash
CANDIDATE="<absolute candidate argument>"
DIST_TAG="<dist-tag argument>"
case "$CANDIDATE" in /*) ;; *) echo "ABORT: candidate path must be absolute"; exit 1 ;; esac
case "$DIST_TAG" in ""|*[!0-9A-Za-z._-]*) echo "ABORT: invalid or missing dist-tag"; exit 1 ;; esac
# Every publication must prove it did not move the lane it does not own. Capture
# both dist-tags before U1 and assert the untouched lane against its own captured
# value; a version literal kept by hand in this file rots at the next cut. An
# absent tag reads as the empty string, and preserving absence is a valid result.
PRE_PUBLISH_LATEST=$(npm view @junghanacs/entwurf dist-tags.latest)
PRE_PUBLISH_REPAIR=$(npm view @junghanacs/entwurf dist-tags.repair)
export PRE_PUBLISH_LATEST PRE_PUBLISH_REPAIR
CANDIDATE=$(realpath "$CANDIDATE")
test -f "$CANDIDATE"
test "$(node -p "require('./package.json').version")" = "$VERSION"
git diff-index --quiet HEAD --
test "$(git rev-parse "v${VERSION}")" = "$(git rev-parse HEAD)"
gh release view "v${VERSION}" --json tagName,name,url
```

Read package identity from the tarball and require an exact match:

```bash
META=$(tar -xOf "$CANDIDATE" package/package.json | node -e '
let s=""; process.stdin.setEncoding("utf8");
process.stdin.on("data", d => s += d);
process.stdin.on("end", () => {
  const p=JSON.parse(s); process.stdout.write(`${p.name}\t${p.version}`);
});')
IFS=$'\t' read -r NAME CANDIDATE_VERSION <<< "$META"
test "$NAME" = "@junghanacs/entwurf"
test "$CANDIDATE_VERSION" = "$VERSION"
```

Require the sibling acceptance log produced by `make` and bind it to the same
canonical path and digest:

```bash
ACCEPTANCE_LOG="$(dirname "$CANDIDATE")/acceptance.log"
test -s "$ACCEPTANCE_LOG"
CANDIDATE_SHA256=$(sha256sum "$CANDIDATE" | cut -d' ' -f1)
grep -F "candidate mode: caller-preserved exact artifact (no repack)" "$ACCEPTANCE_LOG"
grep -F "candidate canonical-path=$CANDIDATE" "$ACCEPTANCE_LOG"
grep -F "artifact sha256=$CANDIDATE_SHA256" "$ACCEPTANCE_LOG"
grep -F "repoDigest=" "$ACCEPTANCE_LOG"
```

If any evidence is missing, stop. Do not repack or regenerate the candidate.

## U1. Publish the accepted bytes

```bash
npm publish "$CANDIDATE" --tag "$DIST_TAG"
test "$(sha256sum "$CANDIDATE" | cut -d' ' -f1)" = "$CANDIDATE_SHA256"
```

## U2. Verify dist-tags

Apply the lane-specific dist-tag contract. The published lane must equal this
version, and the lane this publication did not touch must still hold the exact
value captured in U0. Stable publication moves `latest` and preserves the
accepted repair line; repair publication moves `repair` and preserves whatever
stable version was current immediately before U1. Read both from the same
post-publish registry snapshot, and never assert a hand-kept literal.

```bash
DIST_TAGS=$(npm view @junghanacs/entwurf dist-tags --json)
case "$DIST_TAG" in
  latest) PRESERVED_TAG=repair; PRESERVED="${PRE_PUBLISH_REPAIR?capture it in U0 before U1}" ;;
  repair) PRESERVED_TAG=latest; PRESERVED="${PRE_PUBLISH_LATEST?capture it in U0 before U1}" ;;
  *) echo "ABORT: release policy has no preservation contract for dist-tag $DIST_TAG" >&2; exit 1 ;;
esac
DIST_TAGS="$DIST_TAGS" VERSION="$VERSION" DIST_TAG="$DIST_TAG" \
PRESERVED_TAG="$PRESERVED_TAG" PRESERVED="$PRESERVED" node - <<'NODE'
const tags = JSON.parse(process.env.DIST_TAGS);
const version = process.env.VERSION;
const distTag = process.env.DIST_TAG;
const preservedTag = process.env.PRESERVED_TAG;
const preserved = process.env.PRESERVED;
const seen = (name) => tags[name] ?? "";
const shown = (name) => seen(name) || "(absent)";
if (seen(distTag) !== version) {
  throw new Error(`dist-tag ${distTag}=${shown(distTag)}, expected ${version}`);
}
if (seen(preservedTag) !== preserved) {
  throw new Error(`dist-tag ${preservedTag}=${shown(preservedTag)}, expected preserved ${preserved || "(absent)"}`);
}
console.log(`registry ${distTag} publication: ${distTag}=${version} ${preservedTag}=${shown(preservedTag)}`);
NODE
```

## U3. Prove the registry-installed package

Sandbox HOME and every writable XDG root. Prove the package came from the
registry, not the checkout or preserved tarball.

```bash
TMP_ROOT=$(mktemp -d -t entwurf-registry-smoke.XXXXXX)
mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/data" "$TMP_ROOT/state" "$TMP_ROOT/cache" "$TMP_ROOT/agent"
HOME="$TMP_ROOT/home" \
XDG_DATA_HOME="$TMP_ROOT/data" \
XDG_STATE_HOME="$TMP_ROOT/state" \
XDG_CACHE_HOME="$TMP_ROOT/cache" \
PI_CODING_AGENT_DIR="$TMP_ROOT/agent" \
  pi install "npm:@junghanacs/entwurf@${VERSION}"
printf '%s\n' "{ \"packages\": [\"npm:@junghanacs/entwurf@${VERSION}\"] }" > "$TMP_ROOT/agent/settings.json"
BRIDGE=$(HOME="$TMP_ROOT/home" XDG_DATA_HOME="$TMP_ROOT/data" XDG_STATE_HOME="$TMP_ROOT/state" XDG_CACHE_HOME="$TMP_ROOT/cache" PI_CODING_AGENT_DIR="$TMP_ROOT/agent" node --experimental-strip-types scripts/resolve-acp-bridge.ts)
test "$BRIDGE" = "$TMP_ROOT/agent/npm/node_modules/@junghanacs/entwurf"
HOME="$TMP_ROOT/home" \
XDG_DATA_HOME="$TMP_ROOT/data" \
XDG_STATE_HOME="$TMP_ROOT/state" \
XDG_CACHE_HOME="$TMP_ROOT/cache" \
PI_CODING_AGENT_DIR="$TMP_ROOT/agent" \
  pi --no-extensions -e "$BRIDGE" --list-models entwurf
rm -rf "$TMP_ROOT"
```

The output must include `entwurf` and the curated Claude anchors, with no
`Unknown provider` or `No models matching` error. A failed registry smoke is a
stop-and-classify event; do not notify downstream consumers.

For the current #51 contract, the final Linux recovery proof remains:

1. Install the approved package on the maintainer and target host.
2. Run installed `entwurf install-meta-bridge`.
3. Restart every already-open Claude Code session.
4. Open a new session with its live MCP child.
5. Require installed `entwurf doctor-meta-bridge` to pass.

## Recovery table

| State | Recovery |
|---|---|
| Pre-version main push succeeded; CI failed | Fix in a new commit; rerun `land` for the new SHA. |
| Prepared main push succeeded; CI failed | Fix in a new commit; do not tag or create a candidate. |
| Exact candidate acceptance failed | Preserve candidate and log; diagnose; do not repack around the failure. |
| Local tag exists; tag push failed | Fix the cause and retry the tag push. |
| Tag is pushed; GitHub release is absent | Resume at M5/M6; do not move the tag. |
| GitHub release exists; notification failed | Resume at M7 only. |
| Wrong local tag; not pushed | Delete the local tag and rerun preflight. |
| Wrong pushed tag | Do not force; report to GLG. |
| npm publish succeeded; registry smoke failed | Stop and classify; do not notify downstream consumers. |
