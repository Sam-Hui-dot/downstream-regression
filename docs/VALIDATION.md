# Validation Scope and Source Accounting

## Verification Matrix

`downstream-regression` is verified on two independent layers so reviewers can test core behavior without external repositories, while also reproducing real historical MoonBit ecosystem upgrades:

1. **Zero-dependency multi-target unit tests (`moon test`)**
   - Covered targets: `wasm`, `wasm-gc`, `js`, `native` (all with `--deny-warn`).
   - `parser_test.mbt`: `moon test` summary counts (including `skipped`, ANSI escape stripping, malformed/inconsistent summary rejection), failure line parsing (Windows paths, colons in messages), 4-digit compiler error extraction, and `moon tree` root/direct/inventory/diff parsing.
   - `manifest_test.mbt`: exact single-occurrence rewriting for both `moon.mod` (`"dep@ver"`) and `moon.mod.json` (`"dep": "ver"`), prefix collision protection, and rejection of missing/duplicate/invalid manifests.
   - `compare_test.mbt`: all 9 `Comparison.status` classifications and CLI exit-code mappings, `--out` option parsing and rejection, plus batch JSON plan validation (duplicate IDs, invalid targets, path traversal rejection).
   - `report_test.mbt`: deterministic Markdown snapshot tests (`inspect`) for both single-case reports (`report.md`) and batch summaries (`batch.md`).

2. **Independent consumer check**
   - CI creates a separate temporary MoonBit module importing `Sam-Hui-dot/downstream-regression` and runs `moon test` on `js` and `wasm` targets against the public root library API.
   - Release verification additionally installs `Sam-Hui-dot/downstream-regression/cmd/main@0.2.0` via `moon install` into a standalone directory and runs both `--help` and `snapshot` against `examples/compile-regression`.

3. **Real historical ecosystem comparisons**
   - Executed in CI with SHA-256 verified Windows toolchain archives (`moon 0.1.20261104`, `moonc 0.10.20+65efd5b93`, `MOON_WORK=off`):
     - **MoonBack `ccb19d7`** (`moonbitlang/async` `0.21.0` -> `0.22.0`, `wasm`): `89/89` -> `83/89`, `status = "new_test_failure"`, 6 new failures.
     - **moonyacc `0adc773`** (`moonbitlang/async` `0.20.3` -> `0.22.4`, `wasm`): `74/74` -> `74/74`, `status = "pass"`.
     - **`examples/compile-regression`** (`moonbitlang/async` `0.22.0` -> `0.21.0`, `wasm`): baseline `1/1` passed, candidate fails with `Error: [4021]`, `status = "candidate_compile_failure"`.
   - Historical dependency archives require `moonc 0.10.20+65efd5b93`; newer compiler releases can fail while compiling those pinned historical dependencies before tests run.

## Known Boundaries

- Parses English `moon test` and `moon tree` output formats.
- Rewrites a single pinned direct registry dependency (`moon.mod` or `moon.mod.json`); path/workspace overrides and transitive-only pins are rejected explicitly rather than edited implicitly.
- Executes downstream project build/test commands in isolated directories; run only on trusted source repositories.
- Log parsing caps individual captured logs at 16 MiB and applies per-step timeouts (30s version check, 60s `moon tree`, 600s `moon test`).

## Source Accounting

Non-test MoonBit source lines are counted across root library files (`*.mbt` excluding `*_test.mbt`) and CLI source files (`cmd/main/*.mbt` excluding `*_test.mbt`), ignoring blank lines and `//` comment lines. Generated `.mbti` files and example fixtures under `examples/` are excluded from the non-test source count.
