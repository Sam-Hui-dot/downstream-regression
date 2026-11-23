///|
async fn logged_moon(
  moon : String,
  arguments : Array[String],
  log_path : String,
  timeout_ms~ : Int32,
) -> (Int32, String) {
  let status = run_to_log(moon, arguments, log_path, timeout_ms~)
  let bytes = @fs.file_size(log_path)
  guard bytes <= 16_777_216L else {
    raise @downstream-regression.tool_failed(
      "output exceeds the parsing limit; complete log: \{log_path}",
    )
  }
  let contents = @fs.read_file(log_path).text()
  (status, contents)
}

///|
async fn run_to_log(
  moon : String,
  arguments : Array[String],
  log_path : String,
  timeout_ms~ : Int32,
) -> Int32 {
  let output = @process.redirect_to_file(log_path, shared=true)
  defer output.close()
  let status = @async.with_timeout_opt(timeout_ms, () => {
    @process.run(
      moon,
      arguments,
      extra_env={ "MOON_WORK": "off", "NO_COLOR": "1" },
      stdout=output,
      stderr=output,
    )
  })
  guard status is Some(code) else {
    raise @downstream-regression.tool_failed(
      "moon exceeded \{timeout_ms / 1000}s; partial log: \{log_path}",
    )
  }
  code
}

///|
async fn prepare_evidence_dir(out_dir : String?, prefix : String) -> String {
  match out_dir {
    None => @fs.tmpdir(prefix~)
    Some(dir) => {
      guard !dir.trim().is_empty() else {
        raise @downstream-regression.StudyError::InvalidInput(
          "--out requires a nonempty path",
        )
      }
      @fs.mkdir(dir, recursive=true, allow_exist=true)
      @fs.realpath(dir)
    }
  }
}
