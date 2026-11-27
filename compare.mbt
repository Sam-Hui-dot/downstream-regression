///|
/// Extract an optional `--out <DIR>` flag from CLI arguments while preserving positional order.
pub fn extract_out_option(
  args : Array[String],
) -> (String?, Array[String]) raise StudyError {
  let mut out_dir : String? = None
  let positional : Array[String] = []
  let len = args.length()
  let mut i = 0
  while i < len {
    if args[i] == "--out" {
      guard out_dir is None else {
        raise InvalidInput("--out may only be specified once")
      }
      guard i + 1 < len else {
        raise InvalidInput("--out requires a directory path")
      }
      out_dir = Some(args[i + 1])
      i += 2
    } else {
      positional.push(args[i])
      i += 1
    }
  }
  (out_dir, positional)
}

///|
/// Validate that a MoonBit test target is one of the supported values.
pub fn validate_target(target : String) -> String raise StudyError {
  guard target is ("wasm" | "native" | "wasm-gc" | "js") else {
    raise InvalidInput("unsupported target: \{target}")
  }
  target
}

///|
/// Validate that a snapshot module path is repository-relative and free of traversal components.
pub fn validate_module_dir(module_dir : String) -> Unit raise StudyError {
  guard !module_dir.has_prefix("/") &&
    !module_dir.contains("\\") &&
    !module_dir.contains(":") else {
    raise InvalidInput("MODULE_DIR must be repository-relative")
  }
  for component in module_dir.split("/") {
    guard component != ".." && component != "" else {
      raise InvalidInput("MODULE_DIR contains an invalid path component")
    }
  }
}

///|
/// Return true when a trial's exit code, test counts, and parsed failure map are mutually consistent.
pub fn is_comparable(trial : Trial) -> Bool {
  match trial.counts {
    None => false
    Some(counts) =>
      counts.failed == trial.failures.length() &&
      (counts.failed == 0) == (trial.exit_code == 0)
  }
}

///|
/// Compare baseline and candidate trials and classify the regression outcome.
pub fn compare_trials(
  baseline : Trial,
  candidate : Trial,
  dependency : String,
  target : String,
  evidence : String,
) -> Comparison {
  let new_failures : Map[String, String] = Map([])
  let fixed_failures : Map[String, String] = Map([])
  let changed_failure_messages : Map[String, String] = Map([])
  let baseline_comparable = is_comparable(baseline)
  let candidate_comparable = is_comparable(candidate)
  if baseline_comparable && candidate_comparable {
    for name, message in candidate.failures {
      match baseline.failures.get(name) {
        None => new_failures[name] = message
        Some(previous) =>
          if previous != message {
            changed_failure_messages[name] = message
          }
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
    (Some(before), None) if baseline.exit_code == 0 &&
      before.skipped == 0 &&
      candidate.exit_code != 0 &&
      !candidate.compiler_errors.is_empty() => "candidate_compile_failure"
    _ if !candidate_comparable => "candidate_inconclusive"
    _ if !new_failures.is_empty() => "new_test_failure"
    _ if !changed_failure_messages.is_empty() => "failure_changed"
    _ if candidate.exit_code != 0 => "candidate_failing"
    _ if baseline.exit_code != 0 => "baseline_failing"
    (Some(a), Some(b)) if a.total != b.total || a.skipped != b.skipped =>
      "test_summary_changed"
    _ => "pass"
  }
  {
    status,
    baseline,
    candidate,
    new_failures,
    fixed_failures,
    changed_failure_messages,
    other_dependency_changes: diff_resolutions(
      baseline.resolutions,
      candidate.resolutions,
      dependency,
    ),
    target,
    evidence,
  }
}

///|
/// Map a comparison status string to the CLI exit code (`0` pass, `1` regression, `2` inconclusive/error).
pub fn exit_code_for_status(status : String) -> Int32 {
  match status {
    "pass" => 0
    "new_test_failure" | "failure_changed" | "candidate_compile_failure" => 1
    _ => 2
  }
}

///|
fn required_plan_field(
  fields : Map[String, Json],
  key : String,
  position : Int32,
) -> String raise StudyError {
  guard fields.get(key) is Some(String(value)) && !value.trim().is_empty() else {
    raise InvalidInput("case \{position}: \{key} must be a nonempty string")
  }
  value
}

///|
/// Parse and validate a batch comparison JSON array into typed `BatchCase` entries.
pub fn parse_batch_plan(raw : Json) -> Array[BatchCase] raise StudyError {
  guard raw is Array(entries) && !entries.is_empty() else {
    raise InvalidInput("plan must be a nonempty JSON array")
  }
  let cases : Array[BatchCase] = []
  let seen : Map[String, Bool] = Map([])
  for index, entry in entries {
    let position = index + 1
    guard entry is Object(fields) else {
      raise InvalidInput("case \{position} must be an object")
    }
    let id = required_plan_field(fields, "id", position)
    guard !seen.contains(id) else {
      raise InvalidInput("duplicate case id: \{id}")
    }
    seen[id] = true
    let repo = required_plan_field(fields, "repo", position)
    let revision = required_plan_field(fields, "revision", position)
    let module_dir = required_plan_field(fields, "module", position)
    validate_module_dir(module_dir)
    let dependency = required_plan_field(fields, "dependency", position)
    let baseline = required_plan_field(fields, "baseline", position)
    let candidate = required_plan_field(fields, "candidate", position)
    guard baseline != candidate else {
      raise InvalidInput(
        "case \{position}: baseline and candidate versions must differ",
      )
    }
    let target = if fields.contains("target") {
      validate_target(required_plan_field(fields, "target", position))
    } else {
      "wasm"
    }
    cases.push({
      id,
      repo,
      revision,
      module_dir,
      dependency,
      baseline,
      candidate,
      target,
    })
  }
  cases
}
