///|
fn format_counts_compact(counts : TestCounts?) -> String {
  match counts {
    None => "-"
    Some(c) =>
      if c.skipped > 0 {
        "\{c.passed}/\{c.total} (failed \{c.failed}, skipped \{c.skipped})"
      } else {
        "\{c.passed}/\{c.total}"
      }
  }
}

///|
fn escape_md_cell(text : String) -> String {
  text
  .replace_all(old="|", new="\\|")
  .replace_all(old="\r", new="")
  .replace_all(old="\n", new=" ")
}

///|
fn sorted_keys(map : Map[String, String]) -> Array[String] {
  let keys : Array[String] = []
  for key, _ in map {
    keys.push(key)
  }
  keys.sort()
  keys
}

///|
fn write_failure_section(
  out : StringBuilder,
  heading : String,
  failures : Map[String, String],
) -> Unit {
  if failures.is_empty() {
    return
  }
  out.write_string("\n## \{heading} (\{failures.length()})\n\n")
  for key in sorted_keys(failures) {
    let message = failures.get(key).unwrap_or("")
    out.write_string("- `\{key}`: \{message}\n")
  }
}

///|
/// Render a deterministic Markdown report for a single downstream comparison.
pub fn render_markdown_report(
  report : Comparison,
  toolchain~ : String = "",
  api_diffs~ : Array[MbtiDiffReport] = [],
  root_causes~ : Array[RootCauseHint] = [],
) -> String {
  let out = StringBuilder()
  let code = exit_code_for_status(report.status)
  out.write_string("# Downstream Regression Report\n\n")
  out.write_string("- **Status**: `\{report.status}` (exit code `\{code}`)\n")
  out.write_string("- **Downstream**: `\{report.baseline.downstream}`\n")
  out.write_string(
    "- **Dependency**: `\{report.baseline.dependency}` -> `\{report.candidate.dependency}`\n",
  )
  out.write_string("- **Target**: `\{report.target}`\n")
  if !toolchain.trim().is_empty() {
    let first_line = match toolchain.trim().split_once("\n") {
      Some((head, _)) => head.trim().to_owned()
      None => toolchain.trim().to_owned()
    }
    out.write_string("- **Toolchain**: `\{first_line}`\n")
  }
  out.write_string("- **Evidence**: `\{report.evidence}`\n\n")

  out.write_string("## Summary\n\n")
  out.write_string(
    "| Variant | Dependency | Exit Code | Passed / Total | Failed | Skipped |\n",
  )
  out.write_string("| --- | --- | --- | --- | --- | --- |\n")
  for pair in [("baseline", report.baseline), ("candidate", report.candidate)] {
    let (label, trial) = pair
    let (passed_total, failed, skipped) = match trial.counts {
      Some(c) => ("\{c.passed}/\{c.total}", "\{c.failed}", "\{c.skipped}")
      None => ("-", "-", "-")
    }
    out.write_string(
      "| \{label} | `\{escape_md_cell(trial.dependency)}` | `\{trial.exit_code}` | \{passed_total} | \{failed} | \{skipped} |\n",
    )
  }

  write_failure_section(out, "New Failures", report.new_failures)
  write_failure_section(
    out,
    "Changed Failure Messages",
    report.changed_failure_messages,
  )
  write_failure_section(out, "Fixed Failures", report.fixed_failures)

  if !report.candidate.compiler_errors.is_empty() {
    out.write_string(
      "\n## Candidate Compiler Errors (\{report.candidate.compiler_errors.length()})\n\n",
    )
    for err in report.candidate.compiler_errors {
      out.write_string("- `\{err}`\n")
    }
  }

  if !report.other_dependency_changes.is_empty() {
    out.write_string(
      "\n## Other Dependency Changes (\{report.other_dependency_changes.length()})\n\n",
    )
    out.write_string("| Dependency | Baseline | Candidate |\n")
    out.write_string("| --- | --- | --- |\n")
    for change in report.other_dependency_changes {
      let before = change.baseline.join(", ")
      let after = change.candidate.join(", ")
      out.write_string(
        "| `\{escape_md_cell(change.requested)}` | `\{escape_md_cell(before)}` | `\{escape_md_cell(after)}` |\n",
      )
    }
  }

  if !root_causes.is_empty() {
    out.write_string(
      "\n## Suspected Root-Cause Correlation (\{root_causes.length()})\n\n",
    )
    out.write_string(
      "| Upstream Package | Breaking Symbol | Change | Evidence Kind | Matched Diagnostic |\n",
    )
    out.write_string("| --- | --- | --- | --- | --- |\n")
    for hint in root_causes {
      out.write_string(
        "| `\{escape_md_cell(hint.package_name)}` | `\{escape_md_cell(hint.symbol)}` | \{escape_md_cell(hint.change_detail)} | `\{escape_md_cell(hint.evidence_kind)}` | \{escape_md_cell(hint.evidence_excerpt)} |\n",
      )
    }
  }

  let breaking_diffs : Array[(String, MbtiChange)] = []
  for diff in api_diffs {
    for ch in diff.changes {
      if ch.severity == "breaking" {
        breaking_diffs.push((diff.package_name, ch))
      }
    }
  }
  if !breaking_diffs.is_empty() {
    out.write_string(
      "\n## Upstream API Breaking Changes (\{breaking_diffs.length()})\n\n",
    )
    out.write_string("| Package | Category | Symbol | Detail |\n")
    out.write_string("| --- | --- | --- | --- |\n")
    let limit = if breaking_diffs.length() < 30 {
      breaking_diffs.length()
    } else {
      30
    }
    for i in 0..<limit {
      let (pkg, ch) = breaking_diffs[i]
      out.write_string(
        "| `\{escape_md_cell(pkg)}` | `\{escape_md_cell(ch.category)}` | `\{escape_md_cell(ch.symbol)}` | \{escape_md_cell(ch.detail)} |\n",
      )
    }
    if breaking_diffs.length() > limit {
      out.write_string(
        "\n_...and \{breaking_diffs.length() - limit} more breaking API changes (see `api-diff.json`)._\n",
      )
    }
  }

  out.to_string()
}

///|
/// Render a Markdown summary table for a batch regression run (suitable for CI job summaries).
pub fn render_batch_markdown(outcome : BatchOutcome) -> String {
  let out = StringBuilder()
  let mut max_exit = 0
  for item in outcome.cases {
    if item.exit_code > max_exit {
      max_exit = item.exit_code
    }
  }
  out.write_string("# Downstream Regression Batch Summary\n\n")
  out.write_string(
    "- **Cases**: \{outcome.cases.length()} | **Exit Code**: `\{max_exit}`\n",
  )
  out.write_string("- **Evidence**: `\{outcome.evidence}`\n\n")
  out.write_string(
    "| Case | Status | Exit | Baseline | Candidate | New Failures | Compile Errors | Notes |\n",
  )
  out.write_string("| --- | --- | --- | --- | --- | --- | --- | --- |\n")
  for item in outcome.cases {
    let status = match item.status {
      Some(s) => "`\{escape_md_cell(s)}`"
      None => "`error`"
    }
    let notes = match item.error {
      Some(msg) => escape_md_cell(msg)
      None => "-"
    }
    out.write_string(
      "| `\{escape_md_cell(item.id)}` | \{status} | `\{item.exit_code}` | \{format_counts_compact(item.baseline_counts)} | \{format_counts_compact(item.candidate_counts)} | \{item.new_failure_count} | \{item.compiler_error_count} | \{notes} |\n",
    )
  }
  out.to_string()
}
