///|
/// Errors raised for invalid user input or external tool failures.
#derive(Debug, Eq)
pub(all) suberror StudyError {
  InvalidInput(String)
  ToolFailed(String)
}

///|
pub extend StudyError with @debug.Debug::{to_repr}

///|
pub extend StudyError with Eq::{not_equal, equal}

///|
/// Construct a `StudyError::ToolFailed` error with a diagnostic message.
pub fn tool_failed(message : String) -> StudyError {
  ToolFailed(message)
}

///|
/// Convert any MoonBit error into a concise human-readable diagnostic message.
pub fn error_message(error : Error) -> String {
  match error {
    InvalidInput(message) | ToolFailed(message) => message
    other => other.to_string()
  }
}

///|
/// Supported manifest formats for rewriting direct registry dependencies.
#derive(Debug, Eq)
pub(all) enum ManifestKind {
  MoonMod
  MoonModJson
}

///|
pub extend ManifestKind with @debug.Debug::{to_repr}

///|
pub extend ManifestKind with Eq::{not_equal, equal}

///|
/// Parsed summary counts from a `moon test` invocation.
#derive(Debug, Eq, ToJson)
pub(all) struct TestCounts {
  total : Int32
  passed : Int32
  failed : Int32
  skipped : Int32
}

///|
pub extend TestCounts with @debug.Debug::{to_repr}

///|
pub extend TestCounts with Eq::{not_equal, equal}

///|
pub extend TestCounts with @json.ToJson::{to_json}

///|
/// A non-target dependency whose resolved coordinates differed between trials.
#derive(Debug, Eq, ToJson)
pub(all) struct ResolutionChange {
  requested : String
  baseline : Array[String]
  candidate : Array[String]
}

///|
pub extend ResolutionChange with @debug.Debug::{to_repr}

///|
pub extend ResolutionChange with Eq::{not_equal, equal}

///|
pub extend ResolutionChange with @json.ToJson::{to_json}

///|
/// Observed dependency resolution, exit status, and test outcome for one variant.
#derive(Debug, Eq, ToJson)
pub(all) struct Trial {
  directory : String
  downstream : String
  dependency : String
  exit_code : Int32
  counts : TestCounts?
  failures : Map[String, String]
  compiler_errors : Array[String]
  resolutions : Map[String, Array[String]]
}

///|
pub extend Trial with @debug.Debug::{to_repr}

///|
pub extend Trial with Eq::{not_equal, equal}

///|
pub extend Trial with @json.ToJson::{to_json}

///|
/// Structured comparison result between a baseline trial and a candidate trial.
#derive(Debug, Eq, ToJson)
pub(all) struct Comparison {
  status : String
  baseline : Trial
  candidate : Trial
  new_failures : Map[String, String]
  fixed_failures : Map[String, String]
  changed_failure_messages : Map[String, String]
  other_dependency_changes : Array[ResolutionChange]
  target : String
  evidence : String
}

///|
pub extend Comparison with @debug.Debug::{to_repr}

///|
pub extend Comparison with Eq::{not_equal, equal}

///|
pub extend Comparison with @json.ToJson::{to_json}

///|
/// A validated entry from a batch comparison JSON plan.
#derive(Debug, Eq)
pub(all) struct BatchCase {
  id : String
  repo : String
  revision : String
  module_dir : String
  dependency : String
  baseline : String
  candidate : String
  target : String
}

///|
pub extend BatchCase with @debug.Debug::{to_repr}

///|
pub extend BatchCase with Eq::{not_equal, equal}

///|
/// Summary of a single case inside a batch run.
#derive(Debug, Eq, ToJson)
pub(all) struct CaseOutcome {
  id : String
  status : String?
  exit_code : Int32
  baseline_counts : TestCounts?
  candidate_counts : TestCounts?
  new_failure_count : Int32
  compiler_error_count : Int32
  evidence : String
  error : String?
}

///|
pub extend CaseOutcome with @debug.Debug::{to_repr}

///|
pub extend CaseOutcome with Eq::{not_equal, equal}

///|
pub extend CaseOutcome with @json.ToJson::{to_json}

///|
/// Aggregated outcome of a batch comparison run.
#derive(Debug, Eq, ToJson)
pub(all) struct BatchOutcome {
  evidence : String
  cases : Array[CaseOutcome]
}

///|
pub extend BatchOutcome with @debug.Debug::{to_repr}

///|
pub extend BatchOutcome with Eq::{not_equal, equal}

///|
pub extend BatchOutcome with @json.ToJson::{to_json}
