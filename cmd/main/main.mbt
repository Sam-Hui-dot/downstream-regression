///|
struct Variant {
  dir : String
  version : String
  label : String
}

///|
let usage : String =
  #|downstream-regression [--out DIR] MOON DEPENDENCY BASE_DIR BASE_VERSION CANDIDATE_DIR CANDIDATE_VERSION [TARGET]
  #|downstream-regression [--out DIR] snapshot MOON GIT REPO REV MODULE_DIR DEPENDENCY BASE_VERSION CANDIDATE_VERSION [TARGET]
  #|downstream-regression [--out DIR] batch MOON GIT PLAN_JSON
  #|downstream-regression mbti-diff OLD_MBTI NEW_MBTI [--format text|json|md] [--fail-on-breaking] [--out FILE]
  #|TARGET defaults to wasm and can also be native, wasm-gc or js.

///|
async fn execute(
  moon : String,
  variant : Variant,
  dependency : String,
  target : String,
  evidence : String,
) -> @downstream-regression.Trial {
  let (tree_code, tree) = logged_moon(
    moon,
    ["-C", variant.dir, "tree"],
    "\{evidence}/\{variant.label}-tree.txt",
    timeout_ms=60_000,
  )
  guard tree_code == 0 else {
    raise @downstream-regression.tool_failed(
      "\{variant.label}: moon tree exited \{tree_code}",
    )
  }
  let expected = "\{dependency}@\{variant.version}"
  guard @downstream-regression.parse_direct_versions(tree, dependency) ==
    [expected] else {
    raise @downstream-regression.tool_failed(
      "\{variant.label}: expected exactly one registry edge to \{expected}",
    )
  }
  let downstream = @downstream-regression.parse_tree_root(tree)
  guard !downstream.is_empty() else {
    raise @downstream-regression.tool_failed(
      "\{variant.label}: failed to identify downstream module",
    )
  }
  let (exit_code, log) = logged_moon(
    moon,
    ["-C", variant.dir, "test", "--target", target],
    "\{evidence}/\{variant.label}-test.txt",
    timeout_ms=600_000,
  )
  {
    directory: variant.dir,
    downstream,
    dependency: expected,
    exit_code,
    counts: @downstream-regression.parse_test_counts(log),
    failures: @downstream-regression.parse_failure_records(log),
    compiler_errors: @downstream-regression.parse_compiler_errors(log),
    resolutions: @downstream-regression.parse_dependency_inventory(tree),
  }
}

///|
async fn run_comparison(
  moon : String,
  dependency : String,
  baseline : Variant,
  candidate : Variant,
  target : String,
  evidence : String,
  print_report : Bool,
) -> (Int32, @downstream-regression.Comparison) {
  try {
    let (version_status, toolchain) = logged_moon(
      moon,
      ["version", "--all"],
      "\{evidence}/toolchain.txt",
      timeout_ms=30_000,
    )
    guard version_status == 0 else {
      raise @downstream-regression.tool_failed(
        "moon version --all exited \{version_status}",
      )
    }
    let left = execute(moon, baseline, dependency, target, evidence)
    let right = execute(moon, candidate, dependency, target, evidence)
    guard left.downstream == right.downstream else {
      raise @downstream-regression.tool_failed(
        "downstream module differs: \{left.downstream} vs \{right.downstream}",
      )
    }
    let report = @downstream-regression.compare_trials(
      left, right, dependency, target, evidence,
    )
    let json = @json.ToJson::to_json(report).stringify()
    @fs.write_file(
      "\{evidence}/report.json",
      json,
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{evidence}/report.md",
      @downstream-regression.render_markdown_report(report, toolchain~),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{evidence}/report.html",
      @downstream-regression.render_html_report(report, toolchain~),
      create_mode=CreateOrTruncate,
    )
    if print_report {
      println(json)
    }
    (@downstream-regression.exit_code_for_status(report.status), report)
  } catch {
    error =>
      raise @downstream-regression.tool_failed(
        "\{@downstream-regression.error_message(error)}; logs: \{evidence}",
      )
  }
}

///|
async fn git_step(
  git : String,
  args : Array[String],
  log_path : String,
) -> String {
  let (code, stdout, stderr) = @process.collect_output(git, args)
  @fs.write_file(
    log_path,
    "\{stdout.text()}\n\{stderr.text()}",
    create_mode=CreateOrTruncate,
  )
  guard code == 0 else {
    raise @downstream-regression.tool_failed(
      "git exited \{code}; see \{log_path}",
    )
  }
  stdout.text().trim().to_owned()
}

///|
async fn detect_manifest(
  module_path : String,
  evidence : String,
) -> (@downstream-regression.ManifestKind, String) {
  let moon_mod = "\{module_path}/moon.mod"
  if @fs.exists(moon_mod) {
    guard @fs.kind(moon_mod, follow_symlink=false) is Regular else {
      raise @downstream-regression.StudyError::InvalidInput(
        "snapshot mode requires a regular moon.mod file; see \{evidence}",
      )
    }
    return (MoonMod, moon_mod)
  }
  let moon_mod_json = "\{module_path}/moon.mod.json"
  if @fs.exists(moon_mod_json) {
    guard @fs.kind(moon_mod_json, follow_symlink=false) is Regular else {
      raise @downstream-regression.StudyError::InvalidInput(
        "snapshot mode requires a regular moon.mod.json file; see \{evidence}",
      )
    }
    return (MoonModJson, moon_mod_json)
  }
  raise @downstream-regression.StudyError::InvalidInput(
    "snapshot mode requires a regular moon.mod or moon.mod.json file; see \{evidence}",
  )
}

///|
async fn snapshot(
  args : Array[String],
  evidence : String,
  print_report : Bool,
) -> (Int32, @downstream-regression.Comparison) {
  guard args.length() == 9 || args.length() == 10 else {
    raise @downstream-regression.StudyError::InvalidInput(usage)
  }
  let moon = args[1]
  let git = args[2]
  let repository = @fs.realpath(args[3])
  let module_dir = args[5]
  let dependency = args[6]
  let baseline_version = args[7]
  let candidate_version = args[8]
  let target = @downstream-regression.validate_target(
    if args.length() == 10 {
      args[9]
    } else {
      "wasm"
    },
  )
  guard baseline_version != candidate_version else {
    raise @downstream-regression.StudyError::InvalidInput(
      "use two distinct dependency versions",
    )
  }
  @downstream-regression.validate_module_dir(module_dir)
  let revision = git_step(
    git,
    [
      "-C",
      repository,
      "rev-parse",
      "--verify",
      "--end-of-options",
      "\{args[4]}^{commit}",
    ],
    "\{evidence}/revision.txt",
  )
  let mut manifest_info : (@downstream-regression.ManifestKind, String)? = None
  for label in ["baseline", "candidate"] {
    let checkout = "\{evidence}/\{label}"
    guard !@fs.exists(checkout) else {
      raise @downstream-regression.StudyError::InvalidInput(
        "evidence directory already contains \{label}; use a fresh --out path",
      )
    }
    ignore(
      git_step(
        git,
        [
          "clone", "--local", "--no-hardlinks", "--no-checkout", "--", repository,
          checkout,
        ],
        "\{evidence}/\{label}-clone.txt",
      ),
    )
    ignore(
      git_step(
        git,
        ["-C", checkout, "checkout", "--detach", revision],
        "\{evidence}/\{label}-checkout.txt",
      ),
    )
    // Reject symlinks in the module path and manifest before changing the copy.
    let mut path = checkout
    for component in module_dir.split("/") {
      path = "\{path}/\{component}"
      guard @fs.kind(path, follow_symlink=false) is Directory else {
        raise @downstream-regression.StudyError::InvalidInput(
          "module path must consist of directories; see \{evidence}",
        )
      }
    }
    let detected = detect_manifest(path, evidence)
    if label == "candidate" {
      manifest_info = Some(detected)
    }
  }
  let (manifest_kind, manifest_path) = match manifest_info {
    Some(info) => info
    None =>
      raise @downstream-regression.tool_failed(
        "failed to resolve candidate manifest; see \{evidence}",
      )
  }
  let manifest = @fs.read_file(manifest_path).text()
  let updated = @downstream-regression.rewrite_manifest_dependency(
    manifest_kind, manifest, dependency, baseline_version, candidate_version,
  ) catch {
    error =>
      raise @downstream-regression.StudyError::InvalidInput(
        "\{@downstream-regression.error_message(error)}; see \{evidence}",
      )
  }
  @fs.write_file(manifest_path, updated, create_mode=CreateOrTruncate)
  let baseline_dir = "\{evidence}/baseline/\{module_dir}"
  let candidate_dir = "\{evidence}/candidate/\{module_dir}"
  run_comparison(
    moon,
    dependency,
    { dir: baseline_dir, version: baseline_version, label: "baseline", },
    { dir: candidate_dir, version: candidate_version, label: "candidate", },
    target,
    evidence,
    print_report,
  )
}

///|
async fn cmd_mbti_diff(args : Array[String], out_file : String?) -> Int32 {
  guard args.length() >= 3 else {
    raise @downstream-regression.StudyError::InvalidInput(usage)
  }
  let old_path = args[1]
  let new_path = args[2]
  let mut format = "text"
  let mut fail_on_breaking = false
  let mut i = 3
  while i < args.length() {
    match args[i] {
      "--format" => {
        guard i + 1 < args.length() else {
          raise @downstream-regression.StudyError::InvalidInput(
            "--format requires a value",
          )
        }
        format = args[i + 1]
        i += 2
      }
      "--fail-on-breaking" => {
        fail_on_breaking = true
        i += 1
      }
      other =>
        raise @downstream-regression.StudyError::InvalidInput(
          "unknown option: \{other}",
        )
    }
  }
  let old_text = @fs.read_file(old_path).text()
  let new_text = @fs.read_file(new_path).text()
  let report = @downstream-regression.diff_mbti(old_text, new_text)
  let rendered = match format {
    "text" => @downstream-regression.render_mbti_diff_text(report)
    "json" => @json.ToJson::to_json(report).stringify()
    "md" | "markdown" =>
      @downstream-regression.render_mbti_diff_markdown(report)
    _ =>
      raise @downstream-regression.StudyError::InvalidInput(
        "unsupported --format value: \{format}",
      )
  }
  match out_file {
    Some(path) => @fs.write_file(path, rendered, create_mode=CreateOrTruncate)
    None => println(rendered)
  }
  if fail_on_breaking && !report.compatible {
    1
  } else {
    0
  }
}

///|
async fn run(raw_args : Array[String]) -> Int32 {
  let (out_dir, args) = @downstream-regression.extract_out_option(raw_args)
  match args.get(0) {
    Some("mbti-diff") => return cmd_mbti_diff(args, out_dir)
    Some("snapshot") => {
      let evidence = prepare_evidence_dir(out_dir, "moon-downstream-")
      let (code, _) = snapshot(args, evidence, true)
      return code
    }
    Some("batch") => return batch(args, out_dir)
    _ => ()
  }
  guard args.length() == 6 || args.length() == 7 else {
    raise @downstream-regression.StudyError::InvalidInput(usage)
  }
  let baseline_dir = @fs.realpath(args[2])
  let candidate_dir = @fs.realpath(args[4])
  guard baseline_dir != candidate_dir else {
    raise @downstream-regression.StudyError::InvalidInput(
      "use two separate project directories",
    )
  }
  guard args[3] != args[5] else {
    raise @downstream-regression.StudyError::InvalidInput(
      "use two distinct dependency versions",
    )
  }
  let target = @downstream-regression.validate_target(
    if args.length() == 7 {
      args[6]
    } else {
      "wasm"
    },
  )
  let evidence = prepare_evidence_dir(out_dir, "moon-downstream-")
  let (code, _) = run_comparison(
    args[0],
    args[1],
    { dir: baseline_dir, version: args[3], label: "baseline", },
    { dir: candidate_dir, version: args[5], label: "candidate", },
    target,
    evidence,
    true,
  )
  code
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && args[1] == "--help" {
    println(usage)
    return
  }
  let exit_code = run(args[1:].to_owned()) catch {
    error => {
      println(@downstream-regression.error_message(error))
      2
    }
  }
  @env.exit(exit_code)
}
