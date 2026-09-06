// Deterministic gate for the release-gate STEP OUTCOME protocol (P1).
//
// THE DEFECT THIS OWNS. The aggregate release gate documented — in run.sh's own
// usage, README, and VERIFY — that a cut needs `LIVE=1` and `SKIP=0`. Nothing
// enforced it. Exit authority read the FAIL counter alone, so
// `./run.sh release-gate <dir>` returned 0 while printing 14 SKIPs and the words
// "all green". And a step that WAS invoked could decline a prerequisite and exit
// 0 — Cortex without `ENTWURF_ACP_CORTEX_CONNECTION` is the measured case — which
// the aggregate counted as PASS. Both holes are the same shape: a skip that
// cannot be told apart from an acceptance, which means a release summary cannot
// prove the calls it claims.
//
// WHAT THIS GATE PINS, in the order the cells run (the order is load-bearing:
// each mutant must die on ITS claim, so a cell that would fire first on another
// cell's mutation is deliberately kept narrow):
//   1. the protocol is ONE number, agreed across the shell and TS halves;
//   2. the classifier never rounds a skip up to a pass;
//   3. `--cut` refuses a MUST skip while a bare diagnostic run does not, AND the
//      refusal names its cause — a step that RAN AND BROKE is a different fact
//      from one that NEVER RAN, and the counters are never fudged to carry it;
//   4. no LIVE smoke still carries the pre-P1 exit-0 skip shape;
//   5. a real smoke invoked with LIVE unset propagates the protocol code out
//      through run_ts (the "direct LIVE!=1" case);
//   6. a run.sh wrapper that declines its own prerequisite does the same (the
//      "internal prerequisite" case, Cortex being the one that was measured).
//   7. every LIVE smoke is either wired into the aggregate or excluded for a
//      reason the docs actually state — the protocol cannot vouch for a step the
//      gate never lists;
//   8. the moved check-gate-qualification stays reachable on its owners, and the
//      CI step qualifies the FULL floor;
//   9. every gate a committed mutant NAMES also runs inside `check:full` (or says
//      in its own prose why it deliberately does not) — a gate reachable only
//      through qualification's control-pre puts a whole defect class behind the
//      28-minute body;
//  10. the CI push trigger is filtered to BRANCH refs, so pushing a release tag
//      does not rebuild a SHA its branch run already built.
//
// Cells 5-6 SPAWN the real subcommands rather than reasoning about them: the
// whole defect was an assumption about what a step would do, so an assumption is
// exactly what this gate must not make. They are cheap — each smoke declines
// before it does any work.
//
// Pure + subprocess, no network/model — IN pnpm run check:full.

import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { copyFileSync, globSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";
import { LIVE_SKIP_EXIT, LIVE_SKIP_MARKER } from "./lib/live-skip.ts";

const REPO_DIR = fileURLToPath(new URL("..", import.meta.url));
const SHELL_LIB = "scripts/lib/step-outcome.sh";

/** Run a snippet with the shell half sourced; returns trimmed stdout. */
function inShell(snippet: string): string {
	return execFileSync("bash", ["-c", `. "${SHELL_LIB}"; ${snippet}`], {
		cwd: REPO_DIR,
		encoding: "utf8",
		timeout: 20_000,
	}).trim();
}

/** Invoke a real run.sh subcommand; returns its exit code + combined output. */
function runSubcommand(sub: string, env: Record<string, string | undefined>): { code: number; output: string } {
	const childEnv: Record<string, string> = {};
	for (const [k, v] of Object.entries({ ...process.env, ...env })) {
		if (v !== undefined) childEnv[k] = v;
	}
	try {
		const out = execFileSync("bash", ["run.sh", sub], {
			cwd: REPO_DIR,
			encoding: "utf8",
			timeout: 120_000,
			env: childEnv,
			stdio: ["ignore", "pipe", "pipe"],
		});
		return { code: 0, output: out };
	} catch (err) {
		const e = err as { status?: number | null; stdout?: string; stderr?: string };
		return { code: e.status ?? -1, output: `${e.stdout ?? ""}${e.stderr ?? ""}` };
	}
}

// ===========================================================================
// 1) ONE protocol, two languages. A drifted constant does not degrade
//    gracefully — it silently reclassifies every skip in the aggregate.
// ===========================================================================
{
	const shellValue = inShell('echo "$ENTWURF_STEP_SKIP_EXIT"');
	assert.equal(
		shellValue,
		String(LIVE_SKIP_EXIT),
		`[QK:SKIP-EXIT-ONE-PROTOCOL] ${SHELL_LIB} and scripts/lib/live-skip.ts must name the SAME skip exit code. ` +
			"The smokes exit with the TS constant and the aggregate classifies with the shell one, so a drift between " +
			"them turns every honest skip into a FAIL (or, the other way, into a PASS) with nothing in the summary " +
			`saying so. shell=${shellValue} ts=${LIVE_SKIP_EXIT}`,
	);
	// The code must also stay clear of the ranges that already mean something
	// else, or a dependency's unrelated verdict reads as a skip.
	assert.ok(
		LIVE_SKIP_EXIT > 4 && LIVE_SKIP_EXIT < 126,
		"the skip code must avoid the per-tool contract band (0..4) and the shell's signal band (126+)",
	);
}

// ===========================================================================
// 2) The classifier. A skip is its own outcome, never rounded up or down.
// ===========================================================================
{
	const table: Array<[string, string]> = [
		["0", "PASS"],
		[String(LIVE_SKIP_EXIT), "SKIP"],
		["1", "FAIL"],
		["2", "FAIL"],
		["127", "FAIL"],
		["137", "FAIL"],
	];
	for (const [code, expected] of table) {
		const got = inShell(`entwurf_step_outcome ${code}`);
		assert.equal(
			got,
			expected,
			`[QK:STEP-OUTCOME-SKIP-NOT-PASS] exit ${code} must classify as ${expected}, got ${got}. A skip rounded up to ` +
				"PASS is exactly the pre-P1 defect: the aggregate then reports acceptance for a step that told it, in the " +
				"only channel it has, that it never ran. A skip rounded down to FAIL is the mirror error and makes the " +
				"unattended diagnostic unusable.",
		);
	}
}

// ===========================================================================
// 3) Cut authority. `--cut` is the executable half of "a CUT needs SKIP=0";
//    without it the diagnostic must stay green so an unattended run is usable.
// ===========================================================================
{
	const releasable = (failc: number, skipc: number, cut: number): boolean =>
		inShell(`if entwurf_release_releasable ${failc} ${skipc} ${cut}; then echo YES; else echo NO; fi`) === "YES";

	assert.ok(releasable(0, 0, 1), "a cut with no failures and no skips is releasable");
	assert.ok(!releasable(1, 0, 1), "a failure blocks a cut");
	assert.ok(!releasable(1, 0, 0), "a failure blocks the diagnostic too — FAIL was always blocking");
	assert.ok(
		releasable(0, 3, 0),
		"a DIAGNOSTIC run with skips stays exit 0 — an unattended `./run.sh release-gate` must remain runnable, and " +
			"turning it red was never the ask",
	);
	assert.ok(
		!releasable(0, 3, 1),
		"[QK:CUT-REFUSES-SKIP] `--cut` must refuse a MUST SKIP. This is the whole point: the release procedure said " +
			'"a CUT needs LIVE=1, SKIP=0" in prose while the code returned 0 with 14 skips, so a summary could be quoted ' +
			"as acceptance for calls that never happened. It also removes the need for a separate LIVE assertion — with " +
			"LIVE unset every LIVE-gated step skips, and the skip count is what blocks.",
	);

	// …and the refusal must SAY WHICH of the two it is. A blocked cut caused by a
	// broken call and one caused by an absent prerequisite need different actions
	// from whoever reads the record, and the counters must not be fudged to carry
	// that (a synthesized FAIL=1 for a policy block erases the distinction).
	const verdict = (failc: number, skipc: number, cut: number): string =>
		inShell(`entwurf_release_verdict ${failc} ${skipc} ${cut}`);

	assert.equal(verdict(0, 0, 1), "cut: OK", "a clean cut says so in one token");
	assert.equal(
		verdict(0, 3, 0),
		"cut: n/a (diagnostic, 3 SKIP)",
		"a diagnostic run names its skips without claiming a cut",
	);
	assert.equal(verdict(0, 0, 0), "cut: n/a (diagnostic)", "a clean diagnostic run still does not claim a cut");
	assert.equal(
		verdict(1, 0, 1),
		"cut: BLOCKED (MUST FAIL)",
		"a step that RAN AND BROKE must be named as a failure — that is a defect to fix",
	);
	assert.equal(
		verdict(0, 3, 1),
		"cut: BLOCKED (MUST SKIP)",
		"[QK:CUT-VERDICT-NAMES-CAUSE] a cut blocked ONLY by skips must say so in its own token, distinct from a failure " +
			"block. An operator (and the P5 release record) reads two different actions out of these: a MUST FAIL is a " +
			"broken call to fix, a MUST SKIP is a prerequisite to supply. Collapsing them into one string — or worse, " +
			"synthesizing FAIL=1 for the policy block — throws away the exact distinction this protocol was built to make.",
	);
	assert.equal(
		verdict(2, 5, 1),
		"cut: BLOCKED (MUST FAIL)",
		"when both are present the FAILURE is the headline — a broken call outranks a missing prerequisite",
	);
}

// ===========================================================================
// 4) No LIVE smoke still carries the pre-P1 skip shape (static, all of them).
//    A future smoke that hand-rolls `exit 0` on a skip re-opens the hole for
//    one lane only, which is precisely how this survived so long.
// ===========================================================================
{
	const smokes = globSync("scripts/smoke-*live*.ts", { cwd: REPO_DIR }).sort();
	assert.ok(smokes.length >= 15, `expected the LIVE smoke family, found ${smokes.length}`);
	let liveGated = 0;
	for (const rel of smokes) {
		const src = readFileSync(join(REPO_DIR, rel), "utf8");
		if (!src.includes("process.env.LIVE")) continue; // gated in run.sh instead (cell 6 owns that surface)
		liveGated++;
		// ONE assertion, three ways to fail it: no protocol import, or either of
		// the two pre-P1 shapes (exit 0 / bare return) still inside the LIVE gate.
		// Kept as one so the claim owns every way a smoke can go back to being
		// indistinguishable from success — a split would let a mutation die on an
		// unclaimed sibling assertion instead of here.
		const importsProtocol = src.includes('from "./lib/live-skip.ts"');
		const exitsZero = /LIVE !== "1"[\s\S]{0,400}?process\.exit\(0\)/.test(src);
		const bareReturns = /LIVE !== "1"[\s\S]{0,400}?\n\t+return;/.test(src);
		assert.ok(
			importsProtocol && !exitsZero && !bareReturns,
			`[QK:NO-SMOKE-SKIPS-WITH-ZERO] ${basename(rel)} gates on LIVE but does not decline through skipLive ` +
				`(importsProtocol=${importsProtocol} exitsZero=${exitsZero} bareReturns=${bareReturns}). Every LIVE smoke ` +
				"must take the one protocol exit — a hand-rolled `process.exit(0)` or bare `return` is indistinguishable " +
				"from success, which is exactly what let the aggregate count a never-run step as PASS.",
		);
	}
	assert.ok(liveGated >= 15, `expected most LIVE smokes to gate on LIVE, got ${liveGated}`);
}

// ===========================================================================
// 5) REAL propagation — the direct `LIVE!=1` case, end to end through run_ts.
//    Static source pins cannot see a transport that swallows the code.
// ===========================================================================
{
	const { code, output } = runSubcommand("smoke-acp-raw-turn-live", { LIVE: undefined });
	assert.equal(
		code,
		LIVE_SKIP_EXIT,
		`[QK:LIVE-SKIP-IS-PROTOCOL-EXIT] a LIVE smoke invoked with LIVE unset must leave the protocol's SKIP code on ` +
			`the process, all the way out through run_ts — got exit ${code}. Exit 0 here is the original defect: the ` +
			`aggregate cannot tell "I declined" from "I passed", so it reports acceptance. Output: ` +
			`${JSON.stringify(output.slice(-300))}`,
	);
	assert.ok(
		output.includes(LIVE_SKIP_MARKER),
		`the skip must also be readable by a human in the log — ${LIVE_SKIP_MARKER} names the missing prerequisite so an ` +
			"operator who hits a red --cut run knows what to supply. Output: " +
			JSON.stringify(output.slice(-300)),
	);
}

// ===========================================================================
// 6) REAL propagation — a run.sh WRAPPER declining its own prerequisite. This
//    is the second skip surface: some smokes never reach their .ts file at all.
// ===========================================================================
{
	const viaWrapper = runSubcommand("smoke-acp-cortex-live", { LIVE: undefined });
	assert.equal(
		viaWrapper.code,
		LIVE_SKIP_EXIT,
		`[QK:WRAPPER-SKIP-IS-PROTOCOL-EXIT] a run.sh smoke WRAPPER that declines a prerequisite must return the protocol ` +
			`SKIP code, not 0 — got exit ${viaWrapper.code}. The wrapper is a skip surface of its own (cortex and matrix ` +
			"both decline before their .ts is ever reached), so fixing only the TypeScript " +
			`half would leave the aggregate counting those as PASS. Output: ${JSON.stringify(viaWrapper.output.slice(-300))}`,
	);

	// The measured Cortex cell: LIVE IS set, but the connection the adapter needs
	// is not. Which branch declines (the wrapper's `cortex` PATH check or the
	// smoke's own connection check) depends on the host; the OUTCOME must not.
	const missingPrereq = runSubcommand("smoke-acp-cortex-live", {
		LIVE: "1",
		ENTWURF_ACP_CORTEX_CONNECTION: undefined,
	});
	assert.equal(
		missingPrereq.code,
		LIVE_SKIP_EXIT,
		"LIVE=1 with no ENTWURF_ACP_CORTEX_CONNECTION must be a SKIP, not a PASS — this is the exact cell that made a " +
			"cortex-less host look like cortex acceptance. Output: " +
			JSON.stringify(missingPrereq.output.slice(-300)),
	);
}

// ===========================================================================
// 7) NO SILENT AGGREGATE OMISSION. The protocol tells the truth about the steps
//    the gate RUNS; it says nothing about steps the gate never lists. Three LIVE
//    smokes (cortex, spawn-live, claude-native-resume) sat outside the aggregate
//    with no stated reason until 2026-07-31, so a green cut was silent about the
//    second backend, the spawn substrate, and native resume. (spawn-live was
//    deleted with its transport in the visible-first cut; the incident is kept
//    verbatim because it is what this rule was derived from.)
//
//    So: every LIVE smoke is either WIRED into release_gate or EXCLUDED for a
//    reason an operator can read in the docs. The exclusion half is checked
//    against the doc text, not against a list in this file — an exclusion that
//    only this gate believes in is how the omission would come back.
// ===========================================================================
{
	const runSh = readFileSync(join(REPO_DIR, "run.sh"), "utf8");
	const gateBody = runSh.slice(runSh.indexOf("release_gate() {"), runSh.indexOf("# 5. Summary"));
	assert.ok(gateBody.length > 1000, "located the release_gate body");

	// name → the sentence in the docs that carries its exclusion, and where.
	const DOCUMENTED_EXCLUSIONS: Record<string, [file: string, sentence: string]> = {
		"smoke-acp-long-turn-live": ["VERIFY.md", "on-demand, not part of `release-gate`"],
		"smoke-mux-fresh-call-live": ["VERIFY.md", "Fresh-call LIVE is on-demand, not part of `release-gate`"],
		"smoke-agy-native-push-live": ["VERIFY.md", "Aggregate release-gate does not own an agy conversation id"],
		"smoke-acp-ordering-probe-live": ["docs/acp-backend-rail.md", "opt-in paired observation"],
		// Cortex needs an external Snowflake connection the HOST owns, so an aggregate
		// that required it would block every cut taken without that account. Excluded —
		// NOT waived: its direct call stays required for a Cortex-rail cut, and running
		// it without the connection still reports protocol SKIP rather than a pass.
		"smoke-acp-cortex-live": ["VERIFY.md", "The release aggregate does not re-certify Cortex"],
	};

	const allLive = globSync("scripts/smoke-*live*.{ts,sh}", { cwd: REPO_DIR })
		.map((p) => basename(p).replace(/\.(ts|sh)$/, ""))
		.sort();
	assert.ok(allLive.length >= 18, `expected the full LIVE smoke family, found ${allLive.length}`);

	for (const name of allLive) {
		const wired = gateBody.includes(`"$self" ${name}\n`) || gateBody.includes(`"$self" ${name} `);
		const excused = DOCUMENTED_EXCLUSIONS[name];
		if (wired) {
			assert.ok(!excused, `${name} is both wired and excused — pick one`);
			continue;
		}
		assert.ok(
			excused,
			`[QK:NO-SILENT-AGGREGATE-OMISSION] ${name} is neither wired into release_gate nor excluded in the docs. ` +
				"A LIVE smoke that exists but is never listed makes a green cut silent about the axis it covers — exactly " +
				"how cortex (the second shipped backend) and claude-native-resume went unrun for releases. " +
				"Wire it, or state the exclusion where an operator reads it.",
		);
		const [file, sentence] = excused as [string, string];
		assert.ok(
			readFileSync(join(REPO_DIR, file), "utf8").includes(sentence),
			`${name} claims a documented exclusion, but ${file} no longer says "${sentence}" — an exclusion only this ` +
				"gate believes in is not documented",
		);
	}
}

// ===========================================================================
// 8. qualification scheduling topology — the subtraction has its own oracle.
//    check-gate-qualification left the default check chains (operator
//    inner-loop cost, 2026-08 subtraction). That move is a gate/release
//    contract: the step must stay REACHABLE on the axes that now own it — the
//    CI check job (on the pushes #103's filter still sends it) and release_gate
//    as its own MUST step — and
//    must not silently return to the default chain. Without this cell,
//    deleting the release_gate qualification block or the CI line leaves every
//    focused gate green while a cut quietly loses its discriminating-power
//    step.
//
//    THREE claims, because each is an independent contract. 8a is REACHABILITY
//    (absent from the default chain; present exactly once in CI and exactly once
//    as a wired release_gate MUST step; named in VERIFY). 8b is what the CI step
//    qualifies (the FULL floor, before the qualification run), added by #70. 8c is
//    what the RELEASE path ACCEPTS as evidence for one SHA — that the body step
//    actually ran there (#103). Each carries its own replant — one mutant must
//    never stand in for another.
// ===========================================================================
{
	// The default chain is tiered (#70): `check` (core) and `check:full` compose the
	// named group scripts, so the reachability scan covers EVERY check* script —
	// qualification sneaking into any group re-doubles the closure floor.
	const pkgScripts = (
		JSON.parse(readFileSync(join(REPO_DIR, "package.json"), "utf8")) as { scripts: Record<string, string> }
	).scripts;
	const pkgCheck = Object.entries(pkgScripts)
		.filter(([name]) => name === "check" || name.startsWith("check:"))
		.map(([, body]) => body)
		.join(" && ");
	const ciYml = readFileSync(join(REPO_DIR, ".github/workflows/ci.yml"), "utf8");
	const ciHits = ciYml.split("- run: ./run.sh check-gate-qualification").length - 1;
	const runShQ = readFileSync(join(REPO_DIR, "run.sh"), "utf8");
	const qualGateBody = runShQ.slice(runShQ.indexOf("release_gate() {"), runShQ.indexOf("# 5. Summary"));
	const invocations = qualGateBody.split('bash "$self" check-gate-qualification').length - 1;
	const verifyDoc = readFileSync(join(REPO_DIR, "VERIFY.md"), "utf8");

	// One claim token, one assert (the qualification runner requires the exact-once
	// signature); each broken axis names itself in the joined message.
	const holes: string[] = [];
	if (pkgCheck.includes("check-gate-qualification"))
		holes.push(
			"package.json's default `check` chain contains check-gate-qualification again (doubles every closure floor)",
		);
	if (ciHits !== 1) holes.push(`the CI check job runs check-gate-qualification ${ciHits}x (need exactly once)`);
	if (invocations !== 1)
		holes.push(`release_gate invokes check-gate-qualification ${invocations}x (need exactly one MUST step)`);
	if (
		!qualGateBody.includes('results+=("PASS  check-gate-qualification")') ||
		!qualGateBody.includes('results+=("FAIL  check-gate-qualification")')
	)
		holes.push("the release_gate qualification step does not wire PASS/FAIL into the MUST counters");
	if (
		!verifyDoc.includes(
			"in the CI `check` job on a branch push that touched the qualification surface, and as a release-gate MUST step",
		)
	)
		holes.push("VERIFY.md no longer names the owners of the moved qualification step");
	assert.ok(
		holes.length === 0,
		"[QK:QUALIFICATION-SCHEDULING-REACHABLE] check-gate-qualification left the default check chains " +
			"deliberately, so it must stay REACHABLE on the axes that own it now — absent from the default chain, " +
			"exactly once in the CI check job, exactly once as a release_gate MUST step with its " +
			`outcome wired, and named in VERIFY. Broken: ${holes.join("; ")}`,
	);

	// 8b. WHAT the CI qualification step qualifies — its own claim, not a branch
	//     folded into the one above. #70 split the deterministic floor into tiers,
	//     so "CI runs qualification once" stopped being sufficient evidence on its
	//     own: qualification on top of the ≤60s core would certify kill-power over
	//     a floor no candidate ships on. This is ONE contract with one condition —
	//     the full floor is present in the CI check job AND qualification follows
	//     it — because a floor that is absent and a floor that runs afterwards
	//     break the same promise identically. The committed replant qualifies the
	//     downgrade/omission axis (the tier rename downgrading CI back to core);
	//     ordering stays directly asserted here and has no incident-earned mutant.
	const ciFloorAt = ciYml.indexOf("- run: pnpm run check:full");
	const ciQualAt = ciYml.indexOf("- run: ./run.sh check-gate-qualification");
	assert.ok(
		ciFloorAt !== -1 && ciQualAt > ciFloorAt,
		"[QK:CI-FULL-FLOOR-QUALIFIED] the CI check job owns the FULL deterministic floor (#70): it must run " +
			"`pnpm run check:full` — not the ≤60s core — and check-gate-qualification must come AFTER it, so the " +
			"kill-power proof covers the floor a candidate actually ships on. The committed replant qualifies the " +
			"downgrade/omission axis; ordering is directly asserted by this same oracle. " +
			`Broken: check:full at index ${ciFloorAt}, qualification at index ${ciQualAt}.`,
	);

	// 8c. The RELEASE oracle requires that body to have actually run at the release
	//     SHA -- its own contract, not a branch of 8a. 8a is REACHABILITY (the step
	//     exists in the CI job and in release_gate); this is about what the release
	//     path ACCEPTS as evidence for one SHA. `verify-exact-ci.sh` read only three
	//     job names, and a job conclusion says nothing about whether the step inside
	//     it ran: the moment ci.yml can skip that step (#103 piece 2), a green oracle
	//     would certify a SHA whose qualification body never executed. That is the
	//     "green with no evidence" class this repo fails closed on, which is why the
	//     oracle gets the fourth axis BEFORE the skip exists.
	//
	//     This is a TEXT oracle, the same grade as check-install-surface S7g. A
	//     behavioural oracle would need either a second file (S7a/S7g bind the
	//     release surface to one script read from the index) or an injectable
	//     RUN_JSON seam -- and that seam would be a way to launder release evidence
	//     past gh. Both cost more than the axis is worth here.
	const ciOracle = readFileSync(join(REPO_DIR, ".claude/skills/entwurf-release/scripts/verify-exact-ci.sh"), "utf8");
	const axis: string[] = [];
	if (!ciOracle.includes('QUAL_JOB = "check"') || !ciOracle.includes('"Run ./run.sh check-gate-qualification"'))
		axis.push("the oracle does not name the check job's check-gate-qualification step");
	if (!ciOracle.includes('steps[QUAL_STEP] != "success"'))
		axis.push("the oracle does not require that step's conclusion to be 'success'");
	if (!ciOracle.includes('steps[QUAL_STEP] == "skipped"'))
		axis.push("the oracle does not classify a SKIPPED body as a failure of its own");
	assert.ok(
		axis.length === 0,
		"[QK:RELEASE-SHA-QUALIFIED-IN-CI] the exact-SHA CI oracle must require the qualification BODY to have run " +
			"at the release SHA -- the `check` job's `Run ./run.sh check-gate-qualification` step concluding 'success', " +
			"with skipped named as its own failure. Three green job names do not prove the step inside one of them " +
			`executed. Broken: ${axis.join("; ")}`,
	);
}

// ===========================================================================
// 8d. The qualification filter COVERS every mutant subject (#103 piece 2)
//
//     The body no longer runs on every branch push; a decision script reads the
//     push range and answers. Its whole safety argument is that the path set is
//     DERIVED from the committed manifests rather than copied into a list, so a
//     new mutant subject cannot land outside the filter and quietly stop being
//     re-proven in CI. This asserts that property behaviourally: every subject
//     and signatureSource in scripts/mutants/*.json, fed to the script as a
//     one-file change, must decide `run_body=true`. The oracle is the manifests
//     themselves, read here independently of the script.
// ===========================================================================
{
	const decider = join(REPO_DIR, "scripts/ci-qualify-decide.sh");
	const paths = new Set<string>();
	for (const file of globSync("scripts/mutants/*.json", { cwd: REPO_DIR })) {
		const manifest = JSON.parse(readFileSync(join(REPO_DIR, file), "utf8")) as {
			mutants?: { subject?: string; signatureSource?: string }[];
		};
		for (const mutant of manifest.mutants ?? []) {
			if (mutant.subject) paths.add(mutant.subject);
			if (mutant.signatureSource) paths.add(mutant.signatureSource);
		}
	}
	assert.ok(paths.size > 50, `read only ${paths.size} mutant paths from the manifests`);
	const uncovered = [...paths].filter((path) => {
		const out = execFileSync("bash", [decider, "--files-from", "-"], {
			cwd: REPO_DIR,
			encoding: "utf8",
			input: `${path}\n`,
			stdio: ["pipe", "pipe", "ignore"],
		});
		return out.trim() !== "run_body=true";
	});
	assert.ok(
		uncovered.length === 0,
		"[QK:QUALIFY-FILTER-COVERS-SUBJECTS] the CI qualification filter must run the body for a change to ANY " +
			"committed mutant subject or signature source — it derives that set from scripts/mutants/*.json for " +
			"exactly this reason, so a path it cannot see is a claim that silently stops being re-proven in CI. " +
			`Uncovered (${uncovered.length} of ${paths.size}): ${uncovered.slice(0, 8).join(", ")}`,
	);
}

// ===========================================================================
// 8e. The filter still runs the body for every RED the body has ever produced
//
//     Five reds in 549 runs (#99 stage-2). The first reading of them used the
//     tip COMMIT and concluded the filter would have missed four; replaying the
//     real two-dot push range — what GitHub actually compares — showed all five
//     hit. That reversal is the whole evidentiary basis for this filter.
//
//     It is asserted from RECORDED file lists, not from live history, and that
//     is a constraint rather than a convenience: check-gate-qualification runs
//     every gate inside a snapshot with its own fresh git baseline, where these
//     2026-07/08 commits do not exist. A cell that read history there would be
//     CONTROL-RED for the whole lane — measured, not predicted (this cell did
//     exactly that on 2026-09-06 and cost the release-gate lane its 17 kills).
//     The fixture carries what history said, measured once, in a repo where the
//     objects are present.
//
//     The two-dot READING itself is proven separately, below — and that is where
//     this pair's kill-power lives: this cell carries no committed mutant,
//     because all five ranges also touch a manifest subject, so any mutation
//     that could redden it reddens 8d first and would die at the wrong claim.
// ===========================================================================
{
	const decider = join(REPO_DIR, "scripts/ci-qualify-decide.sh");
	const fixture = JSON.parse(readFileSync(join(REPO_DIR, "scripts/fixtures/qualify-replay.json"), "utf8")) as {
		runs: { runId: string; before: string; head: string; files: string[]; tipOnlyFiles: string[] }[];
	};
	assert.equal(fixture.runs.length, 5, "the replay fixture holds all five historical qualification reds");
	const wrong: string[] = [];
	for (const run of fixture.runs) {
		assert.ok(run.files.length > 0, `run ${run.runId} has no recorded push range`);
		const out = execFileSync("bash", [decider, "--files-from", "-"], {
			cwd: REPO_DIR,
			encoding: "utf8",
			input: `${run.files.join("\n")}\n`,
			stdio: ["pipe", "pipe", "ignore"],
		}).trim();
		if (out !== "run_body=true") wrong.push(`run ${run.runId} (${run.files.length} files) decided ${out}`);
	}
	assert.ok(
		wrong.length === 0,
		"every qualification RED in this repo's CI history must still run the body under the filter, over the " +
			"two-dot push range GitHub compares — the measurement that overturned the tip-commit reading and " +
			"justified filtering at all. Directly asserted, with no committed replant: every one of the five ranges " +
			"also carries a manifest subject, so any single-arm mutation that could turn this red is caught one cell " +
			"earlier by QUALIFY-FILTER-COVERS-SUBJECTS — a replant here would die at the wrong claim (measured " +
			"2026-09-06). The two-dot READING has its own kill-qualified claim below. " +
			`Broken: ${wrong.join("; ")}`,
	);
}

// ===========================================================================
// 8f. The filter reads the two-dot PUSH RANGE, not the tip commit
//
//     The fixture above proves the matcher's verdict on recorded file lists; it
//     cannot prove which git range produced them, because it calls no git. This
//     does, hermetically: a throwaway repo shaped like the real defect — a push
//     of two commits whose TIP is docs-only while the commit under it touched a
//     mutant subject. The two-dot range sees the code; the tip alone does not.
//     That is the exact misreading #99 corrected, and it is what four of the
//     five recorded pushes look like when read the wrong way.
//
//     Hermetic on purpose: no repo history, so it runs identically inside the
//     qualification snapshot.
// ===========================================================================
{
	const decider = join(REPO_DIR, "scripts/ci-qualify-decide.sh");
	const tmp = mkdtempSync(join(tmpdir(), "entwurf-qualify-range-"));
	// core.hooksPath is set globally on this operator's machine; a fixture repo
	// must not run their hooks.
	const git = (...args: string[]) =>
		execFileSync("git", ["-c", "core.hooksPath=/dev/null", "-c", "user.email=g@e", "-c", "user.name=g", ...args], {
			cwd: tmp,
			stdio: "ignore",
		});
	try {
		git("init", "-q", "-b", "main");
		// The decider reads the repo it SITS IN, so the fixture gets a real copy
		// of it and its own one-entry manifest: no seam, no env override, and the
		// manifest-reading path is exercised too.
		mkdirSync(join(tmp, "scripts/mutants"), { recursive: true });
		mkdirSync(join(tmp, "pi-extensions/lib"), { recursive: true });
		copyFileSync(decider, join(tmp, "scripts/ci-qualify-decide.sh"));
		writeFileSync(
			join(tmp, "scripts/mutants/fixture.json"),
			`${JSON.stringify(
				{
					schemaVersion: 1,
					lane: "fixture",
					mutants: [{ claim: "FIXTURE", subject: "pi-extensions/lib/fixture-subject.ts" }],
				},
				null,
				"\t",
			)}\n`,
		);
		writeFileSync(join(tmp, "seed.txt"), "seed\n");
		git("add", "-A");
		git("commit", "-qm", "seed");
		const base = execFileSync("git", ["rev-parse", "HEAD"], { cwd: tmp, encoding: "utf8" }).trim();
		writeFileSync(join(tmp, "pi-extensions/lib/fixture-subject.ts"), "// a mutant subject\n");
		git("add", "-A");
		git("commit", "-qm", "code commit (mid-push)");
		writeFileSync(join(tmp, "README.md"), "docs only\n");
		git("add", "-A");
		git("commit", "-qm", "docs commit (tip)");
		const head = execFileSync("git", ["rev-parse", "HEAD"], { cwd: tmp, encoding: "utf8" }).trim();
		const decide = (from: string) =>
			execFileSync("bash", [join(tmp, "scripts/ci-qualify-decide.sh"), from, head], {
				cwd: tmp,
				encoding: "utf8",
				env: { ...process.env, CI_EVENT_NAME: "push", CI_FORCED: "false" },
				stdio: ["ignore", "pipe", "ignore"],
			}).trim();
		const overRange = decide(base);
		const overTip = decide(`${head}~1`);
		assert.ok(
			overRange === "run_body=true" && overTip === "run_body=false",
			"[QK:QUALIFY-FILTER-READS-PUSH-RANGE] the filter must diff the whole two-dot push range, not the tip " +
				"commit: a push whose tip is docs-only can still carry a mutant subject underneath it, which is how " +
				"four of the five historical reds look like docs pushes when read tip-first. " +
				`Broken: range=${overRange}, tip-only=${overTip} (tip-only must be false, or this fixture proves nothing).`,
		);
	} finally {
		rmSync(tmp, { recursive: true, force: true });
	}
}

// ===========================================================================
// 9. Every gate a mutant manifest NAMES runs inside `pnpm run check:full`
//
//    The measurement behind this (#99 B-3/B-4): across 549 CI runs the mutant-
//    EXECUTION half of qualification never once produced a SURVIVED / WRONG-REASON /
//    MUTANT-STALE / HANG. What it did catch twice was a gate that was already red on a
//    clean tree — CONTROL-PRE — and that class is caught 5.4 minutes earlier, and for
//    free, by any gate the deterministic floor already runs. So a mutant-named gate
//    that sits OUTSIDE `check:full` is the one place where a baseline break can only
//    be found by paying the 28-minute body. `check-omp-birth-hook` was exactly that
//    gate, reachable in the whole repo only through qualification's control-pre.
//
//    The exclusion arm is not a loophole: `scripts/check-setup-qualification.sh` is a
//    mutation-attribution oracle the manifests invoke DIRECTLY and its own header says
//    it is deliberately outside every tier. Like cell 7, the excuse is checked against
//    the text an operator can read, never against a list only this gate believes in.
//
//    ONE PREMISE, stated because it is invisible from here: the script-path join below
//    ignores MODE FLAGS in a gate argv. The `--attribution-self-test` gate therefore
//    counts as covered by the `check-gate-manifests` arm only because
//    `checkVitestAttribution()` runs UNCONDITIONALLY, before that flag is read
//    (`scripts/check-gate-qualification.ts`). Move that call behind a flag and this
//    cell stays green while saying something false.
// ===========================================================================
{
	const pkg = JSON.parse(readFileSync(join(REPO_DIR, "package.json"), "utf8")) as { scripts: Record<string, string> };
	// The floor is composed (#70): `check:full` names group scripts, and a group script
	// may name further ones. Expand transitively rather than hard-coding the tier list.
	const expand = (name: string, seen: Set<string>): string => {
		if (seen.has(name)) return "";
		seen.add(name);
		const body = pkg.scripts[name] ?? "";
		let out = body;
		for (const ref of body.matchAll(/pnpm run ([\w:.-]+)/g)) out += ` ${expand(ref[1], seen)}`;
		const elapsed = /check-elapsed\.sh\s+[\w:.-]+\s+(.+)$/.exec(body);
		if (elapsed) for (const g of elapsed[1].trim().split(/\s+/)) out += ` ${expand(g, seen)}`;
		return out;
	};
	const floorText = expand("check:full", new Set());
	const floorSubcommands = new Set([...floorText.matchAll(/\.\/run\.sh ([\w:.-]+)/g)].map((m) => m[1]));

	// run.sh case arms, so a gate invoked by SCRIPT PATH can be joined to the floor
	// subcommand that runs that same script.
	const arms = new Map<string, string>();
	{
		let names: string[] = [];
		let body: string[] = [];
		for (const line of readFileSync(join(REPO_DIR, "run.sh"), "utf8").split("\n")) {
			const head = /^ {2}([\w|:.-]+)\)$/.exec(line);
			if (head) {
				names = head[1].split("|");
				body = [];
				continue;
			}
			if (line === "    ;;") {
				for (const n of names) arms.set(n, body.join("\n"));
				names = [];
				continue;
			}
			if (names.length > 0) body.push(line);
		}
	}

	const gates = new Map<string, string[]>();
	for (const rel of globSync("scripts/mutants/*.json", { cwd: REPO_DIR }).sort()) {
		const doc = JSON.parse(readFileSync(join(REPO_DIR, rel), "utf8")) as { mutants: Array<{ gate: string[] }> };
		for (const m of doc.mutants) gates.set(m.gate.join(" "), m.gate);
	}
	assert.ok(gates.size >= 40, `expected the committed mutant gate set, found ${gates.size} distinct gate argvs`);

	// argv → the file that states, in prose an operator reads, why it is outside the floor.
	const DOCUMENTED_OUTSIDE: Record<string, [file: string, sentence: string]> = {
		"bash scripts/check-setup-qualification.sh": [
			"scripts/check-setup-qualification.sh",
			"run.sh subcommand and NOT in any check tier",
		],
	};

	const unreached: string[] = [];
	for (const [key, argv] of gates) {
		if (argv[0] === "bash" && argv[1] === "run.sh") {
			if (!floorSubcommands.has(argv[2])) unreached.push(`${key} — run.sh ${argv[2]} is in no check:full group`);
			continue;
		}
		const scriptPath = argv.find((t) => /^scripts\/.+\.(sh|ts|py)$/.test(t));
		if (scriptPath !== undefined && [...floorSubcommands].some((sub) => (arms.get(sub) ?? "").includes(scriptPath))) {
			continue;
		}
		const excused = DOCUMENTED_OUTSIDE[key];
		if (excused === undefined) {
			unreached.push(`${key} — no check:full subcommand invokes ${scriptPath ?? "(no script path in its argv)"}`);
			continue;
		}
		const [file, sentence] = excused;
		if (!readFileSync(join(REPO_DIR, file), "utf8").includes(sentence)) {
			unreached.push(`${key} claims a documented exclusion, but ${file} no longer says "${sentence}"`);
		}
	}
	assert.ok(
		unreached.length === 0,
		"[QK:MUTANT-GATES-INSIDE-FULL-FLOOR] every gate a committed mutant names must also run inside `pnpm run " +
			"check:full`, or state its exclusion where an operator reads it. A gate reachable ONLY through " +
			"qualification's control-pre makes the 28-minute mutant body the only thing that can notice it going red on " +
			"a clean tree — the one CI class that body has actually caught, and the one the 5.4-minute floor catches for " +
			`free everywhere else. Unreached: ${unreached.join("; ")}`,
	);
}

// ===========================================================================
// 10. A TAG push rebuilds nothing
//
//     Measured over this repo's whole history (#99 B-1): 66 of 66 semver tag-push runs
//     rebuilt a SHA some other run had already built, and no tag run ever reported a
//     fact its branch run did not — the single non-green one failed at the same step as
//     its main run, two seconds later. That is 28% of a release window's runner minutes
//     buying a badge on a ref. The exact-SHA evidence a release quotes is the BRANCH
//     run, which is also the run `entwurf-release` land mode reports.
//
//     So `on.push` must carry a REF FILTER that selects branches. `branches:` alone is
//     what makes a tag push create no run at all; a `tags:` key would put them back.
// ===========================================================================
{
	const ciYml = readFileSync(join(REPO_DIR, ".github/workflows/ci.yml"), "utf8");
	const onAt = ciYml.indexOf("\non:\n");
	const envAt = ciYml.indexOf("\nenv:\n");
	assert.ok(onAt !== -1 && envAt > onAt, "located the workflow `on:` block");
	const onLines = ciYml.slice(onAt, envAt).split("\n");
	const pushAt = onLines.findIndex((l) => /^ {2}push:\s*$/.test(l));
	const nextKeyAt = onLines.findIndex((l, i) => i > pushAt && /^ {2}\S/.test(l));
	const pushBody = onLines
		.slice(pushAt + 1, nextKeyAt === -1 ? undefined : nextKeyAt)
		.filter((l) => l.trim() !== "" && !/^\s*#/.test(l));
	const gaps: string[] = [];
	if (pushAt === -1) gaps.push("the `on:` block has no `push:` trigger");
	if (!pushBody.some((l) => /^ {4}branches(-ignore)?:/.test(l)))
		gaps.push(`the push trigger carries no branch ref filter (body: ${JSON.stringify(pushBody)})`);
	if (pushBody.some((l) => /^ {4}tags(-ignore)?:/.test(l)))
		gaps.push("the push trigger names tags — a tag push would create a second run for a SHA already built");
	assert.ok(
		gaps.length === 0,
		"[QK:CI-TAG-PUSH-NOT-REBUILT] the CI `push` trigger must be filtered to BRANCH refs, so pushing a release tag " +
			"creates no run: 66/66 semver tag runs in this repo's history rebuilt an already-built SHA and none ever " +
			"reported a fact its branch run had not, while costing 28% of a release window's runner minutes. Dropping " +
			`the filter does not add evidence, it duplicates it. Broken: ${gaps.join("; ")}`,
	);
}

// ===========================================================================
// The integrated mux lifecycle is a MUST, and the focused fresh-call LIVE is not
//
// Two LIVE smokes now cover the mux rail and they are NOT interchangeable:
// `smoke-mux-fresh-call-live` drives the composition from SOURCE and is on-demand,
// while `smoke-mux-lifecycle-live` enters through the real MCP surface and follows a
// citizen through resume and recall. A cut that ran only the focused one would be
// green about the axis nobody proved. So the MUST wiring is pinned here, exactly
// once, together with the doc sentence that keeps the two apart for an operator.
// ===========================================================================
{
	const runSh = readFileSync(join(REPO_DIR, "run.sh"), "utf8");
	const gateBody = runSh.slice(runSh.indexOf("release_gate() {"), runSh.indexOf("# 5. Summary"));
	const verify = readFileSync(join(REPO_DIR, "VERIFY.md"), "utf8");
	const mustSteps = gateBody.split("\n").filter((l) => l.includes('"$self" smoke-mux-lifecycle-live'));
	const gaps: string[] = [];
	if (mustSteps.length !== 1)
		gaps.push(`release_gate runs smoke-mux-lifecycle-live ${mustSteps.length}x (need exactly one MUST step)`);
	if (mustSteps.length === 1 && !mustSteps[0]?.includes("run_live_step"))
		gaps.push("the lifecycle step does not go through run_live_step, so its SKIP would not reach the classifier");
	if (!verify.includes("Fresh-call LIVE is on-demand, not part of `release-gate`"))
		gaps.push("VERIFY.md no longer excuses the focused fresh-call LIVE from the aggregate");
	if (!verify.includes("smoke-mux-lifecycle-live"))
		gaps.push("VERIFY.md does not name the integrated lifecycle MUST at all");
	assert.ok(
		gaps.length === 0,
		"[QK:MUX-LIFECYCLE-IS-RELEASE-MUST] the integrated mux lifecycle LIVE must be a release-gate MUST exactly once " +
			"and go through run_live_step (so a missing prerequisite is a SKIP the cut refuses, never a silent pass), " +
			"while the focused fresh-call LIVE stays on-demand and VERIFY keeps the two distinguishable — a cut that " +
			`ran only the source-level smoke would be green about the surface no one entered. Broken: ${gaps.join("; ")}`,
	);
}

// ===========================================================================
// The operator's CONFIGURED bridge invocation is proven BEFORE the cost-bearing LIVE tier
//
// `check-bridge` boots the launcher this checkout SHIPS. It cannot speak for the string
// pi's provider actually execs, and only that second one reaches a live ACP session.
// 2026-08-19 measured the difference at full price: a relocated `~/.local/bin/entwurf-bridge`
// symlink into a pnpm cmd-shim (basedir derived from $0, so not relocatable) exited 127, the
// bundled bridge never booted, and the model had no `mcp__entwurf-bridge__*` tool — while
// `command -v` answered yes throughout. #81 had already built the leaf that settles this in
// under a second, and doctor-pi-provider consumes it; it was simply never a step, so the
// verdict surfaced sixteen LIVE steps later at smoke-acp-bundled-mcp-live.
// Pinned here because the step is CHEAP and therefore easy to drop again "to speed the gate up":
// its whole value is the position, so both the position and the classifier arm are asserted.
// run_step, not run_live_step — this doctor is not LIVE-gated and never emits 97, so a SKIP arm
// would describe a prerequisite it cannot have.
// ===========================================================================
{
	const runSh = readFileSync(join(REPO_DIR, "run.sh"), "utf8");
	const gateBody = runSh.slice(runSh.indexOf("release_gate() {"), runSh.indexOf("# 5. Summary"));
	const verify = readFileSync(join(REPO_DIR, "VERIFY.md"), "utf8");
	const STEP =
		'run_step "doctor-pi-provider (#81: the operator\'s CONFIGURED bridge invocation actually boots)" gate bash "$self" doctor-pi-provider';
	const doctorSteps = gateBody.split("\n").filter((l) => l.includes('"$self" doctor-pi-provider'));
	const gaps: string[] = [];
	if (doctorSteps.length !== 1)
		gaps.push(`release_gate runs doctor-pi-provider ${doctorSteps.length}x (need exactly one MUST step)`);
	if (doctorSteps.length === 1 && doctorSteps[0]?.trim() !== STEP)
		gaps.push(`the doctor step is not the exact pinned invocation (got: ${doctorSteps[0]?.trim()})`);
	if (doctorSteps.length === 1 && doctorSteps[0]?.includes("run_live_step"))
		gaps.push("the doctor step goes through run_live_step, inventing a SKIP arm for a doctor that never emits 97");
	// Position is the point: a cheap probe scheduled after the expensive tier proves nothing new.
	const doctorAt = gateBody.indexOf('"$self" doctor-pi-provider');
	// Anchored on the step KEYWORD, not the bare name: prose above this step already discusses
	// smoke-acp-bundled-mcp-live by name, and a needle that a comment can satisfy would drag the
	// boundary backwards and fail an ordering that is actually fine.
	const firstLiveAt = gateBody.indexOf('run_live_step "smoke-acp-');
	if (doctorAt >= 0 && firstLiveAt >= 0 && doctorAt > firstLiveAt)
		gaps.push("the doctor step runs AFTER the ACP LIVE tier — the fail-fast position that motivates it is gone");
	if (!verify.includes("doctor-pi-provider"))
		gaps.push("VERIFY.md does not name doctor-pi-provider in the MUST tier at all");
	if (!verify.includes("the invocation the operator's pi provider actually EXECS"))
		gaps.push("VERIFY.md no longer states WHICH invocation this step proves (ships vs execs)");
	assert.ok(
		gaps.length === 0,
		"[QK:PI-DOCTOR-IS-RELEASE-MUST] the operator's configured bridge invocation must be booted as a release-gate " +
			"MUST exactly once, through run_step (no SKIP arm — this doctor never emits 97), positioned BEFORE the ACP " +
			"LIVE tier, with VERIFY naming it and keeping 'what this checkout ships' apart from 'what the provider execs' " +
			"— drop any of those and the #81 127-class defect goes back to costing sixteen LIVE steps to discover. " +
			`Broken: ${gaps.join("; ")}`,
	);
}

console.log(
	"[check-release-gate-outcomes] ok — STEP OUTCOME protocol: one skip exit code shared by the shell and TS halves " +
		`(${LIVE_SKIP_EXIT}, clear of the per-tool 0..4 and shell 126+ bands), classifier maps 0→PASS / skip→SKIP / ` +
		"everything else→FAIL (never rounding a skip up), `--cut` refuses a MUST SKIP while a bare diagnostic run stays " +
		"exit 0, no LIVE smoke still carries the pre-P1 exit-0 skip shape, and both real skip surfaces were INVOKED and " +
		"observed to propagate the code: a smoke with LIVE unset (through run_ts, with its operator-readable marker) and " +
		"a run.sh wrapper declining its own prerequisite (including the measured LIVE=1 no-cortex-connection cell); and every " +
		"LIVE smoke is either wired into release_gate or excluded by a sentence the docs still carry; and the moved " +
		"check-gate-qualification stays reachable on its owners (absent from the default chain, exactly once in CI, " +
		"exactly once as a release-gate MUST step) and the CI step qualifies the FULL floor, which runs before it, " +
		"while the exact-SHA release oracle requires that BODY step to have concluded success at the release SHA, " +
		"and the CI filter that decides when that body runs covers every mutant subject and still runs it for all " +
		"five historical reds; and " +
		"every gate a committed mutant names is itself inside check:full or states its exclusion in prose an operator " +
		"reads; and the CI push trigger is filtered to branch refs, so a release tag creates no duplicate run; and " +
		"the operator's CONFIGURED bridge invocation is booted exactly once through run_step, before the ACP LIVE tier",
);
