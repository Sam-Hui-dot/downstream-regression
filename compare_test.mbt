///|
fn make_trial(
  dependency : String,
  exit_code : Int32,
  counts : @downstream-regression.TestCounts?,
  failures~ : Map[String, String] = Map([]),
  compiler_errors~ : Array[String] = [],
  resolutions~ : Map[String, Array[String]] = Map([]),
) -> @downstream-regression.Trial {
  {
    directory: "/tmp/case",
    downstream: "demo/app@0.1.0",
    dependency,
    exit_code,
    counts,
    failures,
    compiler_errors,
    resolutions,
  }
}

///|
test "compare_trials classifies all 9 regression statuses and exit codes" {
  let pass_counts : @downstream-regression.TestCounts = {
    total: 10,
    passed: 10,
    failed: 0,
    skipped: 0,
  }
  let one_fail_counts : @downstream-regression.TestCounts = {
    total: 10,
    passed: 9,
    failed: 1,
    skipped: 0,
  }
  let base_ok = make_trial("dep@0.1.0", 0, Some(pass_counts))
  let cand_ok = make_trial("dep@0.2.0", 0, Some(pass_counts))

  // 1. pass
  let r_pass = @downstream-regression.compare_trials(
    base_ok, cand_ok, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_pass.status, "pass")
  assert_eq(@downstream-regression.exit_code_for_status(r_pass.status), 0)

  // 2. new_test_failure
  let cand_new = make_trial(
    "dep@0.2.0",
    1,
    Some(one_fail_counts),
    failures=Map([("pkg / a.mbt / t1", "boom")]),
  )
  let r_new = @downstream-regression.compare_trials(
    base_ok, cand_new, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_new.status, "new_test_failure")
  assert_eq(r_new.new_failures.get("pkg / a.mbt / t1"), Some("boom"))
  assert_eq(@downstream-regression.exit_code_for_status(r_new.status), 1)

  // 3. failure_changed
  let base_fail = make_trial(
    "dep@0.1.0",
    1,
    Some(one_fail_counts),
    failures=Map([("pkg / a.mbt / t1", "old reason")]),
  )
  let cand_changed = make_trial(
    "dep@0.2.0",
    1,
    Some(one_fail_counts),
    failures=Map([("pkg / a.mbt / t1", "new reason")]),
  )
  let r_changed = @downstream-regression.compare_trials(
    base_fail, cand_changed, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_changed.status, "failure_changed")
  assert_eq(
    r_changed.changed_failure_messages.get("pkg / a.mbt / t1"),
    Some("new reason"),
  )
  assert_eq(@downstream-regression.exit_code_for_status(r_changed.status), 1)

  // 4. candidate_compile_failure
  let cand_compile = make_trial("dep@0.2.0", 1, None, compiler_errors=[
    "Error: [4021] unbound",
  ])
  let r_compile = @downstream-regression.compare_trials(
    base_ok, cand_compile, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_compile.status, "candidate_compile_failure")
  assert_eq(@downstream-regression.exit_code_for_status(r_compile.status), 1)

  // 5. candidate_failing (same pre-existing failure)
  let r_same_fail = @downstream-regression.compare_trials(
    base_fail, base_fail, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_same_fail.status, "candidate_failing")
  assert_eq(@downstream-regression.exit_code_for_status(r_same_fail.status), 2)

  // 6. baseline_failing (candidate fixed the baseline failure)
  let r_fixed = @downstream-regression.compare_trials(
    base_fail, cand_ok, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_fixed.status, "baseline_failing")
  assert_eq(r_fixed.fixed_failures.get("pkg / a.mbt / t1"), Some("old reason"))
  assert_eq(@downstream-regression.exit_code_for_status(r_fixed.status), 2)

  // 7. test_summary_changed
  let cand_more = make_trial(
    "dep@0.2.0",
    0,
    Some({ total: 11, passed: 11, failed: 0, skipped: 0, }),
  )
  let r_summary = @downstream-regression.compare_trials(
    base_ok, cand_more, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_summary.status, "test_summary_changed")
  assert_eq(@downstream-regression.exit_code_for_status(r_summary.status), 2)

  // 8. baseline_inconclusive
  let base_bad = make_trial("dep@0.1.0", 0, Some(one_fail_counts))
  let r_base_inc = @downstream-regression.compare_trials(
    base_bad, cand_ok, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_base_inc.status, "baseline_inconclusive")
  assert_eq(@downstream-regression.exit_code_for_status(r_base_inc.status), 2)

  // 9. candidate_inconclusive (candidate failed without summary or compiler errors)
  let cand_abort = make_trial("dep@0.2.0", 2, None)
  let r_cand_inc = @downstream-regression.compare_trials(
    base_ok, cand_abort, "dep", "wasm", "/tmp/e",
  )
  assert_eq(r_cand_inc.status, "candidate_inconclusive")
  assert_eq(@downstream-regression.exit_code_for_status(r_cand_inc.status), 2)
}

///|
test "parse_batch_plan validates valid plans and rejects malformed inputs" {
  let valid_text =
    #|[{"id":"c1","repo":"../r","revision":"HEAD","module":".","dependency":"a/b","baseline":"0.1.0","candidate":"0.2.0"}]
  let valid_json = @json.parse(valid_text)
  let cases = @downstream-regression.parse_batch_plan(valid_json)
  assert_eq(cases.length(), 1)
  assert_eq(cases[0].id, "c1")
  assert_eq(cases[0].target, "wasm")

  // Duplicate case id
  let dup_text =
    #|[{"id":"c1","repo":"r","revision":"HEAD","module":".","dependency":"a/b","baseline":"0.1.0","candidate":"0.2.0"},{"id":"c1","repo":"r","revision":"HEAD","module":".","dependency":"a/b","baseline":"0.1.0","candidate":"0.2.0"}]
  let dup_json = @json.parse(dup_text)
  try @downstream-regression.parse_batch_plan(dup_json) catch {
    InvalidInput(msg) => assert_true(msg.contains("duplicate case id"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("duplicate id must fail")
  }

  // Invalid target
  let bad_target_text =
    #|[{"id":"c1","repo":"r","revision":"HEAD","module":".","dependency":"a/b","baseline":"0.1.0","candidate":"0.2.0","target":"llvm"}]
  let bad_target = @json.parse(bad_target_text)
  try @downstream-regression.parse_batch_plan(bad_target) catch {
    InvalidInput(msg) => assert_true(msg.contains("unsupported target"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("unsupported target must fail")
  }

  // Path traversal in module
  let bad_mod_text =
    #|[{"id":"c1","repo":"r","revision":"HEAD","module":"../escape","dependency":"a/b","baseline":"0.1.0","candidate":"0.2.0"}]
  let bad_mod = @json.parse(bad_mod_text)
  try @downstream-regression.parse_batch_plan(bad_mod) catch {
    InvalidInput(msg) => assert_true(msg.contains("invalid path component"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("path traversal must fail")
  }

  // error_message helper
  assert_eq(
    @downstream-regression.error_message(
      @downstream-regression.tool_failed("boom"),
    ),
    "boom",
  )
}

///|
test "extract_out_option parses leading, trailing, and absent --out flags" {
  let (none_out, plain) = @downstream-regression.extract_out_option([
    "batch", "moon", "git", "p.json",
  ])
  assert_eq(none_out, None)
  assert_eq(plain, ["batch", "moon", "git", "p.json"])

  let (lead_out, lead_rest) = @downstream-regression.extract_out_option([
    "--out", "/tmp/ev", "batch", "moon", "git", "p.json",
  ])
  assert_eq(lead_out, Some("/tmp/ev"))
  assert_eq(lead_rest, ["batch", "moon", "git", "p.json"])

  let (trail_out, trail_rest) = @downstream-regression.extract_out_option([
    "batch", "moon", "git", "p.json", "--out", "/tmp/ev2",
  ])
  assert_eq(trail_out, Some("/tmp/ev2"))
  assert_eq(trail_rest, ["batch", "moon", "git", "p.json"])
}

///|
test "extract_out_option rejects missing value or duplicate flags" {
  try @downstream-regression.extract_out_option(["batch", "--out"]) catch {
    InvalidInput(msg) => assert_true(msg.contains("requires a directory path"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("missing --out argument must fail")
  }

  try
    @downstream-regression.extract_out_option([
      "--out", "a", "--out", "b", "batch",
    ])
  catch {
    InvalidInput(msg) => assert_true(msg.contains("only be specified once"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("duplicate --out must fail")
  }
}
