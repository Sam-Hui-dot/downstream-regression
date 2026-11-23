///|
async fn batch(args : Array[String], out_dir : String?) -> Int32 {
  guard args.length() == 4 else {
    raise @downstream-regression.StudyError::InvalidInput(usage)
  }
  let moon = args[1]
  let git = args[2]
  let raw_plan = @json.parse(@fs.read_file(args[3]).text())
  let cases = @downstream-regression.parse_batch_plan(raw_plan)
  let evidence = prepare_evidence_dir(out_dir, "moon-downstream-batch-")
  let outcomes : Array[@downstream-regression.CaseOutcome] = []
  let mut exit_code = 0
  for index, job in cases {
    let case_dir = "\{evidence}/case-\{index + 1}"
    @fs.mkdir(case_dir, recursive=true, allow_exist=true)
    let job_args = [
      "snapshot",
      moon,
      git,
      job.repo,
      job.revision,
      job.module_dir,
      job.dependency,
      job.baseline,
      job.candidate,
      job.target,
    ]
    let outcome : @downstream-regression.CaseOutcome = try {
      let (code, comparison) = snapshot(job_args, case_dir, false)
      {
        id: job.id,
        status: Some(comparison.status),
        exit_code: code,
        baseline_counts: comparison.baseline.counts,
        candidate_counts: comparison.candidate.counts,
        new_failure_count: comparison.new_failures.length(),
        compiler_error_count: comparison.candidate.compiler_errors.length(),
        evidence: case_dir,
        error: None,
      }
    } catch {
      error =>
        {
          id: job.id,
          status: None,
          exit_code: 2,
          baseline_counts: None,
          candidate_counts: None,
          new_failure_count: 0,
          compiler_error_count: 0,
          evidence: case_dir,
          error: Some(@downstream-regression.error_message(error)),
        }
    }
    outcomes.push(outcome)
    if outcome.exit_code > exit_code {
      exit_code = outcome.exit_code
    }
  }
  let report : @downstream-regression.BatchOutcome = {
    evidence,
    cases: outcomes,
  }
  let json = @json.ToJson::to_json(report).stringify()
  @fs.write_file("\{evidence}/batch.json", json, create_mode=CreateOrTruncate)
  @fs.write_file(
    "\{evidence}/batch.md",
    @downstream-regression.render_batch_markdown(report),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{evidence}/batch.html",
    @downstream-regression.render_batch_html(report),
    create_mode=CreateOrTruncate,
  )
  println(json)
  exit_code
}
