///|
fn html_escape(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
fn status_badge_class(status : String) -> String {
  match status {
    "pass" => "badge-pass"
    "new_test_failure" | "failure_changed" | "candidate_compile_failure" =>
      "badge-fail"
    _ => "badge-warn"
  }
}

///|
/// Render a self-contained offline interactive HTML report for a single downstream comparison.
pub fn render_html_report(
  report : Comparison,
  toolchain~ : String = "",
  api_diffs~ : Array[MbtiDiffReport] = [],
  root_causes~ : Array[RootCauseHint] = [],
) -> String {
  let code = exit_code_for_status(report.status)
  let badge = status_badge_class(report.status)
  let out = StringBuilder()
  out.write_string(
    "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
  )
  out.write_string(
    "<title>Downstream Regression: \{html_escape(report.baseline.downstream)}</title>\n",
  )
  out.write_string(
    "<style>body{margin:0;padding:24px;font-family:system-ui,-apple-system,sans-serif;background:#f3f4f6;color:#111827} .card{background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:18px;margin-bottom:16px;box-shadow:0 1px 2px rgba(0,0,0,0.04)} .meta{display:flex;gap:16px;flex-wrap:wrap;font-size:13px;color:#4b5563;margin-top:8px} .badge{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:700;font-family:ui-monospace,monospace} .badge-pass{background:#dcfce7;color:#166534} .badge-fail{background:#fee2e2;color:#991b1b} .badge-warn{background:#fef3c7;color:#92400e} table{width:100%;border-collapse:collapse;font-size:13px;margin-top:8px} th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #e5e7eb} th{background:#f9fafb;font-weight:600} code{font-family:ui-monospace,monospace;font-size:12px;background:#f3f4f6;padding:1px 4px;border-radius:4px} details{margin:8px 0;padding:8px 12px;background:#fef2f2;border:1px solid #fecaca;border-radius:6px} summary{cursor:pointer;font-weight:600;font-family:ui-monospace,monospace;font-size:12px} pre{white-space:pre-wrap;font-size:12px;margin:8px 0 0}</style>\n",
  )
  out.write_string("</head>\n<body>\n<div class=\"card\">\n")
  out.write_string(
    "<h1 style=\"margin:0 0 8px;font-size:20px\">Downstream Regression Report <span class=\"badge \{badge}\">\{html_escape(report.status)} (exit \{code})</span></h1>\n",
  )
  out.write_string(
    "<div class=\"meta\"><span>Downstream: <code>\{html_escape(report.baseline.downstream)}</code></span><span>Dependency: <code>\{html_escape(report.baseline.dependency)}</code> &rarr; <code>\{html_escape(report.candidate.dependency)}</code></span><span>Target: <code>\{html_escape(report.target)}</code></span></div>\n",
  )
  if !toolchain.trim().is_empty() {
    let first_line = match toolchain.trim().split_once("\n") {
      Some((h, _)) => h.trim().to_owned()
      None => toolchain.trim().to_owned()
    }
    out.write_string(
      "<div class=\"meta\"><span>Toolchain: <code>\{html_escape(first_line)}</code></span></div>\n",
    )
  }
  out.write_string(
    "<table><thead><tr><th>Variant</th><th>Dependency</th><th>Exit</th><th>Passed / Total</th><th>Failed</th><th>Skipped</th></tr></thead><tbody>\n",
  )
  for pair in [("baseline", report.baseline), ("candidate", report.candidate)] {
    let (label, trial) = pair
    let (pt, fl, sk) = match trial.counts {
      Some(c) => ("\{c.passed}/\{c.total}", "\{c.failed}", "\{c.skipped}")
      None => ("-", "-", "-")
    }
    out.write_string(
      "<tr><td>\{label}</td><td><code>\{html_escape(trial.dependency)}</code></td><td><code>\{trial.exit_code}</code></td><td>\{pt}</td><td>\{fl}</td><td>\{sk}</td></tr>\n",
    )
  }
  out.write_string("</tbody></table>\n</div>\n")

  if !report.new_failures.is_empty() {
    out.write_string(
      "<div class=\"card\"><h2 style=\"margin-top:0;font-size:16px\">New Failures (\{report.new_failures.length()})</h2>\n",
    )
    for key in sorted_keys(report.new_failures) {
      let msg = report.new_failures.get(key).unwrap_or("")
      out.write_string(
        "<details open><summary>\{html_escape(key)}</summary><pre>\{html_escape(msg)}</pre></details>\n",
      )
    }
    out.write_string("</div>\n")
  }

  if !report.candidate.compiler_errors.is_empty() {
    out.write_string(
      "<div class=\"card\"><h2 style=\"margin-top:0;font-size:16px\">Candidate Compiler Diagnostics (\{report.candidate.compiler_errors.length()})</h2><ul>\n",
    )
    for err in report.candidate.compiler_errors {
      out.write_string("<li><code>\{html_escape(err)}</code></li>\n")
    }
    out.write_string("</ul></div>\n")
  }

  if !report.other_dependency_changes.is_empty() {
    out.write_string(
      "<div class=\"card\"><h2 style=\"margin-top:0;font-size:16px\">Other Dependency Changes (\{report.other_dependency_changes.length()})</h2><table><thead><tr><th>Dependency</th><th>Baseline</th><th>Candidate</th></tr></thead><tbody>\n",
    )
    for ch in report.other_dependency_changes {
      out.write_string(
        "<tr><td><code>\{html_escape(ch.requested)}</code></td><td><code>\{html_escape(ch.baseline.join(", "))}</code></td><td><code>\{html_escape(ch.candidate.join(", "))}</code></td></tr>\n",
      )
    }
    out.write_string("</tbody></table></div>\n")
  }

  if !root_causes.is_empty() {
    out.write_string(
      "<div class=\"card\"><h2 style=\"margin-top:0;font-size:16px\">Suspected Root-Cause Correlation (\{root_causes.length()})</h2><table><thead><tr><th>Upstream Package</th><th>Breaking Symbol</th><th>Change</th><th>Evidence</th><th>Matched Diagnostic</th></tr></thead><tbody>\n",
    )
    for hint in root_causes {
      out.write_string(
        "<tr><td><code>\{html_escape(hint.package_name)}</code></td><td><code>\{html_escape(hint.symbol)}</code></td><td>\{html_escape(hint.change_detail)}</td><td><span class=\"badge badge-fail\">\{html_escape(hint.evidence_kind)}</span></td><td><code>\{html_escape(hint.evidence_excerpt)}</code></td></tr>\n",
      )
    }
    out.write_string("</tbody></table></div>\n")
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
      "<div class=\"card\"><h2 style=\"margin-top:0;font-size:16px\">Upstream API Breaking Changes (\{breaking_diffs.length()})</h2><table><thead><tr><th>Package</th><th>Category</th><th>Symbol</th><th>Detail</th></tr></thead><tbody>\n",
    )
    let limit = if breaking_diffs.length() < 40 {
      breaking_diffs.length()
    } else {
      40
    }
    for i in 0..<limit {
      let (pkg, ch) = breaking_diffs[i]
      out.write_string(
        "<tr><td><code>\{html_escape(pkg)}</code></td><td><code>\{html_escape(ch.category)}</code></td><td><code>\{html_escape(ch.symbol)}</code></td><td>\{html_escape(ch.detail)}</td></tr>\n",
      )
    }
    out.write_string("</tbody></table></div>\n")
  }

  out.write_string("</body>\n</html>\n")
  out.to_string()
}

///|
/// Render a self-contained offline interactive HTML summary table for a batch regression run.
pub fn render_batch_html(outcome : BatchOutcome) -> String {
  let mut max_exit = 0
  for item in outcome.cases {
    if item.exit_code > max_exit {
      max_exit = item.exit_code
    }
  }
  let out = StringBuilder()
  out.write_string(
    "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n",
  )
  out.write_string("<title>Downstream Regression Batch Summary</title>\n")
  out.write_string(
    "<style>body{margin:0;padding:24px;font-family:system-ui,-apple-system,sans-serif;background:#f3f4f6;color:#111827} .card{background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:18px} .toolbar{display:flex;gap:10px;margin:12px 0;flex-wrap:wrap} input,select{padding:6px 10px;border:1px solid #d1d5db;border-radius:6px;font-size:13px} table{width:100%;border-collapse:collapse;font-size:13px} th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #e5e7eb} th{background:#f9fafb;font-weight:600} code{font-family:ui-monospace,monospace;font-size:12px} .badge{padding:2px 8px;border-radius:999px;font-size:12px;font-weight:600} .badge-pass{background:#dcfce7;color:#166534} .badge-fail{background:#fee2e2;color:#991b1b} .badge-warn{background:#fef3c7;color:#92400e}</style>\n",
  )
  out.write_string("</head>\n<body>\n<div class=\"card\">\n")
  out.write_string(
    "<h1 style=\"margin:0 0 6px;font-size:20px\">Downstream Regression Batch Summary</h1>\n",
  )
  out.write_string(
    "<p style=\"margin:0 0 12px;font-size:13px;color:#4b5563\">Cases: \{outcome.cases.length()} | Exit Code: <code>\{max_exit}</code> | Evidence: <code>\{html_escape(outcome.evidence)}</code></p>\n",
  )
  out.write_string(
    "<div class=\"toolbar\"><input id=\"q\" placeholder=\"Filter by case id...\" /><select id=\"st\"><option value=\"\">All statuses</option><option value=\"pass\">pass</option><option value=\"fail\">regression / error</option></select></div>\n",
  )
  out.write_string(
    "<table id=\"tbl\"><thead><tr><th>Case</th><th>Status</th><th>Exit</th><th>Baseline</th><th>Candidate</th><th>New Failures</th><th>Compile Errors</th><th>Notes</th></tr></thead><tbody>\n",
  )
  for item in outcome.cases {
    let st = item.status.unwrap_or("error")
    let badge = status_badge_class(st)
    let group = if st == "pass" { "pass" } else { "fail" }
    let notes = item.error.unwrap_or("-")
    out.write_string(
      "<tr data-id=\"\{html_escape(item.id)}\" data-group=\"\{group}\"><td><code>\{html_escape(item.id)}</code></td><td><span class=\"badge \{badge}\">\{html_escape(st)}</span></td><td><code>\{item.exit_code}</code></td><td>\{format_counts_compact(item.baseline_counts)}</td><td>\{format_counts_compact(item.candidate_counts)}</td><td>\{item.new_failure_count}</td><td>\{item.compiler_error_count}</td><td>\{html_escape(notes)}</td></tr>\n",
    )
  }
  out.write_string(
    "</tbody></table>\n</div>\n<script>(function(){const q=document.getElementById('q'),st=document.getElementById('st'),rows=[...document.querySelectorAll('#tbl tbody tr')];function f(){const t=q.value.trim().toLowerCase(),g=st.value;rows.forEach(r=>{const okId=!t||r.dataset.id.toLowerCase().includes(t);const okG=!g||r.dataset.group===g;r.style.display=(okId&&okG)?'':'none';});}q.addEventListener('input',f);st.addEventListener('change',f);})();</script>\n</body>\n</html>\n",
  )
  out.to_string()
}
