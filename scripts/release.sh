#!/usr/bin/env bash
# Mechanics for cutting a release. Orchestration lives in
# .pi/prompts/make-release.md (and the update-changelog skill).
#
# Usage: ./scripts/release.sh <version>   e.g. ./scripts/release.sh 0.2.1
#
# Always pass an explicit version (NOT patch/minor/major) — that lets
# aborted releases be retried without bumping the counter.

set -euo pipefail

NEW_VERSION="${1:-}"
if [ -z "$NEW_VERSION" ]; then
  echo "usage: $0 <version>  (e.g. 0.2.1 — no leading 'v')" >&2
  exit 1
fi
TAG="v${NEW_VERSION}"

# 1. Clean working tree
if ! git diff-index --quiet HEAD --; then
  echo "❌ working tree is dirty — commit or stash first" >&2
  exit 1
fi

# 2. CHANGELOG must have a section for this version
if ! grep -q "^## ${NEW_VERSION}\b" CHANGELOG.md; then
  echo "❌ CHANGELOG.md has no '## ${NEW_VERSION}' section" >&2
  echo "   (run /update-changelog and rename '## Unreleased' to '## ${NEW_VERSION}' first)" >&2
  exit 1
fi

# 3. Quality gate
echo "▶ pnpm check"
pnpm check

# 4. package.json + lockfile
CURRENT_VERSION=$(node -p "require('./package.json').version")
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
  npm version "$NEW_VERSION" --no-git-tag-version
  pnpm install --lockfile-only
else
  echo "  package.json already at $NEW_VERSION — skipping bump"
fi

# 5. Commit + tag
git add package.json pnpm-lock.yaml CHANGELOG.md
git commit -m "Release ${TAG}"
git tag "$TAG"

echo
echo "✅ committed and tagged ${TAG}"
echo "   review with: git show ${TAG}"
echo "   push with:   git push origin main && git push origin ${TAG}"
echo
echo "   then create the GitHub release with:"
echo "     gh release create ${TAG} --notes-from-tag --title ${TAG}"
echo
echo "   (or pull the section out of CHANGELOG.md manually if you want richer notes)"
