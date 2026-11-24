///|
/// A suspected causal link between an upstream `.mbti` breaking API change and a downstream failure.
#derive(Debug, Eq, ToJson)
pub(all) struct RootCauseHint {
  package_name : String
  symbol : String
  category : String
  change_detail : String
  evidence_kind : String
  evidence_excerpt : String
}

///|
pub extend RootCauseHint with @debug.Debug::{to_repr}

///|
pub extend RootCauseHint with Eq::{not_equal, equal}

///|
pub extend RootCauseHint with @json.ToJson::{to_json}

///|
fn is_ident_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

///|
fn contains_identifier(haystack : String, ident : String) -> Bool {
  if ident.is_empty() || haystack.length() < ident.length() {
    return false
  }
  let h = haystack.to_array()
  let n = ident.to_array()
  let hlen = h.length()
  let nlen = n.length()
  if hlen < nlen {
    return false
  }
  for i in 0..<=(hlen - nlen) {
    let mut matched = true
    for j in 0..<nlen {
      if h[i + j] != n[j] {
        matched = false
        break
      }
    }
    if matched {
      let left_ok = i == 0 || !is_ident_char(h[i - 1])
      let right_ok = i + nlen == hlen || !is_ident_char(h[i + nlen])
      if left_ok && right_ok {
        return true
      }
    }
  }
  false
}

///|
fn candidate_match_tokens(category : String, symbol : String) -> Array[String] {
  let tokens : Array[String] = []
  let trimmed = symbol.trim().to_owned()
  if trimmed.is_empty() {
    return tokens
  }
  if category == "member" {
    match trimmed.split_once(".") {
      Some((ty, rest)) => {
        let member_ident = extract_ident_before(rest, " :([=")
        if member_ident.length() >= 3 {
          tokens.push(member_ident)
        }
        if ty.length() >= 3 {
          tokens.push(ty.to_owned())
        }
      }
      None => ()
    }
    return tokens
  }
  if category == "impl" {
    return tokens
  }
  tokens.push(trimmed)
  if trimmed.contains("::") {
    match trimmed.split_once("::") {
      Some((_, meth)) => {
        let m = meth.trim().to_owned()
        if m.length() >= 4 &&
          m != "equal" &&
          m != "not_equal" &&
          m != "to_repr" &&
          m != "to_json" &&
          m != "to_string" {
          tokens.push(m)
        }
      }
      None => ()
    }
  }
  tokens
}

///|
fn strip_box_prefix(line : String) -> String {
  let chars = line.to_array()
  let mut idx = 0
  while idx < chars.length() {
    let c = chars[idx]
    if c == ' ' ||
      c == '\t' ||
      c == '│' ||
      c == '╰' ||
      c == '─' ||
      c == '╭' ||
      c == '┬' ||
      c == '┼' ||
      c == '├' ||
      c == '|' {
      idx += 1
    } else {
      break
    }
  }
  let out = StringBuilder()
  for i in idx..<chars.length() {
    out.write_char(chars[i])
  }
  out.to_string().trim().to_owned()
}

///|
fn extract_compiler_error_blocks(log : String) -> Array[(String, String)] {
  let clean = strip_ansi(log).replace_all(old="\r", new="")
  let lines = clean.split("\n").to_array()
  let blocks : Array[(String, String)] = []
  let total = lines.length()
  let mut i = 0
  while i < total {
    let line = lines[i].trim().to_owned()
    if line.contains("Error: [") {
      let buf = StringBuilder()
      buf.write_string(line)
      let mut summary = line
      let limit = if i + 10 < total { i + 10 } else { total }
      for j in (i + 1)..<limit {
        let next_line = lines[j].trim().to_owned()
        if next_line.contains("Error: [") {
          break
        }
        if !next_line.is_empty() {
          buf.write_string("\n")
          buf.write_string(next_line)
          if summary == line &&
            (
              next_line.contains("is unbound") ||
              next_line.contains("not found") ||
              next_line.contains("mismatch") ||
              next_line.contains("has no") ||
              next_line.contains("cannot") ||
              next_line.contains("Error:")
            ) {
            summary = "\{line} - \{strip_box_prefix(next_line)}"
          }
        }
      }
      blocks.push((summary, buf.to_string()))
    }
    i += 1
  }
  blocks
}

///|
fn matches_any_token(text : String, tokens : Array[String]) -> Bool {
  for tok in tokens {
    if tok.length() >= 3 && contains_identifier(text, tok) {
      return true
    }
  }
  false
}

///|
/// Correlate upstream `.mbti` breaking API changes with downstream compiler diagnostics and test failures.
pub fn correlate_regression_with_mbti(
  report : Comparison,
  api_diffs : Array[MbtiDiffReport],
  candidate_test_log : String,
) -> Array[RootCauseHint] {
  let hints : Array[RootCauseHint] = []
  let seen : Map[String, Bool] = Map([])
  let err_blocks = extract_compiler_error_blocks(candidate_test_log)

  for diff in api_diffs {
    for ch in diff.changes {
      if ch.severity != "breaking" {
        continue
      }
      let tokens = candidate_match_tokens(ch.category, ch.symbol)
      if tokens.is_empty() {
        continue
      }
      for block in err_blocks {
        let (summary, full_block) = block
        if matches_any_token(full_block, tokens) {
          let key = "\{diff.package_name}|\{ch.symbol}|compiler_error|\{summary}"
          if !seen.contains(key) {
            seen[key] = true
            hints.push({
              package_name: diff.package_name,
              symbol: ch.symbol,
              category: ch.category,
              change_detail: ch.detail,
              evidence_kind: "compiler_error",
              evidence_excerpt: summary,
            })
          }
        }
      }
      for test_name in sorted_keys(report.new_failures) {
        let msg = report.new_failures.get(test_name).unwrap_or("")
        let combined = "\{test_name} \{msg}"
        if matches_any_token(combined, tokens) {
          let excerpt = "\{test_name}: \{msg}"
          let key = "\{diff.package_name}|\{ch.symbol}|test_failure|\{excerpt}"
          if !seen.contains(key) {
            seen[key] = true
            hints.push({
              package_name: diff.package_name,
              symbol: ch.symbol,
              category: ch.category,
              change_detail: ch.detail,
              evidence_kind: "test_failure",
              evidence_excerpt: excerpt,
            })
          }
        }
      }
      for test_name in sorted_keys(report.changed_failure_messages) {
        let msg = report.changed_failure_messages.get(test_name).unwrap_or("")
        let combined = "\{test_name} \{msg}"
        if matches_any_token(combined, tokens) {
          let excerpt = "\{test_name}: \{msg}"
          let key = "\{diff.package_name}|\{ch.symbol}|test_failure|\{excerpt}"
          if !seen.contains(key) {
            seen[key] = true
            hints.push({
              package_name: diff.package_name,
              symbol: ch.symbol,
              category: ch.category,
              change_detail: ch.detail,
              evidence_kind: "test_failure",
              evidence_excerpt: excerpt,
            })
          }
        }
      }
    }
  }
  hints
}
