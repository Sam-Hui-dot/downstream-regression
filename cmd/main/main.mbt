///|
suberror StudyError {
  InvalidInput(String)
  ToolFailed(String)
}

///|
fn error_message(error : Error) -> String {
  match error {
    InvalidInput(message) | ToolFailed(message) => message
    other => other.to_string()
  }
}

///|
struct Variant {
  dir : String
  version : String
  label : String
}

///|
#derive(ToJson)
struct Trial {
  directory : String
  downstream : String
  dependency : String
  exit_code : Int
  counts : TestCounts?
  failures : Map[String, String]
  compiler_errors : Array[String]
  resolutions : Map[String, Array[String]]
}

///|
#derive(ToJson)
struct TestCounts {
  total : Int
  passed : Int
  failed : Int
  skipped : Int
}

///|
fn failure_records(log : String) -> Map[String, String] {
  let records : Map[String, String] = Map([])
  for raw in log.split("\n") {
    let line = raw.trim()
    guard line.has_prefix("[") else { continue }
    guard line.find("] test ") is Some(package_end) else { continue }
    guard line.find(" (\"") is Some(name_start) else { continue }
    guard line.find("\") failed:") is Some(name_end) else { continue }
    let file_start = package_end + 7
    guard file_start <= name_start && name_start + 3 <= name_end else { continue }
    let file_and_line = line[file_start:name_start].to_owned()
    let file = match file_and_line.rev_find(":") {
      Some(pos) => file_and_line[:pos].to_owned()
      None => file_and_line
    }
    let key = "\{line[1:package_end]} / \{file} / \{line[name_start + 3:name_end]}"
    records[key] = line[name_end + 10:].trim().to_owned()
  }
  records
}

///|
fn test_counts(log : String) -> TestCounts? {
  let mut summary = None
  for line in log.split("\n") {
    let trimmed = line.trim()
    if trimmed.has_prefix("Total tests:") {
      summary = parse_counts(trimmed) catch { _ => None }
    }
  }
  summary
}

///|
fn parse_counts(line : StringView) -> TestCounts? raise {
  let counts : Map[String, Int] = Map([])
  for field in line.split(",") {
    guard field.split_once(":") is Some((key, value)) else { return None }
    let name = key.trim().to_owned()
    guard !counts.contains(name) else { return None }
    counts[name] = @string.parse_int(value.trim().trim_end(chars="."))
  }
  guard counts.get("Total tests") is Some(total) else { return None }
  guard counts.get("passed") is Some(passed) else { return None }
  guard counts.get("failed") is Some(failed) else { return None }
  let skipped = counts.get("skipped").unwrap_or(0)
  guard total > 0 && passed >= 0 && failed >= 0 && skipped >= 0 else { return None }
  guard passed.to_int64() + failed.to_int64() + skipped.to_int64() == total.to_int64() else { return None }
  Some({ total, passed, failed, skipped })
}

///|
fn comparable(trial : Trial) -> Bool {
  match trial.counts {
    None => false
    Some(counts) =>
      counts.failed == trial.failures.length() &&
      (counts.failed == 0) == (trial.exit_code == 0)
  }
}

///|
fn compiler_errors(log : String) -> Array[String] {
  let errors : Array[String] = []
  for raw in log.split("\n") {
    let line = raw.trim()
    guard line.has_prefix("Error: [") else { continue }
    guard line[8:].split_once("]") is Some((code, _)) else { continue }
    guard code.length() == 4 && code.to_owned().iter().all(ch => ch >= '0' && ch <= '9') else { continue }
    errors.push(line.to_owned())
  }
  errors
}

///|
fn resolved_direct_versions(tree : String, dependency : String) -> Array[String] {
  let prefix = "\{dependency} -> "
  let versions = []
  for raw in tree.split("\n") {
    let line = raw.trim_end()
    // A direct edge starts at column one. Nested edges start with spaces or │.
    if line.has_prefix("├─ ") || line.has_prefix("└─ ") {
      let edge = line[3:]
      if edge.has_prefix(prefix) {
        versions.push(edge[prefix.length():].to_owned())
      }
    }
  }
  versions
}

///|
async fn execute(
  moon : String,
  variant : Variant,
  dependency : String,
  target : String,
  evidence : String,
) -> Trial {
  let (tree_code, tree) = logged_moon(
    moon,
    ["-C", variant.dir, "tree"],
    "\{evidence}/\{variant.label}-tree.txt",
    timeout_ms=60_000,
  )
  guard tree_code == 0 else {
    raise ToolFailed("\{variant.label}: moon tree exited \{tree_code}")
  }
  let expected = "\{dependency}@\{variant.version}"
  guard resolved_direct_versions(tree, dependency) == [expected] else {
    raise ToolFailed("\{variant.label}: expected exactly one registry edge to \{expected}")
  }
  let downstream = root_coordinate(tree)
  guard !downstream.is_empty() else {
    raise ToolFailed("\{variant.label}: failed to identify downstream module")
  }
  let (exit_code, log) = logged_moon(
    moon,
    ["-C", variant.dir, "test", "--target", target],
    "\{evidence}/\{variant.label}-test.txt",
    timeout_ms=600_000,
  )
  {
    directory: variant.dir,
    downstream,
    dependency: expected,
    exit_code,
    counts: test_counts(log),
    failures: failure_records(log),
    compiler_errors: compiler_errors(log),
    resolutions: inventory(tree),
  }
}

///|
#derive(ToJson)
struct Comparison {
  status : String
  baseline : Trial
  candidate : Trial
  new_failures : Map[String, String]
  fixed_failures : Map[String, String]
  changed_failure_messages : Map[String, String]
  other_dependency_changes : Array[ResolutionChange]
  target : String
  evidence : String
}

///|
fn compare(baseline : Trial, candidate : Trial, dependency : String, target : String, evidence : String) -> Comparison {
  let new_failures : Map[String, String] = Map([])
  let fixed_failures : Map[String, String] = Map([])
  let changed_failure_messages : Map[String, String] = Map([])
  let baseline_comparable = comparable(baseline)
  let candidate_comparable = comparable(candidate)
  if baseline_comparable && candidate_comparable {
    for name, message in candidate.failures {
      match baseline.failures.get(name) {
        None => new_failures[name] = message
        Some(previous) => if previous != message { changed_failure_messages[name] = message }
      }
    }
    for name, message in baseline.failures {
      if !candidate.failures.contains(name) {
        fixed_failures[name] = message
      }
    }
  }
  let status = match (baseline.counts, candidate.counts) {
    _ if !baseline_comparable => "baseline_inconclusive"
    (Some(before), None) if baseline.exit_code == 0 && before.skipped == 0 && candidate.exit_code != 0 && !candidate.compiler_errors.is_empty() => "candidate_compile_failure"
    _ if !candidate_comparable => "candidate_inconclusive"
    _ if !new_failures.is_empty() => "new_test_failure"
    _ if !changed_failure_messages.is_empty() => "failure_changed"
    _ if candidate.exit_code != 0 => "candidate_failing"
    _ if baseline.exit_code != 0 => "baseline_failing"
    (Some(a), Some(b)) if a.total != b.total || a.skipped != b.skipped => "test_summary_changed"
    _ => "pass"
  }
  {
    status,
    baseline,
    candidate,
    new_failures,
    fixed_failures,
    changed_failure_messages,
    other_dependency_changes: resolution_changes(baseline.resolutions, candidate.resolutions, dependency),
    target,
    evidence,
  }
}

///|
let usage : String =
  #|downstream-regression MOON DEPENDENCY BASE_DIR BASE_VERSION CANDIDATE_DIR CANDIDATE_VERSION [TARGET]
  #|downstream-regression snapshot MOON GIT REPO REV MODULE_DIR DEPENDENCY BASE_VERSION CANDIDATE_VERSION [TARGET]
  #|downstream-regression batch MOON GIT PLAN_JSON
  #|TARGET defaults to wasm and can also be native, wasm-gc or js.

///|
fn checked_target(target : String) -> String raise StudyError {
  guard target is ("wasm" | "native" | "wasm-gc" | "js") else {
    raise InvalidInput("unsupported target: \{target}")
  }
  target
}

///|
async fn run_comparison(
  moon : String,
  dependency : String,
  baseline : Variant,
  candidate : Variant,
  target : String,
  evidence : String,
  print_report : Bool,
) -> Int {
  try {
    let (version_status, _) = logged_moon(moon, ["version", "--all"], "\{evidence}/toolchain.txt", timeout_ms=30_000)
    guard version_status == 0 else { raise ToolFailed("moon version --all exited \{version_status}") }
    let left = execute(moon, baseline, dependency, target, evidence)
    let right = execute(moon, candidate, dependency, target, evidence)
    guard left.downstream == right.downstream else {
      raise ToolFailed("downstream module differs: \{left.downstream} vs \{right.downstream}")
    }
    let report = compare(left, right, dependency, target, evidence)
    let json = @json.ToJson::to_json(report).stringify()
    @fs.write_file("\{evidence}/report.json", json)
    if print_report { println(json) }
    match report.status {
      "pass" => 0
      "new_test_failure" | "failure_changed" | "candidate_compile_failure" => 1
      _ => 2
    }
  } catch {
    error => raise ToolFailed("\{error_message(error)}; logs: \{evidence}")
  }
}

///|
async fn git_step(git : String, args : Array[String], log_path : String) -> String {
  let (code, stdout, stderr) = @process.collect_output(git, args)
  @fs.write_file(log_path, "\{stdout.text()}\n\{stderr.text()}")
  guard code == 0 else { raise ToolFailed("git exited \{code}; see \{log_path}") }
  stdout.text().trim().to_owned()
}

///|
async fn snapshot(args : Array[String], evidence : String, print_report : Bool) -> Int {
  guard args.length() == 9 || args.length() == 10 else { raise InvalidInput(usage) }
  let moon = args[1]
  let git = args[2]
  let repository = @fs.realpath(args[3])
  let module_dir = args[5]
  let dependency = args[6]
  let baseline_version = args[7]
  let candidate_version = args[8]
  let target = checked_target(if args.length() == 10 { args[9] } else { "wasm" })
  guard baseline_version != candidate_version else { raise InvalidInput("use two distinct dependency versions") }
  // Only use repository-relative paths, with slash separators on every host.
  guard !module_dir.has_prefix("/") && !module_dir.contains("\\") && !module_dir.contains(":") else {
    raise InvalidInput("MODULE_DIR must be repository-relative")
  }
  for component in module_dir.split("/") {
    guard component != ".." && component != "" else {
      raise InvalidInput("MODULE_DIR contains an invalid path component")
    }
  }
  let revision = git_step(
    git,
    ["-C", repository, "rev-parse", "--verify", "--end-of-options", "\{args[4]}^{commit}"],
    "\{evidence}/revision.txt",
  )
  for label in ["baseline", "candidate"] {
    let checkout = "\{evidence}/\{label}"
    ignore(git_step(git, ["clone", "--local", "--no-hardlinks", "--no-checkout", "--", repository, checkout], "\{evidence}/\{label}-clone.txt"))
    ignore(git_step(git, ["-C", checkout, "checkout", "--detach", revision], "\{evidence}/\{label}-checkout.txt"))
    // Reject symlinks in the module path and manifest before changing the copy.
    let mut path = checkout
    for component in module_dir.split("/") {
      path = "\{path}/\{component}"
      guard @fs.kind(path, follow_symlink=false) is Directory else {
        raise InvalidInput("module path must consist of directories; see \{evidence}")
      }
    }
    guard @fs.kind("\{path}/moon.mod", follow_symlink=false) is Regular else {
      raise InvalidInput("snapshot mode requires a regular moon.mod file; see \{evidence}")
    }
  }
  let baseline_dir = "\{evidence}/baseline/\{module_dir}"
  let candidate_dir = "\{evidence}/candidate/\{module_dir}"
  let manifest_path = "\{candidate_dir}/moon.mod"
  let manifest = @fs.read_file(manifest_path).text()
  let pin = "\"\{dependency}@\{baseline_version}\""
  guard manifest.split(pin).to_array().length() == 2 else {
    raise InvalidInput("expected one occurrence of \{pin}; see \{evidence}")
  }
  let replacement = "\"\{dependency}@\{candidate_version}\""
  @fs.write_file(manifest_path, manifest.replace_all(old=pin, new=replacement))
  run_comparison(
    moon, dependency,
    { dir: baseline_dir, version: baseline_version, label: "baseline" },
    { dir: candidate_dir, version: candidate_version, label: "candidate" },
    target, evidence, print_report,
  )
}

///|
async fn run(args : Array[String]) -> Int {
  match args.get(0) {
    Some("snapshot") => return snapshot(args, @fs.tmpdir(prefix="moon-downstream-"), true)
    Some("batch") => return batch(args)
    _ => ()
  }
  guard args.length() == 6 || args.length() == 7 else { raise InvalidInput(usage) }
  let baseline_dir = @fs.realpath(args[2])
  let candidate_dir = @fs.realpath(args[4])
  guard baseline_dir != candidate_dir else { raise InvalidInput("use two separate project directories") }
  guard args[3] != args[5] else { raise InvalidInput("use two distinct dependency versions") }
  let target = checked_target(if args.length() == 7 { args[6] } else { "wasm" })
  let evidence = @fs.tmpdir(prefix="moon-downstream-")
  run_comparison(
    args[0], args[1],
    { dir: baseline_dir, version: args[3], label: "baseline" },
    { dir: candidate_dir, version: args[5], label: "candidate" },
    target, evidence, true,
  )
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && args[1] == "--help" {
    println(usage)
    return
  }
  let exit_code = try run(args[1:].to_owned()) catch {
    error => { println(error_message(error)); 2 }
  }
  @env.exit(exit_code)
}
