#!/usr/bin/env bash
# Decide whether a push needs the qualification BODY (#103 piece 2).
#
# The body re-proves every committed mutant's kill-power and costs ~28 minutes.
# Across 549 CI runs it produced five reds, and replaying the real push ranges
# shows this filter would have run the body for all five (#99 stage-2 §1). So a
# push that cannot have touched the qualification surface skips it -- and the
# surface is READ FROM THE MANIFESTS, never copied into a list that can drift.
#
# TWO ENTRYPOINTS, ONE MATCHER:
#   ci-qualify-decide.sh <before-sha> <head-sha>   # CI and replay: a git range
#   ci-qualify-decide.sh --files-from <file|->     # a literal changed-file list
# Both print `run_body=true|false` on stdout and their reasoning on stderr.
#
# Pure local git plus python3 for the manifest read: no gh, no network, so the
# replay fixture gate runs offline and exercises this exact code.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Fail-open is numbered so a log line says WHICH one fired. Every one of these
# means "we cannot compute an honest diff", and the honest answer to that is to
# run the body, never to skip it.
fail_open() {
	echo "ci-qualify-decide: fail-open $1 ($2) -> run_body=true" >&2
	echo "run_body=true"
	exit 0
}

collect_paths_from_manifests() {
	python3 - "$REPO_DIR" <<'PY'
import glob
import json
import os
import sys

repo = sys.argv[1]
out = set()
for path in sorted(glob.glob(os.path.join(repo, "scripts/mutants/*.json"))):
	with open(path, encoding="utf-8") as handle:
		manifest = json.load(handle)
	for mutant in manifest.get("mutants", []):
		subject = mutant.get("subject")
		if subject:
			out.add(subject)
		signature_source = mutant.get("signatureSource")
		if signature_source:
			out.add(signature_source)
for entry in sorted(out):
	print(entry)
PY
}

# A changed path matters when it is a mutant's subject or signature source, or
# when it sits in the machinery that decides what those mutants prove.
matches_qualification_surface() {
	local file="$1"
	local subject
	while IFS= read -r subject; do
		[ "$file" = "$subject" ] && { echo "manifest-subject"; return 0; }
	done <<< "$MANIFEST_PATHS"
	case "$file" in
		scripts/mutants/*) echo "glob:scripts/mutants/**"; return 0 ;;
		scripts/check-*) echo "glob:scripts/check-*"; return 0 ;;
		scripts/lib/*) echo "glob:scripts/lib/**"; return 0 ;;
		.github/workflows/*) echo "glob:.github/workflows/**"; return 0 ;;
		run.sh) echo "exact:run.sh"; return 0 ;;
		package.json) echo "exact:package.json"; return 0 ;;
		# The decider itself: change the filter and the body runs, so a filter
		# that stopped covering something cannot hide behind its own change.
		scripts/ci-qualify-decide.sh) echo "exact:scripts/ci-qualify-decide.sh"; return 0 ;;
	esac
	return 1
}

decide_from_files() {
	local files="$1"
	local count=0
	local hits=0
	local file rule
	while IFS= read -r file; do
		[ -n "$file" ] || continue
		count=$((count + 1))
		if rule="$(matches_qualification_surface "$file")"; then
			hits=$((hits + 1))
			[ "$hits" -le 5 ] && echo "ci-qualify-decide: hit $file ($rule)" >&2
		fi
	done <<< "$files"
	if [ "$hits" -gt 0 ]; then
		echo "ci-qualify-decide: $hits of $count changed files touch the qualification surface -> run_body=true" >&2
		echo "run_body=true"
	else
		echo "ci-qualify-decide: no qualification-surface path among $count changed files -> run_body=false" >&2
		echo "run_body=false"
	fi
}

MANIFEST_PATHS="$(collect_paths_from_manifests)"
[ -n "$MANIFEST_PATHS" ] || { echo "ABORT: no mutant manifests read from $REPO_DIR/scripts/mutants" >&2; exit 1; }

if [ "${1:-}" = "--files-from" ]; then
	SRC="${2:-}"
	[ -n "$SRC" ] || { echo "ABORT: --files-from needs a path or -" >&2; exit 1; }
	if [ "$SRC" = "-" ]; then FILES="$(cat)"; else FILES="$(cat "$SRC")"; fi
	decide_from_files "$FILES"
	exit 0
fi

BEFORE="${1:-}"
HEAD_SHA="${2:-}"
EVENT="${CI_EVENT_NAME:-push}"
FORCED="${CI_FORCED:-false}"

# 3. A human or the schedule asked for this run; there is no push range to read.
#    `qualify` is what makes the dispatch an explicit request for the BODY. A
#    dispatch WITHOUT it is a floor-only rerun, so it must not silently satisfy
#    the release oracle's fourth axis -- the input would be dead configuration if
#    every dispatch ran the body regardless of its value.
case "$EVENT" in
	workflow_dispatch)
		[ "${CI_QUALIFY:-false}" = "true" ] && fail_open 3 "event=workflow_dispatch with qualify=true asked for the body"
		echo "ci-qualify-decide: dispatch without qualify=true is a floor-only rerun; the release oracle will still refuse this SHA until the body runs -> run_body=false" >&2
		echo "run_body=false"
		exit 0
		;;
	schedule) fail_open 3 "event=schedule runs the body unconditionally (drift ceiling)" ;;
	# 5. A pull_request event carries no `before`, and GitHub compares it
	#    three-dot. Narrowing PRs would need a second comparison rule for an
	#    event this repo barely uses, so PRs always run the body.
	pull_request) fail_open 5 "event=pull_request has no two-dot push range" ;;
esac

[ -n "$BEFORE" ] && [ -n "$HEAD_SHA" ] || { echo "ABORT: usage: $0 <before-sha> <head-sha>" >&2; exit 1; }

# 1. A new branch's first push: GitHub sends all-zeros, and its own documented
#    base ("the parent of the ancestor of the deepest commit pushed") is not
#    what a two-dot diff from zeros would give.
case "$BEFORE" in
	*[!0]*) ;;
	*) fail_open 1 "before=$BEFORE is the all-zero SHA (new branch)" ;;
esac

# 2. Force push. What `before` even means here is UNDOCUMENTED (#99 stage-2,
#    "measured not"): if it is the old head, the two-dot diff runs backwards and
#    the verdict can invert. Never guess -- run the body.
[ "$FORCED" = "true" ] && fail_open 2 "the push was forced; its two-dot base is undocumented"

# 4. The range is unreadable on this checkout -- a shallow clone, or an object
#    the remote no longer has (which is also how a force push's old base
#    disappears, so 2 and 4 can both be true and each still names itself).
git -C "$REPO_DIR" cat-file -e "$BEFORE^{commit}" 2>/dev/null || fail_open 4 "before=$BEFORE is not a commit object in this checkout"
git -C "$REPO_DIR" cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null || fail_open 4 "head=$HEAD_SHA is not a commit object in this checkout"

CHANGED="$(git -C "$REPO_DIR" diff --name-only "$BEFORE".."$HEAD_SHA" 2>/dev/null)" || fail_open 4 "git diff $BEFORE..$HEAD_SHA failed"

decide_from_files "$CHANGED"
