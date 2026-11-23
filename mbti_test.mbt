///|
test "diff_mbti detects removed functions, signature changes, visibility narrowing, and additive changes" {
  let baseline_mbti =
    #|// Generated using `moon info`, DON'T EDIT IT
    #|package "demo/lib"
    #|
    #|import {
    #|  "moonbitlang/core/json",
    #|}
    #|
    #|// Values
    #|pub fn handle_cancellation(Int) -> Unit
    #|
    #|pub fn parse(String) -> Int
    #|
    #|// Errors
    #|pub(all) suberror ParseError {
    #|  Empty
    #|  BadToken(String)
    #|}
    #|
    #|// Types and methods
    #|pub(all) struct Config {
    #|  host : String
    #|  port : Int
    #|}
    #|pub fn Config::connect(Self) -> Bool
    #|pub impl Show for Config
    #|
    #|pub struct Opaque {
    #|  // private fields
    #|}
  let candidate_mbti =
    #|// Generated using `moon info`, DON'T EDIT IT
    #|package "demo/lib"
    #|
    #|// Values
    #|pub fn parse(String, strict? : Bool) -> Int
    #|
    #|pub fn format(Int) -> String
    #|
    #|// Errors
    #|pub(all) suberror ParseError {
    #|  Empty
    #|  BadToken(String)
    #|  Timeout
    #|}
    #|
    #|// Types and methods
    #|pub struct Config {
    #|  host : String
    #|  port : Int
    #|  tls : Bool
    #|}
    #|pub fn Config::connect(Self) -> Bool
    #|
    #|pub(all) struct Opaque {
    #|  id : Int
    #|}

  let report = @downstream-regression.diff_mbti(baseline_mbti, candidate_mbti)
  assert_eq(report.package_name, "demo/lib")
  assert_eq(report.compatible, false)
  // Breaking: removed handle_cancellation, changed parse sig, ParseError.Timeout added,
  // Config visibility narrowed pub(all)->pub, removed pub impl Show for Config, Opaque.id added on pub(all)
  assert_true(report.breaking_count >= 5)
  // Additive: added format, Opaque visibility widened, Config.tls on pub struct
  assert_true(report.additive_count >= 2)

  let md = @downstream-regression.render_mbti_diff_markdown(report)
  assert_true(
    md.contains("# MoonBit Public API (`.mbti`) Compatibility Report"),
  )
  assert_true(md.contains("`handle_cancellation`"))
  assert_true(md.contains("`BREAKING`"))
}

///|
test "diff_mbti reports compatible when only additive APIs are introduced" {
  let old_mbti =
    #|package "demo/clean"
    #|
    #|// Values
    #|pub fn run(String) -> Int
  let new_mbti =
    #|package "demo/clean"
    #|
    #|// Values
    #|pub fn run(String) -> Int
    #|pub fn run_v2(String, Int) -> Int

  let report = @downstream-regression.diff_mbti(old_mbti, new_mbti)
  assert_eq(report.compatible, true)
  assert_eq(report.breaking_count, 0)
  assert_eq(report.additive_count, 1)
  let text = @downstream-regression.render_mbti_diff_text(report)
  assert_true(text.contains("MBTI Diff [COMPATIBLE]"))
}

///|
test "render_html_report and render_batch_html produce self-contained interactive HTML" {
  let base : @downstream-regression.Trial = {
    directory: "/b",
    downstream: "moonbitlang/moonback@0.3.0",
    dependency: "moonbitlang/async@0.21.0",
    exit_code: 0,
    counts: Some({ total: 89, passed: 89, failed: 0, skipped: 0, }),
    failures: Map([]),
    compiler_errors: [],
    resolutions: Map([]),
  }
  let cand : @downstream-regression.Trial = {
    directory: "/c",
    downstream: "moonbitlang/moonback@0.3.0",
    dependency: "moonbitlang/async@0.22.0",
    exit_code: 1,
    counts: Some({ total: 89, passed: 88, failed: 1, skipped: 0, }),
    failures: Map([("moonback / conn_test.mbt / idle", "TaskCancelled")]),
    compiler_errors: [],
    resolutions: Map([]),
  }
  let cmp = @downstream-regression.compare_trials(
    base, cand, "moonbitlang/async", "wasm", "/tmp/ev",
  )
  let html = @downstream-regression.render_html_report(
    cmp,
    toolchain="moon 0.1.20261104",
  )
  assert_true(html.contains("<!doctype html>"))
  assert_true(html.contains("moonbitlang/moonback@0.3.0"))
  assert_true(html.contains("TaskCancelled"))
  assert_true(html.contains("new_test_failure (exit 1)"))

  let batch : @downstream-regression.BatchOutcome = {
    evidence: "/tmp/batch",
    cases: [
      {
        id: "moonback",
        status: Some("new_test_failure"),
        exit_code: 1,
        baseline_counts: base.counts,
        candidate_counts: cand.counts,
        new_failure_count: 1,
        compiler_error_count: 0,
        evidence: "/tmp/batch/case-1",
        error: None,
      },
    ],
  }
  let batch_html = @downstream-regression.render_batch_html(batch)
  assert_true(batch_html.contains("Downstream Regression Batch Summary"))
  assert_true(batch_html.contains("Filter by case id..."))
}

///|
test "parse_mbti separates Type::method from top-level values" {
  let old_mbti =
    #|package "demo/pkg"
    #|pub fn top(Int) -> Int
    #|pub struct Box {
    #|  v : Int
    #|}
    #|pub fn Box::get(Self) -> Int
    #|
  let new_mbti =
    #|package "demo/pkg"
    #|pub fn top(Int) -> Int
    #|pub struct Box {
    #|  v : Int
    #|}
    #|pub fn Box::get(Self) -> Int
    #|pub fn Box::set(Self, Int) -> Unit
    #|
  let report = @downstream-regression.diff_mbti(old_mbti, new_mbti)
  assert_eq(report.breaking_count, 0)
  assert_eq(report.additive_count, 1)
  assert_eq(report.changes[0].category, "method")
  assert_eq(report.changes[0].symbol, "Box::set")
}
