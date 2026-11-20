///|
struct BatchCase {
  id : String
  arguments : Array[String]
}

///|
#derive(ToJson)
struct CaseOutcome {
  id : String
  exit_code : Int
  evidence : String
  error : String?
}

///|
#derive(ToJson)
struct BatchOutcome {
  evidence : String
  cases : Array[CaseOutcome]
}

///|
fn required_field(fields : Map[String, Json], key : String, position : Int) -> String raise StudyError {
  guard fields.get(key) is Some(String(value)) && !value.trim().is_empty() else {
    raise InvalidInput("case \{position}: \{key} must be a nonempty string")
  }
  value
}

///|
fn parse_plan(raw : Json, moon : String, git : String) -> Array[BatchCase] raise StudyError {
  guard raw is Array(entries) && !entries.is_empty() else {
    raise InvalidInput("plan must be a nonempty JSON array")
  }
  let cases : Array[BatchCase] = []
  let seen : Set[String] = Set([])
  for index, entry in entries {
    let position = index + 1
    guard entry is Object(fields) else { raise InvalidInput("case \{position} must be an object") }
    let id = required_field(fields, "id", position)
    guard !seen.contains(id) else { raise InvalidInput("duplicate case id: \{id}") }
    seen.add(id)
    let repository = required_field(fields, "repo", position)
    let revision = required_field(fields, "revision", position)
    let module_dir = required_field(fields, "module", position)
    let dependency = required_field(fields, "dependency", position)
    let before = required_field(fields, "baseline", position)
    let after = required_field(fields, "candidate", position)
    let target = if fields.contains("target") {
      checked_target(required_field(fields, "target", position))
    } else {
      "wasm"
    }
    cases.push({
      id,
      arguments: ["snapshot", moon, git, repository, revision, module_dir, dependency, before, after, target],
    })
  }
  cases
}

///|
async fn batch(args : Array[String]) -> Int {
  guard args.length() == 4 else { raise InvalidInput(usage) }
  let cases = parse_plan(@json.parse(@fs.read_file(args[3]).text()), args[1], args[2])
  let evidence = @fs.tmpdir(prefix="moon-downstream-batch-")
  let outcomes : Array[CaseOutcome] = []
  let mut exit_code = 0
  for index, job in cases {
    let case_dir = "\{evidence}/case-\{index + 1}"
    @fs.mkdir(case_dir)
    let outcome = try {
      let code = snapshot(job.arguments, case_dir, false)
      { id: job.id, exit_code: code, evidence: case_dir, error: None }
    } catch {
      error => { id: job.id, exit_code: 2, evidence: case_dir, error: Some(error.to_string()) }
    }
    outcomes.push(outcome)
    if outcome.exit_code > exit_code { exit_code = outcome.exit_code }
  }
  let report : BatchOutcome = { evidence, cases: outcomes }
  let json = @json.ToJson::to_json(report).stringify()
  @fs.write_file("\{evidence}/batch.json", json)
  println(json)
  exit_code
}
