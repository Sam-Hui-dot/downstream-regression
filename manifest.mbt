///|
/// Rewrite a pinned direct registry dependency in a `moon.mod` or `moon.mod.json` manifest.
///
/// The dependency must match `baseline_version` exactly once; zero or multiple
/// occurrences raise `StudyError::InvalidInput` so unrelated lines are never edited.
pub fn rewrite_manifest_dependency(
  kind : ManifestKind,
  content : String,
  dependency : String,
  baseline_version : String,
  candidate_version : String,
) -> String raise StudyError {
  guard !dependency.trim().is_empty() else {
    raise InvalidInput("dependency name must be nonempty")
  }
  guard baseline_version != candidate_version else {
    raise InvalidInput("use two distinct dependency versions")
  }
  match kind {
    MoonMod =>
      rewrite_moon_mod(content, dependency, baseline_version, candidate_version)
    MoonModJson =>
      rewrite_moon_mod_json(
        content, dependency, baseline_version, candidate_version,
      )
  }
}

///|
fn rewrite_moon_mod(
  content : String,
  dependency : String,
  baseline_version : String,
  candidate_version : String,
) -> String raise StudyError {
  let pin = "\"\{dependency}@\{baseline_version}\""
  guard content.split(pin).to_array().length() == 2 else {
    raise InvalidInput("expected one occurrence of \{pin}")
  }
  let replacement = "\"\{dependency}@\{candidate_version}\""
  content.replace_all(old=pin, new=replacement)
}

///|
fn is_json_ws(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'
}

///|
fn chars_match_at(
  chars : Array[Char],
  offset : Int32,
  pattern : Array[Char],
) -> Bool {
  if offset + pattern.length() > chars.length() {
    return false
  }
  for i in 0..<pattern.length() {
    if chars[offset + i] != pattern[i] {
      return false
    }
  }
  true
}

///|
fn rewrite_moon_mod_json(
  content : String,
  dependency : String,
  baseline_version : String,
  candidate_version : String,
) -> String raise StudyError {
  // Validate that the input is well-formed JSON and contains the pinned string under `deps`.
  let parsed = @json.parse(content) catch {
    error => raise InvalidInput("invalid moon.mod.json: \{error}")
  }
  guard parsed is Object(root) else {
    raise InvalidInput("moon.mod.json root must be a JSON object")
  }
  guard root.get("deps") is Some(Object(deps)) else {
    raise InvalidInput("moon.mod.json is missing a deps object")
  }
  guard deps.get(dependency) is Some(String(current)) &&
    current == baseline_version else {
    raise InvalidInput(
      "expected deps[\"\{dependency}\"] == \"\{baseline_version}\" in moon.mod.json",
    )
  }

  let key_token = "\"\{dependency}\"".to_array()
  let val_token = "\"\{baseline_version}\"".to_array()
  let chars = content.to_array()
  let len = chars.length()
  let matches : Array[(Int32, Int32)] = []

  let mut i = 0
  while i < len {
    if chars[i] == '"' {
      if chars_match_at(chars, i, key_token) {
        let mut j = i + key_token.length()
        while j < len && is_json_ws(chars[j]) {
          j += 1
        }
        if j < len && chars[j] == ':' {
          j += 1
          while j < len && is_json_ws(chars[j]) {
            j += 1
          }
          if chars_match_at(chars, j, val_token) {
            matches.push((j, j + val_token.length()))
          }
        }
      }
      // Advance past the current JSON string literal.
      i += 1
      while i < len {
        if chars[i] == '\\' {
          i += 2
        } else if chars[i] == '"' {
          i += 1
          break
        } else {
          i += 1
        }
      }
    } else {
      i += 1
    }
  }

  guard matches.length() == 1 else {
    raise InvalidInput(
      "expected one occurrence of \"\{dependency}\": \"\{baseline_version}\" in moon.mod.json",
    )
  }

  let (val_start, val_end) = matches[0]
  let out = StringBuilder()
  for idx in 0..<val_start {
    out.write_char(chars[idx])
  }
  out.write_string("\"\{candidate_version}\"")
  for idx in val_end..<len {
    out.write_char(chars[idx])
  }
  out.to_string()
}
