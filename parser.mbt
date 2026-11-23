///|
/// Strip ANSI CSI escape sequences (such as color codes) from captured tool logs.
pub fn strip_ansi(text : String) -> String {
  let out = StringBuilder()
  let chars = text.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    if chars[i] == '\u{1b}' && i + 1 < len && chars[i + 1] == '[' {
      i += 2
      while i < len {
        let code = chars[i].to_int()
        i += 1
        if code >= 0x40 && code <= 0x7E {
          break
        }
      }
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  out.to_string()
}

///|
/// Extract failing test records keyed by `package / file / test_name`.
pub fn parse_failure_records(log : String) -> Map[String, String] {
  let clean = strip_ansi(log)
  let records : Map[String, String] = Map([])
  for raw in clean.split("\n") {
    let line = raw.trim()
    guard line.has_prefix("[") else { continue }
    guard line.find("] test ") is Some(package_end) else { continue }
    guard line.find(" (\"") is Some(name_start) else { continue }
    guard line.find("\") failed:") is Some(name_end) else { continue }
    let file_start = package_end + 7
    guard file_start <= name_start && name_start + 3 <= name_end else {
      continue
    }
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
/// Parse the final valid `Total tests:` summary line from a `moon test` log.
pub fn parse_test_counts(log : String) -> TestCounts? {
  let clean = strip_ansi(log)
  let mut summary = None
  for line in clean.split("\n") {
    let trimmed = line.trim()
    if trimmed.has_prefix("Total tests:") {
      summary = parse_counts_line(trimmed) catch { _ => None }
    }
  }
  summary
}

///|
fn parse_counts_line(line : StringView) -> TestCounts? raise {
  let counts : Map[String, Int32] = Map([])
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
  guard total > 0 && passed >= 0 && failed >= 0 && skipped >= 0 else {
    return None
  }
  guard passed.to_int64() + failed.to_int64() + skipped.to_int64() ==
    total.to_int64() else {
    return None
  }
  Some({ total, passed, failed, skipped, })
}

///|
/// Extract MoonBit compiler diagnostic headers such as `Error: [4021]`.
pub fn parse_compiler_errors(log : String) -> Array[String] {
  let clean = strip_ansi(log)
  let errors : Array[String] = []
  for raw in clean.split("\n") {
    let line = raw.trim()
    guard line.has_prefix("Error: [") else { continue }
    guard line[8:].split_once("]") is Some((code, _)) else { continue }
    guard code.length() == 4 &&
      code.to_owned().iter().all(ch => ch >= '0' && ch <= '9') else {
      continue
    }
    errors.push(line.to_owned())
  }
  errors
}

///|
/// Identify the root module coordinate (`name@version`) from `moon tree` output.
pub fn parse_tree_root(tree : String) -> String {
  let clean = strip_ansi(tree)
  for raw in clean.split("\n") {
    let line = raw.trim_end()
    if line.split_once(" (local ") is Some((coordinate, _)) {
      let root = coordinate.trim()
      if !root.has_prefix("├") &&
        !root.has_prefix("└") &&
        !root.has_prefix("│") {
        return root.to_owned()
      }
    }
  }
  ""
}

///|
/// List direct top-level resolved edges for a given dependency in `moon tree` output.
pub fn parse_direct_versions(
  tree : String,
  dependency : String,
) -> Array[String] {
  let clean = strip_ansi(tree)
  let prefix = "\{dependency} -> "
  let versions : Array[String] = []
  for raw in clean.split("\n") {
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
/// Collect all resolved dependency edges from `moon tree`, normalizing local paths.
pub fn parse_dependency_inventory(tree : String) -> Map[String, Array[String]] {
  let clean = strip_ansi(tree)
  let all : Map[String, Array[String]] = Map([])
  for raw in clean.split("\n") {
    let line = raw.trim_end()
    let edge_start = match line.find("├─ ") {
      Some(index) => index
      None =>
        match line.find("└─ ") {
          Some(index) => index
          None => continue
        }
    }
    let edge = line[edge_start + 3:]
    guard edge.split_once(" -> ") is Some((requested, destination)) else {
      continue
    }
    let name = requested.trim().to_owned()
    let resolved = match destination.split_once(" (local ") {
      Some((coordinate, _)) => "\{coordinate} (local)"
      None => destination.trim().to_owned()
    }
    let versions = match all.get(name) {
      Some(values) => values
      None => {
        let values : Array[String] = []
        all[name] = values
        values
      }
    }
    if !versions.contains(resolved) {
      versions.push(resolved)
    }
  }
  for _, versions in all {
    versions.sort()
  }
  all
}

///|
/// Compute non-target dependency resolution differences between two trials.
pub fn diff_resolutions(
  baseline : Map[String, Array[String]],
  candidate : Map[String, Array[String]],
  selected_dependency : String,
) -> Array[ResolutionChange] {
  let names : Array[String] = []
  for requested, _ in baseline {
    names.push(requested)
  }
  for requested, _ in candidate {
    if !baseline.contains(requested) {
      names.push(requested)
    }
  }
  names.sort()
  let changes : Array[ResolutionChange] = []
  for name in names {
    if name == selected_dependency {
      continue
    }
    let before = baseline.get(name).unwrap_or([])
    let after = candidate.get(name).unwrap_or([])
    if before != after {
      changes.push({ requested: name, baseline: before, candidate: after, })
    }
  }
  changes
}
