///|
test "parse_test_counts handles normal, skipped, ansi, and repeated summaries" {
  let log = "\u{1b}[32mrunning tests...\u{1b}[0m\nTotal tests: 10, passed: 9, failed: 1.\nTotal tests: 89, passed: 83, failed: 6."
  assert_eq(
    @downstream-regression.parse_test_counts(log),
    Some({ total: 89, passed: 83, failed: 6, skipped: 0, }),
  )

  let with_skipped = "Total tests: 12, passed: 10, failed: 1, skipped: 1."
  assert_eq(
    @downstream-regression.parse_test_counts(with_skipped),
    Some({ total: 12, passed: 10, failed: 1, skipped: 1, }),
  )
}

///|
test "parse_test_counts rejects inconsistent or duplicate fields" {
  assert_eq(
    @downstream-regression.parse_test_counts(
      "Total tests: 10, passed: 8, failed: 1.",
    ),
    None,
  )
  assert_eq(
    @downstream-regression.parse_test_counts(
      "Total tests: 0, passed: 0, failed: 0.",
    ),
    None,
  )
  assert_eq(
    @downstream-regression.parse_test_counts(
      "Total tests: 5, passed: 5, passed: 5, failed: 0.",
    ),
    None,
  )
  assert_eq(@downstream-regression.parse_test_counts("no summary here"), None)
}

///|
test "parse_failure_records extracts package, file without line, test name, and message" {
  let log = "[moonbitlang/moonback] test C:/src/server_test.mbt:142 (\"idle connection close\") failed: TaskCancelled: socket closed\r\n" +
    "\u{1b}[31m[moonbitlang/moonback/http] test pool_test.mbt:88 (\"reuse: keep-alive\") failed: timeout after 5000ms\u{1b}[0m\n" +
    "not a test failure line"
  let parsed = @downstream-regression.parse_failure_records(log)
  assert_eq(parsed.length(), 2)
  assert_eq(
    parsed.get(
      "moonbitlang/moonback / C:/src/server_test.mbt / idle connection close",
    ),
    Some("TaskCancelled: socket closed"),
  )
  assert_eq(
    parsed.get("moonbitlang/moonback/http / pool_test.mbt / reuse: keep-alive"),
    Some("timeout after 5000ms"),
  )
}

///|
test "parse_compiler_errors captures 4-digit diagnostic codes and ignores malformed lines" {
  let log =
    #|Error: [4021] The value handle_cancellation is unbound.
    #|Error: [4014] Type mismatch
    #|Error: [12] Not four digits
    #|Error: [abcd] Not numeric
    #|Warning: [0001] Unused variable
  assert_eq(@downstream-regression.parse_compiler_errors(log), [
    "Error: [4021] The value handle_cancellation is unbound.", "Error: [4014] Type mismatch",
  ])
}

///|
test "parse_tree helpers extract root, direct versions, full inventory, and diffs" {
  let baseline_tree =
    #|moonbitlang/moonback@0.3.0 (local D:/cases/base/moonback)
    #|├─ moonbitlang/async -> moonbitlang/async@0.21.0
    #|│  └─ moonbitlang/x -> moonbitlang/x@0.4.1
    #|└─ moonbitlang/helper -> moonbitlang/helper@0.1.0 (local D:/cases/base/helper)
  let candidate_tree =
    #|moonbitlang/moonback@0.3.0 (local D:/cases/cand/moonback)
    #|├─ moonbitlang/async -> moonbitlang/async@0.22.0
    #|│  └─ moonbitlang/x -> moonbitlang/x@0.4.2
    #|└─ moonbitlang/helper -> moonbitlang/helper@0.1.0 (local D:/cases/cand/helper)

  assert_eq(
    @downstream-regression.parse_tree_root(baseline_tree),
    "moonbitlang/moonback@0.3.0",
  )
  assert_eq(
    @downstream-regression.parse_direct_versions(
      baseline_tree, "moonbitlang/async",
    ),
    ["moonbitlang/async@0.21.0"],
  )
  // Transitive edges must not be reported as direct edges.
  assert_eq(
    @downstream-regression.parse_direct_versions(baseline_tree, "moonbitlang/x"),
    [],
  )

  let base_inv = @downstream-regression.parse_dependency_inventory(
    baseline_tree,
  )
  let cand_inv = @downstream-regression.parse_dependency_inventory(
    candidate_tree,
  )
  // Local path differences must normalize to "(local)" and not trigger spurious diffs.
  assert_eq(
    base_inv.get("moonbitlang/helper"),
    Some(["moonbitlang/helper@0.1.0 (local)"]),
  )
  assert_eq(
    @downstream-regression.diff_resolutions(
      base_inv, cand_inv, "moonbitlang/async",
    ),
    [
      {
        requested: "moonbitlang/x",
        baseline: ["moonbitlang/x@0.4.1"],
        candidate: ["moonbitlang/x@0.4.2"],
      },
    ],
  )
}
