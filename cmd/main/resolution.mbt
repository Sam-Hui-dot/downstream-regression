///|
#derive(ToJson)
struct ResolutionChange {
  requested : String
  baseline : Array[String]
  candidate : Array[String]
}

///|
fn inventory(tree : String) -> Map[String, Array[String]] {
  let all : Map[String, Array[String]] = Map([])
  for raw in tree.split("\n") {
    let line = raw.trim_end()
    let edge_start = match line.find("├─ ") {
      Some(index) => index
      None => match line.find("└─ ") {
        Some(index) => index
        None => continue
      }
    }
    let edge = line[edge_start + 3:]
    guard edge.split_once(" -> ") is Some((requested, destination)) else { continue }
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
fn resolution_changes(
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
      changes.push({ requested: name, baseline: before, candidate: after })
    }
  }
  changes
}
