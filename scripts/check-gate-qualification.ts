/**
 * check-gate-qualification — kill-proof qualification of the shipped gates.
 *
 * TWO ENTRYPOINTS, ONE FILE. `--manifests-only` (shipped as `run.sh
 * check-gate-manifests`) stops after the HEAD — the runner self-test plus the real
 * manifests' validation and lane inventory — having executed ZERO mutants from
 * `scripts/mutants/` and having made NO snapshot of this repo. The default
 * entrypoint is unchanged: it runs the same head first and then the body. The head
 * is separable because of what it has actually caught: across 549 CI runs the
 * qualification step went red five times, and three of those died in the head in
 * 4-5 seconds, before a single mutant gate was invoked (#99 B-3). The head costs
 * ~8s, so it belongs in the deterministic floor every push already pays for; the
 * body's contract — which mutants run, how they are classified, what it prints —
 * is untouched by the split.
 *
 * Two phases, in a fixed order:
 *
 *   1. RUNNER SELF-TEST. The runner is itself a SUT: a qualification harness that
 *      rounds a wrong-reason red up to KILLED, or misses a zero-match, is a test bug
 *      of exactly the class it exists to close. So before any real manifest runs,
 *      the pure classifier is exhausted as a truth table and the whole pipeline is
 *      driven over a synthetic fixture repo through every negative: malformed
 *      manifest, duplicate claim, path escape, untracked subject, zero-match,
 *      multi-match, SURVIVED, WRONG-REASON, HANG (with a real grandchild kill on
 *      the process group), CONTROL-PRE red (the fake-KILLED hole), a state-poisoning
 *      gate (CONTROL-POST red), and a stray write (tree-manifest impurity).
 *
 *   2. REAL MANIFESTS. `scripts/mutants/*.json` are validated (exact schema, global
 *      claim uniqueness, subject tracked in the ORIGIN index, claim token exactly
 *      once in its gate source), then run in an isolated snapshot repo under the
 *      control-mutant-restore-control state machine. The real checkout is never
 *      written; its HEAD + work-surface content hash are asserted identical
 *      before/after (P1-5 — porcelain text alone misses byte changes in already-
 *      modified files).
 *
 * No tiers: the committed mutant set is one tier — every run executes every mutant,
 * one command, one truth, no advisory lane. Runtime is recorded when this runs on a
 * frozen candidate; if the set ever outgrows its budget, re-open the fast/full split
 * from the design record instead of silently skipping mutants.
 *
 * Evidence: claim IDs + killed mutant IDs, never assertion counts.
 */

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import {
	classifyMutantRun,
	createRepoSnapshot,
	ManifestError,
	type MutantManifest,
	type MutantSpec,
	makeOriginChecks,
	originHead,
	originWorkSurfaceSha,
	qualifyMutants,
	readVitestFailedTitles,
	reportPassed,
	runGateBounded,
	signatureAttributedToFailure,
	signatureOnFailureLine,
	sweepStaleSnapshots,
	validateManifest,
	validateManifestSet,
} from "./lib/mutation-qualify.ts";

const REPO_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MUTANTS_DIR = path.join(REPO_DIR, "scripts", "mutants");

/** Head-only mode: validate, count, and stop — no mutant is executed, no repo snapshot is made. */
const MANIFESTS_ONLY = process.argv.includes("--manifests-only");
const SURFACE = MANIFESTS_ONLY ? "check-gate-manifests" : "gate-qualification";

let passed = 0;
function ok(label: string, cond: boolean): void {
	assert.ok(cond, label);
	console.log(`  ok    ${label}`);
	passed++;
}

function throws(label: string, fn: () => void, naming: string): void {
	try {
		fn();
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		assert.ok(msg.includes(naming), `${label} — error should name \`${naming}\`, got: ${msg}`);
		console.log(`  ok    ${label}`);
		passed++;
		return;
	}
	assert.fail(`${label} — expected a loud refusal, got silence`);
}

/**
 * Vitest attribution, proved on the MEASURED false-positive shape (issue #62 review).
 *
 * Vitest prints a code frame around the failing assertion, and that frame quotes the
 * neighbouring source lines — including an adjacent PASSING test's `it("[QK:…]" …)`
 * title. Measured verbatim on vitest 4.1.9:
 *
 *     ×  [QK:B] fails on its first body line
 *     4|  it("[QK:A] one-liner that passes", () => expect(1).toBe(1));
 *     5|  it("[QK:B] fails on its first body line", () => {
 *
 * The legacy `ok`-line oracle answers TRUE for [QK:A] there — a mutant claiming A
 * would be certified KILLED by a red that belongs to B. The structured oracle reads
 * only the failed-test title set, so it must answer FALSE for A and TRUE for B.
 *
 * The cell is discriminating in BOTH directions: it asserts that the legacy scanner
 * really does say TRUE on this input, so the negative is not vacuous.
 */
function checkVitestAttribution(): void {
	// Declared ONCE as a literal: the manifest's exact-once signature rule counts
	// occurrences of this token in signatureSource, so every other use goes through
	// the binding.
	const claimed = "[QK:VITEST-FAILED-TITLE-ATTRIBUTION]";
	const actualFailure = "[QK:ADJACENT-ACTUAL-FAILURE]";
	const codeFrame = [
		"__ENTWURF_VITEST_JSON__",
		` ×  ${actualFailure} fails on its first body line`,
		`      4|  it("${claimed} one-liner that passes", () => expect(1).toBe(1));`,
		`      5|  it("${actualFailure} fails on its first body line", () => {`,
	].join("\n");
	const report = JSON.stringify({
		testResults: [
			{
				assertionResults: [
					{ status: "passed", fullName: `frame probe ${claimed} one-liner that passes` },
					{ status: "failed", fullName: `frame probe ${actualFailure} fails on its first body line` },
				],
			},
		],
	});

	const dir = fs.mkdtempSync(path.join(os.tmpdir(), "entwurf-attribution-selftest-"));
	const reportPath = path.join(dir, "vitest-report.json");
	try {
		fs.writeFileSync(reportPath, report);
		const titles = readVitestFailedTitles(codeFrame, reportPath);

		ok(
			"attribution self-test is not vacuous — the legacy failure-line oracle really does certify the adjacent PASSING claim on this measured code frame",
			signatureOnFailureLine(codeFrame, claimed),
		);
		ok(
			`${claimed} Vitest attribution reads only structured failed-test titles — an adjacent passing QK quoted by the failing code frame cannot certify the mutant`,
			!signatureAttributedToFailure(codeFrame, claimed, titles) &&
				signatureAttributedToFailure(codeFrame, actualFailure, titles),
		);
		ok(
			"a structured lane whose report is missing is UNREADABLE, never a silent fallback to token scanning",
			readVitestFailedTitles(codeFrame, path.join(dir, "absent.json")) === "unreadable" &&
				!signatureAttributedToFailure(codeFrame, actualFailure, "unreadable"),
		);
		ok(
			"a gate that printed no marker keeps the legacy failure-line oracle unchanged",
			readVitestFailedTitles("  not ok 1 boom [QK:LEGACY]", reportPath) === "legacy" &&
				signatureAttributedToFailure("  not ok 1 boom [QK:LEGACY]", "[QK:LEGACY]", "legacy"),
		);
	} finally {
		fs.rmSync(dir, { recursive: true, force: true });
	}
}

checkVitestAttribution();
if (process.argv.includes("--attribution-self-test")) {
	console.log(`[gate-qualification] attribution self-test: ${passed} checks passed`);
	process.exit(0);
}

// ═══ Phase 1a — the pure classifier, exhausted as a truth table ═════════════

{
	const base: import("./lib/mutation-qualify.ts").MutantRunFacts = {
		controlPreOk: true,
		matchCount: 1,
		timedOut: false,
		exitCode: 1,
		signatureOnFailureLine: true,
		restoredOk: true,
	};
	const rows: [string, Partial<typeof base>, string][] = [
		["nonzero + signature on a failure line", {}, "KILLED"],
		["control-pre red outranks everything", { controlPreOk: false, exitCode: 0 }, "CONTROL-RED"],
		["zero-match is stale production drift, never a kill", { matchCount: 0 }, "MUTANT-STALE"],
		["multi-match refuses before writing", { matchCount: 2 }, "MULTI-MATCH"],
		["failed restore outranks the run outcome (a dirty kill is not a kill)", { restoredOk: false }, "IMPURE"],
		["timeout is HANG, its own class", { timedOut: true, exitCode: null }, "HANG"],
		["exit 0 with the defect planted is SURVIVED", { exitCode: 0, signatureOnFailureLine: false }, "SURVIVED"],
		[
			"nonzero WITHOUT the claimed signature is WRONG-REASON, never rounded up",
			{ signatureOnFailureLine: false },
			"WRONG-REASON",
		],
		[
			"a SIGNAL CRASH (exit null outside our timeout) is WRONG-REASON even with the token present — not a bounded kill",
			{ exitCode: null },
			"WRONG-REASON",
		],
	];
	for (const [why, patch, want] of rows) {
		ok(`classifier: ${why} → ${want}`, classifyMutantRun({ ...base, ...patch }) === want);
	}
	ok(
		"signature: a token on an `ok` line does NOT count (a later-assertion red must not self-certify)",
		signatureOnFailureLine("  ok    something [QK:X] fine\nFAIL: other reason", "[QK:X]") === false,
	);
	ok(
		"signature: a token on a FAIL line counts",
		signatureOnFailureLine("  ok    unrelated\nFAIL: broken [QK:X] here", "[QK:X]") === true,
	);
	ok(
		"signature: an assertion-error line counts (TS gates print the label via AssertionError)",
		signatureOnFailureLine("AssertionError [ERR_ASSERTION]: label [QK:X]", "[QK:X]") === true,
	);

	// Exhaustive truth table (#57 runner qualification): EVERY fact combination — 2
	// control × 3 match classes × 2 timeout × 3 exit classes × 2 signature × 2 restore
	// = 144 rows. The named rows above document each verdict; this loop closes the rest
	// of the space. Two independent assertions per row: the precedence oracle (restated
	// here as full per-verdict conditions), and — standalone, because it is the verdict
	// the whole gate exists to guard — KILLED iff its full 7-way conjunction, so no
	// dropped guard or reordering can round any other row up to a kill.
	{
		let rows = 0;
		for (const controlPreOk of [true, false]) {
			for (const matchCount of [0, 1, 2]) {
				for (const timedOut of [false, true]) {
					for (const exitCode of [null, 0, 1]) {
						for (const sig of [true, false]) {
							for (const restoredOk of [true, false]) {
								const facts = {
									controlPreOk,
									matchCount,
									timedOut,
									exitCode,
									signatureOnFailureLine: sig,
									restoredOk,
								};
								const got = classifyMutantRun(facts);
								const killedIff =
									controlPreOk &&
									matchCount === 1 &&
									restoredOk &&
									!timedOut &&
									exitCode !== null &&
									exitCode !== 0 &&
									sig;
								assert.equal(
									got === "KILLED",
									killedIff,
									`classifier truth table: KILLED must hold iff its full conjunction — row ${JSON.stringify(facts)} → ${got}`,
								);
								const expected = !controlPreOk
									? "CONTROL-RED"
									: matchCount === 0
										? "MUTANT-STALE"
										: matchCount > 1
											? "MULTI-MATCH"
											: !restoredOk
												? "IMPURE"
												: timedOut
													? "HANG"
													: exitCode === null
														? "WRONG-REASON"
														: exitCode === 0
															? "SURVIVED"
															: sig
																? "KILLED"
																: "WRONG-REASON";
								assert.equal(
									got,
									expected,
									`classifier truth table: row ${JSON.stringify(facts)} → ${got}, oracle says ${expected}`,
								);
								rows++;
							}
						}
					}
				}
			}
		}
		ok(
			"classifier: exhaustive truth table — all 144 fact rows match the oracle, KILLED iff its conjunction",
			rows === 144,
		);
	}
}

// ═══ Phase 1b — manifest validation negatives (before any snapshot work) ════

{
	const good = {
		schemaVersion: 1,
		lane: "test",
		mutants: [
			{
				claim: "SELFTEST-KILL",
				title: "t",
				subject: "subject.txt",
				find: ["original-line"],
				replace: ["defect-line"],
				gate: ["bash", "gates/kill.sh"],
				timeoutSeconds: 10,
				signature: "[QK:SELFTEST-KILL]",
				signatureSource: "gates/kill.sh",
			},
		],
	};
	ok("manifest: a well-formed manifest validates", validateManifest(good, "good").mutants.length === 1);
	throws(
		"manifest: an unknown key is refused loudly",
		() => validateManifest({ ...good, extra: 1 }, "m"),
		"unknown key",
	);
	throws(
		"manifest: a missing field is refused loudly",
		() => validateManifest({ schemaVersion: 1, lane: "x" }, "m"),
		"missing key",
	);
	throws(
		"manifest: a wrong schemaVersion is refused",
		() => validateManifest({ ...good, schemaVersion: 2 }, "m"),
		"schemaVersion",
	);
	const mutate = (patch: Record<string, unknown>): unknown => ({
		...good,
		mutants: [{ ...good.mutants[0], ...patch }],
	});
	throws(
		"manifest: an absolute subject path is refused",
		() => validateManifest(mutate({ subject: "/etc/passwd" }), "m"),
		"repo-relative",
	);
	throws(
		"manifest: a `..` subject escape is refused",
		() => validateManifest(mutate({ subject: "../outside.txt" }), "m"),
		"repo-relative",
	);
	throws(
		"manifest: a node_modules subject is refused (shared dependency symlink)",
		() => validateManifest(mutate({ subject: "node_modules/x.js" }), "m"),
		"node_modules",
	);
	throws(
		"manifest: replace identical to find is refused",
		() => validateManifest(mutate({ replace: ["original-line"] }), "m"),
		"differ",
	);
	throws(
		"manifest: a signature that is not [QK:<claim>] is refused",
		() => validateManifest(mutate({ signature: "[QK:OTHER]" }), "m"),
		"signature must be exactly",
	);
	throws(
		"manifest: a wrong-typed timeout is refused",
		() => validateManifest(mutate({ timeoutSeconds: "10" }), "m"),
		"timeoutSeconds",
	);
	throws(
		"manifest: an out-of-range timeout is refused",
		() => validateManifest(mutate({ timeoutSeconds: 0 }), "m"),
		"timeoutSeconds",
	);
	throws(
		"manifest: a shell-string gate is refused (argv array only)",
		() => validateManifest(mutate({ gate: "bash gates/kill.sh" }), "m"),
		"non-empty array",
	);

	const man = validateManifest(good, "a") as MutantManifest;
	const dupSet = [man, validateManifest({ ...good, lane: "other" }, "b")];
	const permissiveOrigin = {
		subjectTracked: () => true,
		regularContainedFile: () => true,
		onWorkSurface: () => true,
		tokenCount: () => 1,
	};
	throws(
		"manifest set: a duplicate claim across manifests is refused",
		() => validateManifestSet(dupSet, permissiveOrigin),
		"duplicate claim",
	);
	throws(
		"manifest set: a subject NOT tracked in the origin index is refused",
		() => validateManifestSet([man], { ...permissiveOrigin, subjectTracked: () => false }),
		"not tracked",
	);
	throws(
		"manifest set: a claim token absent from its gate source is refused",
		() => validateManifestSet([man], { ...permissiveOrigin, tokenCount: () => 0 }),
		"occurs 0",
	);
	throws(
		"manifest set: a claim token duplicated in its gate source is refused",
		() => validateManifestSet([man], { ...permissiveOrigin, tokenCount: () => 2 }),
		"occurs 2",
	);
	// P0-1: tracked is not enough — a tracked SYMLINK subject would let the snapshot's
	// read/write follow it OUT of the sandbox. Both paths must be lstat-regular.
	throws(
		"manifest set: a subject that is not a regular non-symlink file is refused (P0-1)",
		() => validateManifestSet([man], { ...permissiveOrigin, regularContainedFile: (f: string) => f !== "subject.txt" }),
		"symlink-escape guard",
	);
	throws(
		"manifest set: a signatureSource off the origin work surface is refused",
		() => validateManifestSet([man], { ...permissiveOrigin, onWorkSurface: () => false }),
		"not on the origin work surface",
	);
	throws(
		"manifest set: a symlink signatureSource is refused",
		() =>
			validateManifestSet([man], { ...permissiveOrigin, regularContainedFile: (f: string) => f !== "gates/kill.sh" }),
		"signatureSource gates/kill.sh is not a regular",
	);
}

// ═══ Phase 1c — the pipeline over a synthetic fixture repo ══════════════════

function buildFixtureOrigin(): { dir: string; externalTarget: string } {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), "entwurf-qualify-fixture-"));
	// A file OUTSIDE the fixture repo, reachable only through a tracked symlink — the
	// P0-1 escape shape: mutating `linked.txt` would write THIS file.
	const externalDir = fs.mkdtempSync(path.join(os.tmpdir(), "entwurf-qualify-external-"));
	const externalTarget = path.join(externalDir, "external-target.txt");
	fs.writeFileSync(externalTarget, "original-line outside the sandbox\n");
	const write = (rel: string, body: string, mode = 0o644): void => {
		const p = path.join(dir, rel);
		fs.mkdirSync(path.dirname(p), { recursive: true });
		fs.writeFileSync(p, body);
		fs.chmodSync(p, mode);
	};
	write("subject.txt", "alpha\noriginal-line\nomega\n");
	write("double.txt", "dup-line\ndup-line\n");
	// Each fixture gate reads the subject and goes red IFF the planted defect is present.
	write(
		"gates/kill.sh",
		'#!/usr/bin/env bash\nif grep -q defect-line subject.txt; then echo "FAIL: planted defect detected [QK:SELFTEST-KILL]" >&2; exit 1; fi\nexit 0\n',
		0o755,
	);
	write("gates/survive.sh", "#!/usr/bin/env bash\nexit 0\n", 0o755);
	write(
		"gates/wrong.sh",
		'#!/usr/bin/env bash\nif grep -q defect-line subject.txt; then echo "FAIL: some other assertion tripped [QK:SELFTEST-OTHER]" >&2; exit 1; fi\nexit 0\n',
		0o755,
	);
	write(
		"gates/hang.sh",
		'#!/usr/bin/env bash\nif grep -q defect-line subject.txt; then sleep 300 & echo $! > "$HOME/grandchild.pid"; sleep 300; fi\nexit 0\n',
		0o755,
	);
	write("gates/red.sh", '#!/usr/bin/env bash\necho "FAIL: baseline is red [QK:SELFTEST-PRERED]" >&2\nexit 1\n', 0o755);
	write(
		"gates/stray.sh",
		'#!/usr/bin/env bash\nif grep -q defect-line subject.txt; then echo stray > stray-file.txt; echo "FAIL: planted defect detected [QK:SELFTEST-STRAY]" >&2; exit 1; fi\nexit 0\n',
		0o755,
	);
	write(
		"gates/poison.sh",
		'#!/usr/bin/env bash\nif [ -f poison.marker ]; then echo "FAIL: poisoned state [QK:SELFTEST-POISON]" >&2; exit 1; fi\nif grep -q defect-line subject.txt; then touch poison.marker; echo "FAIL: planted defect detected [QK:SELFTEST-POISON]" >&2; exit 1; fi\nexit 0\n',
		0o755,
	);
	// Red IFF the literal `$&` replacement text landed byte-for-byte: an interpreting
	// String.replace would write the matched line back instead, this grep would miss,
	// and the mutant would SURVIVE — so KILLED proves the replacement stayed literal.
	write(
		"gates/dollar.sh",
		"#!/usr/bin/env bash\nif grep -qF 'dollar-$&-defect' subject.txt; then echo \"FAIL: literal replacement landed [QK:SELFTEST-DOLLAR]\" >&2; exit 1; fi\nexit 0\n",
		0o755,
	);
	write("untracked.txt", "present on disk but never git-added\n");
	fs.symlinkSync(externalTarget, path.join(dir, "linked.txt"));
	const git = (...args: string[]): void => {
		const r = spawnSync("git", ["-C", dir, ...args], {
			stdio: "ignore",
			env: {
				...process.env,
				GIT_CONFIG_GLOBAL: "/dev/null",
				GIT_CONFIG_SYSTEM: "/dev/null",
				GIT_AUTHOR_NAME: "fx",
				GIT_AUTHOR_EMAIL: "fx@localhost",
				GIT_COMMITTER_NAME: "fx",
				GIT_COMMITTER_EMAIL: "fx@localhost",
			},
		});
		assert.equal(r.status, 0, `fixture git ${args.join(" ")} failed`);
	};
	git("init", "-q");
	git("add", "subject.txt", "double.txt", "gates", "linked.txt");
	git("-c", "commit.gpgsign=false", "commit", "-q", "-m", "fixture");
	return { dir, externalTarget };
}

function fixtureSpec(patch: Partial<MutantSpec>): MutantSpec {
	return {
		claim: "SELFTEST-KILL",
		title: "fixture",
		subject: "subject.txt",
		find: ["original-line"],
		replace: ["defect-line"],
		gate: ["bash", "gates/kill.sh"],
		timeoutSeconds: 30,
		signature: "[QK:SELFTEST-KILL]",
		signatureSource: "gates/kill.sh",
		...patch,
	};
}

const quiet = (): void => {};

{
	const { dir: fixtureOrigin, externalTarget } = buildFixtureOrigin();
	try {
		const checks = makeOriginChecks(fixtureOrigin);
		ok("origin checks: a tracked subject is recognized", checks.subjectTracked("subject.txt") === true);
		ok(
			"origin checks: a file present on disk but NOT in the index is refused (hardening #3)",
			checks.subjectTracked("untracked.txt") === false,
		);
		ok(
			"origin checks: token counting reads the origin bytes",
			checks.tokenCount("gates/kill.sh", "[QK:SELFTEST-KILL]") === 1,
		);
		// P0-1 against a REAL tracked symlink (not an injected fake): the lstat check
		// must refuse it even though `git ls-files --error-unmatch` calls it tracked.
		ok(
			"origin checks: a TRACKED SYMLINK is refused by the regular-file check (real lstat)",
			checks.subjectTracked("linked.txt") === true && checks.regularContainedFile("linked.txt") === false,
		);
		ok(
			"origin checks: a regular tracked file passes the regular-file check",
			checks.regularContainedFile("subject.txt") === true,
		);
		ok(
			"origin checks: the work surface includes untracked-non-ignored files (a new gate before its first commit)",
			checks.onWorkSurface("untracked.txt") === true && checks.onWorkSurface("absent-file.txt") === false,
		);
		throws(
			"manifest set: a REAL tracked-symlink subject is refused end-to-end (external escape shape)",
			() =>
				validateManifestSet(
					[{ schemaVersion: 1, lane: "escape", mutants: [fixtureSpec({ subject: "linked.txt" })] }],
					checks,
				),
			"symlink-escape guard",
		);

		const snap = createRepoSnapshot(fixtureOrigin);
		try {
			ok(
				"snapshot: replicates only the git surface (untracked.txt IS listed by --others, so it rides too)",
				fs.existsSync(path.join(snap.repoDir, "untracked.txt")),
			);
			ok("snapshot: base dir is mode 0700", (fs.statSync(snap.baseDir).mode & 0o777) === 0o700);
			ok(
				"snapshot: executable modes survive the copy",
				(fs.statSync(path.join(snap.repoDir, "gates/kill.sh")).mode & 0o111) !== 0,
			);
			ok(
				"snapshot: has its own git baseline (porcelain clean)",
				spawnSync("git", ["-C", snap.repoDir, "status", "--porcelain"], {
					encoding: "utf8",
					env: { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_SYSTEM: "/dev/null" },
				}).stdout.trim() === "",
			);

			// KILLED positive + zero-match + multi-match + SURVIVED + WRONG-REASON in one report.
			const report = await qualifyMutants(
				snap,
				[
					fixtureSpec({}),
					fixtureSpec({ claim: "SELFTEST-STALE", signature: "[QK:SELFTEST-STALE]", find: ["never-present-line"] }),
					fixtureSpec({
						claim: "SELFTEST-MULTI",
						signature: "[QK:SELFTEST-MULTI]",
						subject: "double.txt",
						find: ["dup-line"],
						replace: ["defect-line"],
					}),
					fixtureSpec({
						claim: "SELFTEST-SURVIVE",
						signature: "[QK:SELFTEST-SURVIVE]",
						gate: ["bash", "gates/survive.sh"],
					}),
					fixtureSpec({ claim: "SELFTEST-WRONG", signature: "[QK:SELFTEST-WRONG]", gate: ["bash", "gates/wrong.sh"] }),
					fixtureSpec({
						claim: "SELFTEST-DOLLAR",
						signature: "[QK:SELFTEST-DOLLAR]",
						replace: ["dollar-$&-defect"],
						gate: ["bash", "gates/dollar.sh"],
					}),
				],
				quiet,
			);
			const byClaim = new Map(report.groups.flatMap((g) => g.mutants).map((m) => [m.claim, m.verdict]));
			ok(
				"pipeline: a planted defect the gate catches with its own token → KILLED",
				byClaim.get("SELFTEST-KILL") === "KILLED",
			);
			ok(
				"pipeline: a find that no longer matches → MUTANT-STALE (red, never vacuous-killed)",
				byClaim.get("SELFTEST-STALE") === "MUTANT-STALE",
			);
			ok(
				"pipeline: a find matching twice → MULTI-MATCH (nothing written)",
				byClaim.get("SELFTEST-MULTI") === "MULTI-MATCH",
			);
			ok("pipeline: a gate green under the defect → SURVIVED", byClaim.get("SELFTEST-SURVIVE") === "SURVIVED");
			ok(
				"pipeline: a gate red at ANOTHER claim's token → WRONG-REASON, never rounded up to KILLED",
				byClaim.get("SELFTEST-WRONG") === "WRONG-REASON",
			);
			ok(
				"pipeline: the multi-match subject was never written",
				fs.readFileSync(path.join(snap.repoDir, "double.txt"), "utf8") === "dup-line\ndup-line\n",
			);
			ok(
				"pipeline: a replacement carrying `$&` lands LITERALLY (String.replace patterns are inert) → KILLED",
				byClaim.get("SELFTEST-DOLLAR") === "KILLED",
			);
			ok("pipeline: the snapshot tree stayed clean across restores", report.treeClean && report.porcelainClean);
			ok("pipeline: a report with non-KILLED verdicts does not pass", reportPassed(report) === false);

			// HANG: bounded, restore still happens, and the whole report stays honest.
			const hangReport = await qualifyMutants(
				snap,
				[
					fixtureSpec({
						claim: "SELFTEST-HANG",
						signature: "[QK:SELFTEST-HANG]",
						gate: ["bash", "gates/hang.sh"],
						timeoutSeconds: 2,
					}),
				],
				quiet,
			);
			const hang = hangReport.groups[0].mutants[0];
			ok("pipeline: a hanging gate is classified HANG within its bound", hang.verdict === "HANG" && hang.seconds < 30);
			ok(
				"pipeline: the subject is restored even when the gate hung (finally-path restore)",
				fs.readFileSync(path.join(snap.repoDir, "subject.txt"), "utf8") === "alpha\noriginal-line\nomega\n",
			);

			// CONTROL-PRE red: the fake-KILLED hole — a baseline-red gate must abort its group.
			const preRed = await qualifyMutants(
				snap,
				[fixtureSpec({ claim: "SELFTEST-PRERED", signature: "[QK:SELFTEST-PRERED]", gate: ["bash", "gates/red.sh"] })],
				quiet,
			);
			ok(
				"pipeline: a baseline-red gate → group pre-red, mutant CONTROL-RED (no fake KILLED)",
				preRed.groups[0].control === "pre-red" && preRed.groups[0].mutants[0].verdict === "CONTROL-RED",
			);
			ok("pipeline: a control-red report does not pass", reportPassed(preRed) === false);

			// Stray write: mutant kills, but the tree manifest catches the impurity.
			const stray = await qualifyMutants(
				snap,
				[fixtureSpec({ claim: "SELFTEST-STRAY", signature: "[QK:SELFTEST-STRAY]", gate: ["bash", "gates/stray.sh"] })],
				quiet,
			);
			ok(
				"pipeline: a gate that wrote a stray file into the tree → treeClean=false (porcelain-invisible writes included)",
				stray.treeClean === false,
			);
			ok(
				"pipeline: an impure-tree report does not pass even with a KILLED mutant",
				stray.groups[0].mutants[0].verdict === "KILLED" && reportPassed(stray) === false,
			);
			fs.rmSync(path.join(snap.repoDir, "stray-file.txt"), { force: true });

			// State poison: mutant kills but leaves state that turns CONTROL-POST red.
			const poison = await qualifyMutants(
				snap,
				[
					fixtureSpec({
						claim: "SELFTEST-POISON",
						signature: "[QK:SELFTEST-POISON]",
						gate: ["bash", "gates/poison.sh"],
					}),
				],
				quiet,
			);
			ok(
				"pipeline: state leaked by a mutant run turns CONTROL-POST red (group impure)",
				poison.groups[0].control === "post-red",
			);
			ok("pipeline: a post-red report does not pass", reportPassed(poison) === false);
			fs.rmSync(path.join(snap.repoDir, "poison.marker"), { force: true });

			// P0-1 RUNTIME guard: the self-test injects specs directly (bypassing
			// validateManifestSet), so the escape must ALSO be stopped at the moment of
			// mutation — refused before a byte is read, external target untouched.
			const externalBefore = fs.readFileSync(externalTarget, "utf8");
			await assert.rejects(
				qualifyMutants(
					snap,
					[
						fixtureSpec({
							claim: "SELFTEST-ESCAPE",
							signature: "[QK:SELFTEST-ESCAPE]",
							subject: "linked.txt",
							gate: ["bash", "gates/survive.sh"],
						}),
					],
					quiet,
				),
				/symlink-escape guard/,
				"a tracked-symlink subject must be refused at mutation time, loudly",
			);
			ok(
				"pipeline: the symlink-escape refusal left the EXTERNAL target byte-identical (no write followed the link)",
				fs.readFileSync(externalTarget, "utf8") === externalBefore,
			);
		} finally {
			fs.rmSync(snap.baseDir, { recursive: true, force: true });
		}

		// P1-5: the origin tripwire hashes the WORK SURFACE CONTENT, not `status
		// --porcelain` text — a porcelain-based tripwire cannot see a byte change inside
		// a file that was ALREADY modified (same ` M` row before and after). Prove the
		// discriminating power on exactly that shape: modify → hash moves; modify the
		// BYTES AGAIN (porcelain text identical) → hash moves again; restore → hash back.
		{
			const subjectPath = path.join(fixtureOrigin, "subject.txt");
			const pristine = fs.readFileSync(subjectPath);
			const h0 = originWorkSurfaceSha(fixtureOrigin);
			fs.writeFileSync(subjectPath, "alpha\nmodified-once\nomega\n");
			const h1 = originWorkSurfaceSha(fixtureOrigin);
			fs.writeFileSync(subjectPath, "alpha\nmodified-twice\nomega\n");
			const h2 = originWorkSurfaceSha(fixtureOrigin);
			fs.writeFileSync(subjectPath, pristine);
			const h3 = originWorkSurfaceSha(fixtureOrigin);
			ok("tripwire: a first modification moves the work-surface hash", h1 !== h0);
			ok(
				"tripwire: a byte change INSIDE an already-modified file moves the hash again (porcelain would not see it)",
				h2 !== h1,
			);
			ok("tripwire: restoring the bytes restores the hash (content-derived, not time-derived)", h3 === h0);
		}

		// pgroup kill: the grandchild really dies on this host (hardening #6, Linux axis).
		{
			const invocationDir = fs.mkdtempSync(path.join(os.tmpdir(), "entwurf-qualify-pgk-"));
			const pidFile = path.join(invocationDir, "grandchild.pid");
			const script = path.join(invocationDir, "spawner.sh");
			fs.writeFileSync(script, `#!/usr/bin/env bash\nsleep 300 & echo $! > ${JSON.stringify(pidFile)}\nwait\n`);
			fs.chmodSync(script, 0o755);
			const run = await runGateBounded({
				cwd: invocationDir,
				argv: ["bash", script],
				timeoutSeconds: 2,
				invocationDir,
			});
			ok("pgroup: the spawner timed out as expected", run.timedOut === true);
			const grandchild = Number(fs.readFileSync(pidFile, "utf8").trim());
			let dead = false;
			for (let i = 0; i < 20 && !dead; i++) {
				try {
					process.kill(grandchild, 0);
					await new Promise((r) => setTimeout(r, 50));
				} catch {
					dead = true;
				}
			}
			ok(`pgroup: the GRANDCHILD (pid ${grandchild}) is dead after the group SIGKILL`, dead);
			fs.rmSync(invocationDir, { recursive: true, force: true });
		}

		// Stale-snapshot sweep: dead-pid residue is reclaimed, a live runner's dir survives.
		{
			const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "entwurf-qualify-sweep-"));
			const deadDir = path.join(tmpRoot, "entwurf-qualify-dead1");
			fs.mkdirSync(deadDir);
			fs.writeFileSync(path.join(deadDir, "runner.json"), JSON.stringify({ pid: 999_999_999, startedAt: 0 }));
			const liveDir = path.join(tmpRoot, "entwurf-qualify-live1");
			fs.mkdirSync(liveDir);
			fs.writeFileSync(path.join(liveDir, "runner.json"), JSON.stringify({ pid: process.pid, startedAt: Date.now() }));
			const swept = sweepStaleSnapshots(tmpRoot);
			ok("sweep: a dead-pid snapshot dir is reclaimed", swept.includes(deadDir) && !fs.existsSync(deadDir));
			ok("sweep: a live runner's snapshot dir survives", fs.existsSync(liveDir));
			fs.rmSync(tmpRoot, { recursive: true, force: true });
		}
	} finally {
		fs.rmSync(fixtureOrigin, { recursive: true, force: true });
		fs.rmSync(path.dirname(externalTarget), { recursive: true, force: true });
	}
}

console.log(`\n[${SURFACE}] self-test: ${passed} checks passed`);

// ═══ Phase 1d — the real manifests, VALIDATED but not yet run ═══════════════
//
// The HEAD ends here. Everything above and in this block is pure reading and
// checking: no mutant from `scripts/mutants/` is executed and no snapshot of THIS
// repo exists yet. `--manifests-only` returns from exactly this point.

let selected: MutantSpec[];
let manifestCount: number;
{
	const manifests: MutantManifest[] = fs
		.readdirSync(MUTANTS_DIR)
		.filter((f) => f.endsWith(".json"))
		.sort()
		.map((f) => {
			let raw: unknown;
			try {
				raw = JSON.parse(fs.readFileSync(path.join(MUTANTS_DIR, f), "utf8"));
			} catch (err) {
				throw new ManifestError(`${f}: not valid JSON — ${err instanceof Error ? err.message : String(err)}`);
			}
			return validateManifest(raw, f);
		});
	// Vacuous-green guard (matrix-style table integrity): an emptied mutants dir or a
	// manifest lost in a merge must name itself here — "0/0 killed" is not a pass.
	// Extend this inventory and the manifests TOGETHER, never silently.
	const EXPECTED_LANE_MUTANTS: Record<string, number> = {
		"acp-augment": 10,
		"acp-cortex": 12,
		"acp-launch-namespace": 2,
		"acp-overlay": 1,
		"acp-prompt-lifecycle": 15,
		"acp-stop-reason": 6,
		"acp-stream-hooks": 10,
		"acp-usage-accounting": 12,
		"agy-permission": 6,
		"bridge-boot-resume": 3,
		"bridge-command-boot": 9,
		"capability-cache": 3,
		"copilot-birth": 19,
		"copilot-launch": 14,
		"copilot-receive": 18,
		"fresh-cut": 1,
		"gate-qualification": 2,
		"meta-facts": 4,
		"meta-hook-session-switch": 17,
		"meta-identity": 4,
		"meta-retire": 3,
		"mux-boundary": 14,
		"mux-fresh-call": 37,
		"mux-launcher-fence": 7,
		"mux-parent-artifact": 3,
		"pack-install": 2,
		"pi-package-ownership": 6,
		"mux-resume-call": 12,
		"omp-birth": 11,
		"omp-fresh": 24,
		"omp-receive": 11,
		"probe-ordering": 1,
		"release-gate": 15,
		"resume-args": 6,
		"resume-launch-identity": 6,
		"self-address": 5,
		"setup-verdict": 13,
		"source-install": 2,
		"v2-surface": 7,
		"v2-visible-resume": 17,
	};
	const laneTally: Record<string, number> = {};
	for (const man of manifests) laneTally[man.lane] = (laneTally[man.lane] ?? 0) + man.mutants.length;
	try {
		assert.deepEqual(laneTally, EXPECTED_LANE_MUTANTS);
	} catch {
		assert.fail(
			"[QK:LANE-INVENTORY-DECLARED] the mutant lane inventory drifted from the declared contract — extend " +
				"EXPECTED_LANE_MUTANTS and the manifests together, never silently. A lane that lost its manifest in a " +
				"merge, or gained mutants nobody declared, would otherwise pass as `n/n killed` over whatever set " +
				`happened to be on disk. declared=${JSON.stringify(EXPECTED_LANE_MUTANTS)} onDisk=${JSON.stringify(laneTally)}`,
		);
	}
	try {
		selected = validateManifestSet(manifests, makeOriginChecks(REPO_DIR));
	} catch (err) {
		assert.fail(
			"[QK:MANIFEST-SET-INTEGRITY-REFUSED] the committed manifest set broke its cross-manifest contract (global " +
				"claim uniqueness, subject tracked + lstat-regular in the ORIGIN index, signatureSource on the origin work " +
				"surface, claim token present exactly once in its gate source). Every one of those is what makes a KILLED " +
				"verdict mean something, so the set is refused rather than run. Refusal: " +
				(err instanceof Error ? err.message : String(err)),
		);
	}
	manifestCount = manifests.length;
	console.log(`[${SURFACE}] ${selected.length} mutants across ${manifestCount} lanes (no tiers — full set every run)`);
}

if (MANIFESTS_ONLY) {
	console.log(
		`[check-gate-manifests] ok — runner self-test green, ${selected.length} committed mutants across ` +
			`${manifestCount} lanes validated against the origin index, and the lane inventory matches its declared ` +
			"contract. ZERO mutants were executed and this repo was never snapshotted: the body " +
			"(check-gate-qualification) owns that, unchanged.",
	);
	process.exit(0);
}

// ═══ Phase 2 — the real manifests against a snapshot of THIS repo ═══════════

{
	const headBefore = originHead(REPO_DIR);
	const workSurfaceBefore = originWorkSurfaceSha(REPO_DIR);

	sweepStaleSnapshots(os.tmpdir());
	const snap = createRepoSnapshot(REPO_DIR);
	console.log(
		`[gate-qualification] snapshot: ${snap.repoDir} (${snap.fileCount} files, origin HEAD ${headBefore.slice(0, 12)})`,
	);
	let report: Awaited<ReturnType<typeof qualifyMutants>>;
	try {
		report = await qualifyMutants(snap, selected, (line) => console.log(line));
	} finally {
		fs.rmSync(snap.baseDir, { recursive: true, force: true });
	}

	// Tripwire, not recovery: the runner never writes the origin, so any drift here is
	// an outside writer racing the qualification — evidence cannot be attributed.
	assert.equal(originHead(REPO_DIR), headBefore, "origin HEAD changed during qualification");
	assert.equal(
		originWorkSurfaceSha(REPO_DIR),
		workSurfaceBefore,
		"origin work surface changed during qualification (content hash, not porcelain text)",
	);
	console.log("[gate-qualification] origin checkout: HEAD + work-surface content hash identical before/after");

	const killed = report.groups.flatMap((g) => g.mutants).filter((m) => m.verdict === "KILLED");
	const failed = report.groups.flatMap((g) => g.mutants).filter((m) => m.verdict !== "KILLED");
	const controlRed = report.groups.filter((g) => g.control !== "ok");
	if (!report.treeClean || !report.porcelainClean) {
		console.error(
			`[gate-qualification] IMPURE: snapshot tree drifted (treeClean=${report.treeClean} porcelainClean=${report.porcelainClean})`,
		);
	}
	for (const g of controlRed) {
		console.error(`[gate-qualification] CONTROL ${g.control}: ${g.gate.join(" ")}`);
	}
	for (const m of failed) {
		console.error(`[gate-qualification] NOT KILLED: ${m.claim} → ${m.verdict} (${m.detail})`);
	}
	console.log(
		`\n[gate-qualification] qualified claims: ${killed.length}/${selected.length} killed — ${killed.map((m) => m.claim).join(", ")}`,
	);
	assert.ok(reportPassed(report), "gate qualification failed — see NOT KILLED / CONTROL lines above");
}

console.log("[gate-qualification] ok");
