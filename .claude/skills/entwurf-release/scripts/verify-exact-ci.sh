#!/usr/bin/env bash
set -euo pipefail

SHA="${1:-}"
MODE="${2:-wait}"

case "$SHA" in
  ''|*[!0-9a-f]*) echo "ABORT: first argument must be a full hexadecimal commit SHA" >&2; exit 1 ;;
esac
[ "${#SHA}" -eq 40 ] || { echo "ABORT: commit SHA must be the full 40-character SHA" >&2; exit 1; }
case "$MODE" in
  wait|verify) ;;
  *) echo "ABORT: mode must be wait or verify" >&2; exit 1 ;;
esac

command -v gh >/dev/null 2>&1 || { echo "ABORT: gh is not on PATH" >&2; exit 1; }
gh auth status >/dev/null
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
[ -n "$REPO" ] || { echo "ABORT: cannot resolve the GitHub repository" >&2; exit 1; }

# Two event kinds may carry the evidence for one SHA: the ordinary branch push,
# and a workflow_dispatch the release path fires when the qualification BODY did
# not run at that SHA. The event filter stays in the jq (not `gh run list
# --event`, which takes one value): without it a pull_request run for the same
# --commit would be admitted, and a PR run is a merge preview, not this SHA.
find_run() {
  gh run list \
    --repo "$REPO" \
    --workflow ci.yml \
    --commit "$SHA" \
    --limit 10 \
    --json databaseId,headSha,createdAt,event \
    --jq "map(select(.headSha == \"$SHA\" and (.event == \"push\" or .event == \"workflow_dispatch\"))) | sort_by(.createdAt) | reverse | .[0].databaseId // empty"
}

RUN_ID="$(find_run)"
if [ "$MODE" = wait ]; then
  for _ in $(seq 1 60); do
    [ -n "$RUN_ID" ] && break
    sleep 5
    RUN_ID="$(find_run)"
  done
fi
[ -n "$RUN_ID" ] || {
  echo "ABORT: no push- or dispatch-triggered ci.yml run exists for exact SHA $SHA" >&2
  exit 1
}

if [ "$MODE" = wait ]; then
  gh run watch "$RUN_ID" --repo "$REPO" --exit-status
fi

# The newest run at the SHA is the one judged, deliberately: the rule is
# deterministic and an operator who re-ran CI meant the newer run. In verify mode
# a still-running newest run therefore ABORTs on status != completed, which is the
# correct answer -- "not finished" is not evidence.
# `jobs` already carries each job's steps[], so the qualification-step axis below
# costs no extra API call.
RUN_JSON="$(gh run view "$RUN_ID" --repo "$REPO" --json databaseId,headSha,status,conclusion,url,event,jobs)"
RUN_JSON="$RUN_JSON" EXPECTED_SHA="$SHA" python3 - <<'PY'
import json
import os
import sys

run = json.loads(os.environ["RUN_JSON"])
expected_sha = os.environ["EXPECTED_SHA"]
required = ("check", "install-surface", "artifact-consumer")
# The qualification BODY axis. GitHub names an unnamed step "Run <command>", so
# this literal is bound to ci.yml's `- run: ./run.sh check-gate-qualification`
# line -- the one cell 8a already pins to exactly one occurrence.
QUAL_JOB = "check"
QUAL_STEP = "Run ./run.sh check-gate-qualification"
errors = []

# headSha is checked unconditionally, for both event kinds. That check only
# starts carrying load once dispatch runs are admitted: `gh workflow run --ref`
# takes a branch or tag, never a SHA, so a branch that moved between the dispatch
# and this read would otherwise pass silently.
if run.get("headSha") != expected_sha:
    errors.append(f"headSha={run.get('headSha')!r}, expected {expected_sha!r}")
if run.get("status") != "completed":
    errors.append(f"workflow status={run.get('status')!r}, expected 'completed'")
if run.get("conclusion") != "success":
    errors.append(f"workflow conclusion={run.get('conclusion')!r}, expected 'success'")

jobs = {job.get("name"): job for job in run.get("jobs", [])}
for name in required:
    conclusion = (jobs.get(name) or {}).get("conclusion")
    if conclusion != "success":
        errors.append(f"job {name!r} conclusion={conclusion!r}, expected 'success'")

steps = {step.get("name"): step.get("conclusion") for step in (jobs.get(QUAL_JOB) or {}).get("steps", [])}
if QUAL_STEP not in steps:
    errors.append(
        f"job {QUAL_JOB!r} has no step named {QUAL_STEP!r} -- the qualification BODY did not run at this SHA. "
        "GitHub renders an unnamed `- run: <command>` step as 'Run <command>', so giving that step a `name:` "
        "in ci.yml also lands here; keep it unnamed, or update this literal with it."
    )
elif steps[QUAL_STEP] == "skipped":
    errors.append(
        f"step {QUAL_STEP!r} conclusion='skipped' -- a skipped body is NOT evidence. Force it with "
        "`gh workflow run ci.yml --ref <branch> -f qualify=true`, then re-run this oracle."
    )
elif steps[QUAL_STEP] != "success":
    errors.append(f"step {QUAL_STEP!r} conclusion={steps[QUAL_STEP]!r}, expected 'success'")

if errors:
    print("ABORT: exact-SHA CI contract failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    print(f"  run={run.get('url')} event={run.get('event')!r}", file=sys.stderr)
    sys.exit(1)

print(f"exact-ci: PASS sha={expected_sha} run={run.get('databaseId')} event={run.get('event')} url={run.get('url')}")
for name in required:
    print(f"exact-ci: job {name}=success")
print(f"exact-ci: step {QUAL_JOB}/{QUAL_STEP}=success")
PY
