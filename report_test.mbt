///|
test "render_markdown_report outputs deterministic single-case report" {
  let baseline : @downstream-regression.Trial = {
    directory: "/tmp/ev/baseline",
    downstream: "moonbitlang/moonback@0.3.0",
    dependency: "moonbitlang/async@0.21.0",
    exit_code: 0,
    counts: Some({ total: 89, passed: 89, failed: 0, skipped: 0, }),
    failures: Map([]),
    compiler_errors: [],
    resolutions: Map([
      ("moonbitlang/async", ["moonbitlang/async@0.21.0"]),
      ("moonbitlang/x", ["moonbitlang/x@0.4.1"]),
    ]),
  }
  let candidate : @downstream-regression.Trial = {
    directory: "/tmp/ev/candidate",
    downstream: "moonbitlang/moonback@0.3.0",
    dependency: "moonbitlang/async@0.22.0",
    exit_code: 1,
    counts: Some({ total: 89, passed: 88, failed: 1, skipped: 0, }),
    failures: Map([("moonback / server_test.mbt / close idle", "TaskCancelled")]),
    compiler_errors: [],
    resolutions: Map([
      ("moonbitlang/async", ["moonbitlang/async@0.22.0"]),
      ("moonbitlang/x", ["moonbitlang/x@0.4.2"]),
    ]),
  }
  let comparison = @downstream-regression.compare_trials(
    baseline, candidate, "moonbitlang/async", "wasm", "/tmp/ev",
  )
  let md = @downstream-regression.render_markdown_report(
    comparison,
    toolchain="moon 0.1.20261104\nmoonc v0.10.20",
  )
  inspect(
    md,
    content=(
      #|# Downstream Regression Report
      #|
      #|- **Status**: `new_test_failure` (exit code `1`)
      #|- **Downstream**: `moonbitlang/moonback@0.3.0`
      #|- **Dependency**: `moonbitlang/async@0.21.0` -> `moonbitlang/async@0.22.0`
      #|- **Target**: `wasm`
      #|- **Toolchain**: `moon 0.1.20261104`
      #|- **Evidence**: `/tmp/ev`
      #|
      #|## Summary
      #|
      #|| Variant | Dependency | Exit Code | Passed / Total | Failed | Skipped |
      #|| --- | --- | --- | --- | --- | --- |
      #|| baseline | `moonbitlang/async@0.21.0` | `0` | 89/89 | 0 | 0 |
      #|| candidate | `moonbitlang/async@0.22.0` | `1` | 88/89 | 1 | 0 |
      #|
      #|## New Failures (1)
      #|
      #|- `moonback / server_test.mbt / close idle`: TaskCancelled
      #|
      #|## Other Dependency Changes (1)
      #|
      #|| Dependency | Baseline | Candidate |
      #|| --- | --- | --- |
      #|| `moonbitlang/x` | `moonbitlang/x@0.4.1` | `moonbitlang/x@0.4.2` |
      #|
    ),
  )
}

///|
test "render_batch_markdown renders summary table for CI step summaries" {
  let outcome : @downstream-regression.BatchOutcome = {
    evidence: "/tmp/batch",
    cases: [
      {
        id: "moonback-async-cancellation",
        status: Some("new_test_failure"),
        exit_code: 1,
        baseline_counts: Some({ total: 89, passed: 89, failed: 0, skipped: 0, }),
        candidate_counts: Some({ total: 89, passed: 83, failed: 6, skipped: 0, }),
        new_failure_count: 6,
        compiler_error_count: 0,
        evidence: "/tmp/batch/case-1",
        error: None,
      },
      {
        id: "moonyacc-async-control",
        status: Some("pass"),
        exit_code: 0,
        baseline_counts: Some({ total: 74, passed: 74, failed: 0, skipped: 0, }),
        candidate_counts: Some({ total: 74, passed: 74, failed: 0, skipped: 0, }),
        new_failure_count: 0,
        compiler_error_count: 0,
        evidence: "/tmp/batch/case-2",
        error: None,
      },
    ],
  }
  let md = @downstream-regression.render_batch_markdown(outcome)
  inspect(
    md,
    content=(
      #|# Downstream Regression Batch Summary
      #|
      #|- **Cases**: 2 | **Exit Code**: `1`
      #|- **Evidence**: `/tmp/batch`
      #|
      #|| Case | Status | Exit | Baseline | Candidate | New Failures | Compile Errors | Notes |
      #|| --- | --- | --- | --- | --- | --- | --- | --- |
      #|| `moonback-async-cancellation` | `new_test_failure` | `1` | 89/89 | 83/89 | 6 | 0 | - |
      #|| `moonyacc-async-control` | `pass` | `0` | 74/74 | 74/74 | 0 | 0 | - |
      #|
    ),
  )
}
