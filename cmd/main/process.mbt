///|
async fn logged_moon(
  moon : String,
  arguments : Array[String],
  log_path : String,
  timeout_ms~ : Int,
) -> (Int, String) {
  let status = run_to_log(moon, arguments, log_path, timeout_ms~)
  let bytes = @fs.file_size(log_path)
  guard bytes <= 16_777_216L else {
    raise ToolFailed("output exceeds the parsing limit; complete log: \{log_path}")
  }
  let contents = @fs.read_file(log_path).text()
  (status, contents)
}

///|
async fn run_to_log(
  moon : String,
  arguments : Array[String],
  log_path : String,
  timeout_ms~ : Int,
) -> Int {
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
    raise ToolFailed("moon exceeded \{timeout_ms / 1000}s; partial log: \{log_path}")
  }
  code
}

///|
fn root_coordinate(tree : String) -> String {
  for raw in tree.split("\n") {
    if raw.split_once(" (local ") is Some((coordinate, _)) {
      let root = coordinate.trim()
      if !root.has_prefix("├") && !root.has_prefix("└") && !root.has_prefix("│") {
        return root.to_owned()
      }
    }
  }
  ""
}
