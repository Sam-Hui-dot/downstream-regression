///|
/// Parsed declaration of a MoonBit public type/struct/enum/suberror/trait in a `.mbti` file.
#derive(Debug, Eq, ToJson)
pub(all) struct MbtiTypeDecl {
  name : String
  kind : String
  visibility : String
  header : String
  members : Array[String]
}

///|
pub extend MbtiTypeDecl with @debug.Debug::{to_repr}

///|
pub extend MbtiTypeDecl with Eq::{not_equal, equal}

///|
pub extend MbtiTypeDecl with @json.ToJson::{to_json}

///|
/// Parsed representation of a MoonBit `pkg.generated.mbti` public interface file.
#derive(Debug, Eq, ToJson)
pub(all) struct MbtiInterface {
  package_name : String
  values : Map[String, String]
  types : Map[String, MbtiTypeDecl]
  methods : Map[String, String]
  impls : Array[String]
  type_aliases : Map[String, String]
}

///|
pub extend MbtiInterface with @debug.Debug::{to_repr}

///|
pub extend MbtiInterface with Eq::{not_equal, equal}

///|
pub extend MbtiInterface with @json.ToJson::{to_json}

///|
/// A single API change entry produced by comparing two `.mbti` interfaces.
#derive(Debug, Eq, ToJson)
pub(all) struct MbtiChange {
  severity : String
  category : String
  symbol : String
  detail : String
  baseline : String?
  candidate : String?
}

///|
pub extend MbtiChange with @debug.Debug::{to_repr}

///|
pub extend MbtiChange with Eq::{not_equal, equal}

///|
pub extend MbtiChange with @json.ToJson::{to_json}

///|
/// Structured static compatibility report between baseline and candidate `.mbti` interfaces.
#derive(Debug, Eq, ToJson)
pub(all) struct MbtiDiffReport {
  package_name : String
  compatible : Bool
  breaking_count : Int32
  additive_count : Int32
  changes : Array[MbtiChange]
}

///|
pub extend MbtiDiffReport with @debug.Debug::{to_repr}

///|
pub extend MbtiDiffReport with Eq::{not_equal, equal}

///|
pub extend MbtiDiffReport with @json.ToJson::{to_json}

///|
fn mbti_lex_cmp(a : String, b : String) -> Int32 {
  let len = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<len {
    let ca = a.code_unit_at(i)
    let cb = b.code_unit_at(i)
    if ca != cb {
      return ca.compare(cb)
    }
  }
  a.length().compare(b.length())
}

///|
fn normalize_sig_whitespace(text : String) -> String {
  let out = StringBuilder()
  let mut prev_space = false
  for ch in text.trim() {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      if !prev_space {
        out.write_char(' ')
        prev_space = true
      }
    } else {
      out.write_char(ch)
      prev_space = false
    }
  }
  out.to_string()
}

///|
fn has_unclosed_delimiters(text : String) -> Bool {
  let mut parens = 0
  let mut brackets = 0
  for ch in text {
    match ch {
      '(' => parens += 1
      ')' => if parens > 0 { parens -= 1 }
      '[' => brackets += 1
      ']' => if brackets > 0 { brackets -= 1 }
      _ => ()
    }
  }
  parens > 0 || brackets > 0
}

///|
fn extract_ident_before(text : StringView, delimiters : String) -> String {
  let out = StringBuilder()
  for ch in text {
    if delimiters.contains_char(ch) {
      break
    }
    out.write_char(ch)
  }
  out.to_string().trim().to_owned()
}

///|
fn parse_type_header(line : String) -> (String, String, String)? {
  let trimmed = line.trim().to_owned()
  let (vis, rest) = if trimmed.has_prefix("pub(all) ") {
    ("pub(all)", trimmed[9:].trim().to_owned())
  } else if trimmed.has_prefix("pub(open) ") {
    ("pub(open)", trimmed[10:].trim().to_owned())
  } else if trimmed.has_prefix("pub(readonly) ") {
    ("pub(readonly)", trimmed[14:].trim().to_owned())
  } else if trimmed.has_prefix("pub ") {
    ("pub", trimmed[4:].trim().to_owned())
  } else if trimmed.has_prefix("type ") {
    ("abstract", trimmed)
  } else {
    return None
  }
  for kind in ["struct", "enum", "suberror", "trait", "type"] {
    let prefix = "\{kind} "
    if rest.has_prefix(prefix) {
      let after = rest[prefix.length():]
      let name = extract_ident_before(after, " {([:=<")
      if !name.is_empty() {
        return Some((vis, kind, name))
      }
    }
  }
  None
}

///|
/// Parse a MoonBit `.mbti` interface file into structured values, types, methods, impls, and aliases.
pub fn parse_mbti(text : String) -> MbtiInterface {
  let clean = strip_ansi(text).replace_all(old="\r", new="")
  let lines = clean.split("\n").to_array()
  let mut package_name = ""
  let values : Map[String, String] = Map([])
  let types : Map[String, MbtiTypeDecl] = Map([])
  let methods : Map[String, String] = Map([])
  let impls : Array[String] = []
  let type_aliases : Map[String, String] = Map([])

  let mut i = 0
  let total = lines.length()
  while i < total {
    let raw_line = lines[i].trim().to_owned()
    i += 1
    if raw_line.is_empty() ||
      raw_line.has_prefix("//") ||
      raw_line.has_prefix("#") {
      continue
    }
    if raw_line.has_prefix("package \"") && raw_line.has_suffix("\"") {
      package_name = raw_line[9:raw_line.length() - 1].to_owned()
      continue
    }
    if raw_line.has_prefix("import {") {
      while i < total && !lines[i].trim().has_prefix("}") {
        i += 1
      }
      if i < total {
        i += 1
      }
      continue
    }
    if raw_line.has_prefix("pub impl ") || raw_line.has_prefix("pub extend ") {
      let mut full = raw_line
      while i < total && has_unclosed_delimiters(full) {
        let next_line = lines[i].trim().to_owned()
        i += 1
        if !next_line.is_empty() && !next_line.has_prefix("//") {
          full = "\{full} \{next_line}"
        }
      }
      let norm = normalize_sig_whitespace(full)
      if !impls.contains(norm) {
        impls.push(norm)
      }
      continue
    }
    if raw_line.has_prefix("pub typealias ") {
      let mut full = raw_line
      while i < total && has_unclosed_delimiters(full) {
        let next_line = lines[i].trim().to_owned()
        i += 1
        if !next_line.is_empty() && !next_line.has_prefix("//") {
          full = "\{full} \{next_line}"
        }
      }
      let norm = normalize_sig_whitespace(full)
      let rest = norm[14:].trim()
      let name = extract_ident_before(rest, " =[")
      if !name.is_empty() {
        type_aliases[name] = norm
      }
      continue
    }
    if raw_line.has_prefix("pub fn ") ||
      raw_line.has_prefix("pub fn[") ||
      raw_line.has_prefix("pub async fn ") ||
      raw_line.has_prefix("pub async fn[") ||
      raw_line.has_prefix("pub let ") ||
      raw_line.has_prefix("pub const ") {
      let mut full = raw_line
      while i < total && has_unclosed_delimiters(full) {
        let next_line = lines[i].trim().to_owned()
        i += 1
        if !next_line.is_empty() && !next_line.has_prefix("//") {
          full = "\{full} \{next_line}"
        }
      }
      let line = normalize_sig_whitespace(full)
      let is_value_binding = line.has_prefix("pub let ") ||
        line.has_prefix("pub const ")
      let rest = if line.has_prefix("pub async fn ") {
        line[13:]
      } else if line.has_prefix("pub async fn[") {
        line[12:]
      } else if line.has_prefix("pub fn ") {
        line[7:]
      } else if line.has_prefix("pub fn[") {
        line[6:]
      } else if line.has_prefix("pub const ") {
        line[10:]
      } else {
        line[8:]
      }
      // Handle generic fn prefix like `pub fn[T] foo(...)`
      let after_generics = if rest.has_prefix("[") {
        match rest.split_once("]") {
          Some((_, tail)) => tail.trim()
          None => rest
        }
      } else {
        rest.trim()
      }
      let stop_chars = if is_value_binding { " :=" } else { " ([" }
      let sym = extract_ident_before(after_generics, stop_chars)
      if !sym.is_empty() {
        if sym.contains("::") {
          methods[sym] = line
        } else {
          values[sym] = line
        }
      }
      continue
    }
    match parse_type_header(raw_line) {
      Some((visibility, kind, name)) => {
        let members : Array[String] = []
        if raw_line.contains("{") && !raw_line.contains("}") {
          while i < total {
            let field_line = lines[i].trim().to_owned()
            i += 1
            if field_line.has_prefix("}") {
              break
            }
            if !field_line.is_empty() && !field_line.has_prefix("//") {
              members.push(field_line)
            }
          }
        }
        types[name] = { name, kind, visibility, header: raw_line, members, }
      }
      None => ()
    }
  }
  impls.sort_by((a, b) => mbti_lex_cmp(a, b))
  { package_name, values, types, methods, impls, type_aliases, }
}

///|
fn sorted_map_keys_str(m : Map[String, String]) -> Array[String] {
  let keys : Array[String] = []
  for k, _ in m {
    keys.push(k)
  }
  keys.sort_by((a, b) => mbti_lex_cmp(a, b))
  keys
}

///|
fn visibility_rank(vis : String) -> Int32 {
  match vis {
    "abstract" => 0
    "pub" => 1
    "pub(readonly)" => 2
    "pub(open)" => 3
    "pub(all)" => 4
    _ => 1
  }
}

///|
fn extract_balanced_segment(
  text : String,
  open_ch : Char,
  close_ch : Char,
) -> (String, String)? {
  let chars = text.to_array()
  let mut start = -1
  let mut depth = 0
  for i in 0..<chars.length() {
    let c = chars[i]
    if c == open_ch {
      if start < 0 {
        start = i
      }
      depth += 1
    } else if c == close_ch && start >= 0 {
      depth -= 1
      if depth == 0 {
        let seg = StringBuilder()
        for j in (start + 1)..<i {
          seg.write_char(chars[j])
        }
        let rest = StringBuilder()
        for j in (i + 1)..<chars.length() {
          rest.write_char(chars[j])
        }
        return Some(
          (
            seg.to_string().trim().to_owned(),
            rest.to_string().trim().to_owned(),
          ),
        )
      }
    }
  }
  None
}

///|
fn split_return_and_raise(tail : String) -> (String, String) {
  let clean = match tail.split_once("->") {
    Some((_, rhs)) => rhs.trim().to_owned()
    None => tail.trim().to_owned()
  }
  match clean.split_once(" raise") {
    Some((ret, err)) => (ret.trim().to_owned(), "raise\{err}".trim().to_owned())
    None => (clean, "")
  }
}

///|
fn extract_fn_generics(sig : String) -> String {
  let trimmed = if sig.has_prefix("pub async fn") {
    sig[12:].trim().to_owned()
  } else if sig.has_prefix("pub fn") {
    sig[6:].trim().to_owned()
  } else {
    return ""
  }
  if trimmed.has_prefix("[") {
    match extract_balanced_segment(trimmed, '[', ']') {
      Some((g, _)) => g
      None => ""
    }
  } else {
    ""
  }
}

///|
fn classify_signature_change(old_sig : String, new_sig : String) -> String {
  let reasons : Array[String] = []
  let old_async = old_sig.has_prefix("pub async fn")
  let new_async = new_sig.has_prefix("pub async fn")
  if old_async != new_async {
    reasons.push("async modifier changed")
  }
  let old_gen = extract_fn_generics(old_sig)
  let new_gen = extract_fn_generics(new_sig)
  if old_gen != new_gen {
    reasons.push("generic parameters or trait bounds changed")
  }
  match
    (
      extract_balanced_segment(old_sig, '(', ')'),
      extract_balanced_segment(new_sig, '(', ')'),
    ) {
    (Some((old_params, old_tail)), Some((new_params, new_tail))) => {
      if old_params != new_params {
        let old_labeled = old_params.contains("~") || old_params.contains("?")
        let new_labeled = new_params.contains("~") || new_params.contains("?")
        if old_labeled || new_labeled {
          reasons.push("labeled or optional parameters changed")
        } else {
          reasons.push("parameter list changed")
        }
      }
      let (old_ret, old_err) = split_return_and_raise(old_tail)
      let (new_ret, new_err) = split_return_and_raise(new_tail)
      if old_ret != new_ret {
        reasons.push("return type changed")
      }
      if old_err != new_err {
        reasons.push("raise/error signature changed")
      }
    }
    _ => ()
  }
  if reasons.is_empty() {
    "signature changed"
  } else {
    reasons.join("; ")
  }
}

///|
fn diff_signature_maps(
  changes : Array[MbtiChange],
  category : String,
  before : Map[String, String],
  after : Map[String, String],
) -> Unit {
  for sym in sorted_map_keys_str(before) {
    let old_sig = before.get(sym).unwrap_or("")
    match after.get(sym) {
      None =>
        changes.push({
          severity: "breaking",
          category,
          symbol: sym,
          detail: "removed public \{category}",
          baseline: Some(old_sig),
          candidate: None,
        })
      Some(new_sig) =>
        if old_sig != new_sig {
          let detail = if category == "value" || category == "method" {
            classify_signature_change(old_sig, new_sig)
          } else {
            "signature changed"
          }
          changes.push({
            severity: "breaking",
            category,
            symbol: sym,
            detail,
            baseline: Some(old_sig),
            candidate: Some(new_sig),
          })
        }
    }
  }
  for sym in sorted_map_keys_str(after) {
    if !before.contains(sym) {
      changes.push({
        severity: "additive",
        category,
        symbol: sym,
        detail: "added public \{category}",
        baseline: None,
        candidate: after.get(sym),
      })
    }
  }
}

///|
/// Statically compare two `.mbti` public interfaces and classify breaking vs additive API changes.
pub fn diff_mbti(
  baseline_text : String,
  candidate_text : String,
) -> MbtiDiffReport {
  let base = parse_mbti(baseline_text)
  let cand = parse_mbti(candidate_text)
  let changes : Array[MbtiChange] = []

  diff_signature_maps(changes, "value", base.values, cand.values)
  diff_signature_maps(changes, "method", base.methods, cand.methods)
  diff_signature_maps(
    changes,
    "typealias",
    base.type_aliases,
    cand.type_aliases,
  )

  // Compare types, visibility, struct fields, enum variants, and trait methods
  let base_type_names : Array[String] = []
  for k, _ in base.types {
    base_type_names.push(k)
  }
  base_type_names.sort_by((a, b) => mbti_lex_cmp(a, b))

  let cand_type_names : Array[String] = []
  for k, _ in cand.types {
    cand_type_names.push(k)
  }
  cand_type_names.sort_by((a, b) => mbti_lex_cmp(a, b))

  for name in base_type_names {
    let bt = base.types.get(name).unwrap()
    match cand.types.get(name) {
      None =>
        changes.push({
          severity: "breaking",
          category: "type",
          symbol: name,
          detail: "removed public \{bt.kind}",
          baseline: Some(bt.header),
          candidate: None,
        })
      Some(ct) =>
        if bt.kind != ct.kind {
          changes.push({
            severity: "breaking",
            category: "type",
            symbol: name,
            detail: "changed kind from \{bt.kind} to \{ct.kind}",
            baseline: Some(bt.header),
            candidate: Some(ct.header),
          })
        } else {
          let br = visibility_rank(bt.visibility)
          let cr = visibility_rank(ct.visibility)
          if cr < br {
            changes.push({
              severity: "breaking",
              category: "type",
              symbol: name,
              detail: "visibility narrowed from \{bt.visibility} to \{ct.visibility}",
              baseline: Some(bt.header),
              candidate: Some(ct.header),
            })
          } else if cr > br {
            changes.push({
              severity: "additive",
              category: "type",
              symbol: name,
              detail: "visibility widened from \{bt.visibility} to \{ct.visibility}",
              baseline: Some(bt.header),
              candidate: Some(ct.header),
            })
          }
          // Check removed or changed members
          for m in bt.members {
            if !ct.members.contains(m) {
              changes.push({
                severity: "breaking",
                category: "member",
                symbol: "\{name}.\{m}",
                detail: "removed or altered member in \{bt.kind}",
                baseline: Some(m),
                candidate: None,
              })
            }
          }
          for m in ct.members {
            if !bt.members.contains(m) {
              // Adding a member to pub(all) struct/enum/suberror or trait breaks construction/matching/impls.
              let is_breaking = ct.visibility == "pub(all)" ||
                ct.kind == "trait" ||
                ct.kind == "enum" ||
                ct.kind == "suberror"
              changes.push({
                severity: if is_breaking {
                  "breaking"
                } else {
                  "additive"
                },
                category: "member",
                symbol: "\{name}.\{m}",
                detail: if is_breaking {
                  "added member to \{ct.visibility} \{ct.kind} (breaks exhaustive match or literal construction)"
                } else {
                  "added member to \{ct.kind}"
                },
                baseline: None,
                candidate: Some(m),
              })
            }
          }
        }
    }
  }
  for name in cand_type_names {
    if !base.types.contains(name) {
      let ct = cand.types.get(name).unwrap()
      changes.push({
        severity: "additive",
        category: "type",
        symbol: name,
        detail: "added public \{ct.kind}",
        baseline: None,
        candidate: Some(ct.header),
      })
    }
  }

  // Compare public trait implementations
  for imp in base.impls {
    if !cand.impls.contains(imp) {
      changes.push({
        severity: "breaking",
        category: "impl",
        symbol: imp,
        detail: "removed public trait implementation",
        baseline: Some(imp),
        candidate: None,
      })
    }
  }
  for imp in cand.impls {
    if !base.impls.contains(imp) {
      changes.push({
        severity: "additive",
        category: "impl",
        symbol: imp,
        detail: "added public trait implementation",
        baseline: None,
        candidate: Some(imp),
      })
    }
  }

  let mut breaking_count = 0
  let mut additive_count = 0
  for ch in changes {
    if ch.severity == "breaking" {
      breaking_count += 1
    } else {
      additive_count += 1
    }
  }
  let pkg = if !cand.package_name.is_empty() {
    cand.package_name
  } else {
    base.package_name
  }
  {
    package_name: pkg,
    compatible: breaking_count == 0,
    breaking_count,
    additive_count,
    changes,
  }
}

///|
/// Render an `MbtiDiffReport` as compact plain text.
pub fn render_mbti_diff_text(report : MbtiDiffReport) -> String {
  let out = StringBuilder()
  let verdict = if report.compatible { "COMPATIBLE" } else { "BREAKING" }
  out.write_string(
    "MBTI Diff [\{verdict}] package=\{report.package_name} breaking=\{report.breaking_count} additive=\{report.additive_count}\n",
  )
  for ch in report.changes {
    out.write_string(
      "[\{ch.severity}] \{ch.category} \{ch.symbol}: \{ch.detail}\n",
    )
  }
  out.to_string()
}

///|
/// Render an `MbtiDiffReport` as GitHub-flavored Markdown.
pub fn render_mbti_diff_markdown(report : MbtiDiffReport) -> String {
  let out = StringBuilder()
  let verdict = if report.compatible { "COMPATIBLE" } else { "BREAKING" }
  out.write_string("# MoonBit Public API (`.mbti`) Compatibility Report\n\n")
  out.write_string(
    "- **Package**: `\{report.package_name}` | **Verdict**: `\{verdict}`\n",
  )
  out.write_string(
    "- **Breaking Changes**: `\{report.breaking_count}` | **Additive Changes**: `\{report.additive_count}`\n\n",
  )
  if report.changes.is_empty() {
    out.write_string("No public interface changes detected.\n")
  } else {
    out.write_string("| Severity | Category | Symbol | Detail |\n")
    out.write_string("| --- | --- | --- | --- |\n")
    for ch in report.changes {
      out.write_string(
        "| `\{ch.severity}` | `\{ch.category}` | `\{escape_md_cell(ch.symbol)}` | \{escape_md_cell(ch.detail)} |\n",
      )
    }
  }
  out.to_string()
}
