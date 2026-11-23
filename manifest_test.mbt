///|
test "rewrite_manifest_dependency updates moon.mod exactly once" {
  let manifest =
    #|name = "demo/app"
    #|version = "0.1.0"
    #|import {
    #|  "moonbitlang/async@0.21.0",
    #|  "moonbitlang/async-extra@0.21.0",
    #|}
  let updated = @downstream-regression.rewrite_manifest_dependency(
    MoonMod,
    manifest,
    "moonbitlang/async",
    "0.21.0",
    "0.22.0",
  )
  assert_true(updated.contains("\"moonbitlang/async@0.22.0\""))
  assert_true(updated.contains("\"moonbitlang/async-extra@0.21.0\""))
}

///|
test "rewrite_manifest_dependency rejects missing or duplicate moon.mod pins" {
  let missing =
    #|name = "demo/app"
    #|import { "moonbitlang/async@0.20.0" }
  try
    @downstream-regression.rewrite_manifest_dependency(
      MoonMod,
      missing,
      "moonbitlang/async",
      "0.21.0",
      "0.22.0",
    )
  catch {
    InvalidInput(msg) => assert_true(msg.contains("expected one occurrence"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("missing pin must fail")
  }

  let duplicate =
    #|import { "moonbitlang/async@0.21.0" }
    #|// "moonbitlang/async@0.21.0"
  try
    @downstream-regression.rewrite_manifest_dependency(
      MoonMod,
      duplicate,
      "moonbitlang/async",
      "0.21.0",
      "0.22.0",
    )
  catch {
    InvalidInput(msg) => assert_true(msg.contains("expected one occurrence"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("duplicate pin must fail")
  }
}

///|
test "rewrite_manifest_dependency updates moon.mod.json while preserving formatting" {
  let manifest =
    #|{
    #|  "name": "demo/legacy",
    #|  "version": "0.1.0",
    #|  "deps": {
    #|    "moonbitlang/async": "0.21.0",
    #|    "moonbitlang/async-extra": "0.21.0",
    #|    "moonbitlang/x": "0.4.1"
    #|  }
    #|}
  let updated = @downstream-regression.rewrite_manifest_dependency(
    MoonModJson,
    manifest,
    "moonbitlang/async",
    "0.21.0",
    "0.22.0",
  )
  assert_true(updated.contains("\"moonbitlang/async\": \"0.22.0\""))
  assert_true(updated.contains("\"moonbitlang/async-extra\": \"0.21.0\""))
  assert_true(updated.contains("\"moonbitlang/x\": \"0.4.1\""))
}

///|
test "rewrite_manifest_dependency rejects invalid moon.mod.json or mismatched version" {
  let mismatched =
    #|{
    #|  "name": "demo/legacy",
    #|  "deps": { "moonbitlang/async": "0.20.0" }
    #|}
  try
    @downstream-regression.rewrite_manifest_dependency(
      MoonModJson,
      mismatched,
      "moonbitlang/async",
      "0.21.0",
      "0.22.0",
    )
  catch {
    InvalidInput(msg) => assert_true(msg.contains("expected deps"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("mismatched json version must fail")
  }

  try
    @downstream-regression.rewrite_manifest_dependency(
      MoonModJson,
      "{ not valid json",
      "moonbitlang/async",
      "0.21.0",
      "0.22.0",
    )
  catch {
    InvalidInput(msg) => assert_true(msg.contains("invalid moon.mod.json"))
    _ => fail("expected InvalidInput")
  } noraise {
    _ => fail("malformed json must fail")
  }
}
