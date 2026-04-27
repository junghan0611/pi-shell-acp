---
description: Cut a release of pi-shell-acp (orchestration; mechanics in scripts/release.sh)
---

Make a release of this repository.

Version or release type: "$ARGUMENTS"

## Step-by-Step Process

### 1. Determine the target version

`$ARGUMENTS` can be either:
- An explicit version number (e.g., `0.2.1`) — **recommended** since aborted releases can be retried without bumping the counter.
- A release type: `patch`, `minor`, or `major` — bumped from the current version in `package.json`.

If `$ARGUMENTS` is an explicit version: use it as `$NEW_VERSION`.

If `$ARGUMENTS` is a release type:

```bash
CURRENT_VERSION=$(node -p "require('./package.json').version")
NEW_VERSION=$(npm version $ARGUMENTS --no-git-tag-version | sed 's/^v//')
git checkout package.json pnpm-lock.yaml  # revert
echo "Will release version: $NEW_VERSION"
```

If no argument is provided, ask the user.

### 2. Refresh the changelog

Use the `update-changelog` skill (it auto-loads from agent-config) to draft new entries into `## Unreleased` based on `git log v<last-tag>..HEAD`.

### 3. Verify the version number

Double-check `$NEW_VERSION` before proceeding.

### 4. Promote the Unreleased section

Edit `CHANGELOG.md`:
- Rename `## Unreleased` to `## $NEW_VERSION — YYYY-MM-DD`
- Add a fresh empty `## Unreleased` section at the top

### 5. Run the release script

```bash
./scripts/release.sh $NEW_VERSION
```

Pass the explicit version (e.g. `0.2.1`), NOT the release type.

The script will:
- Verify the working tree is clean.
- Verify `CHANGELOG.md` has a `## $NEW_VERSION` section.
- Run `pnpm check` (lint + typecheck + check-mcp/models/backends/registration/dep-versions).
- Bump `package.json` and `pnpm-lock.yaml` if needed.
- Create a `Release v$NEW_VERSION` commit and a `v$NEW_VERSION` tag.

### 6. Push and create the GitHub release

The script does NOT push. Show the user:

```bash
git push origin main && git push origin v$NEW_VERSION
gh release create v$NEW_VERSION --notes-from-tag --title v$NEW_VERSION
```

**Important:** Do not auto-push. Let the user review the commit and tag first.

## Notes

- The `commit` skill governs everyday commits; this command only governs the special `Release vX.Y.Z` commit.
- The release script intentionally rejects dirty working trees and missing CHANGELOG sections — fix the underlying issue rather than bypassing.
