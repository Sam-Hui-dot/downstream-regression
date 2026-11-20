///|
async test "async dependency exposes cancellation wrapper" {
  let result = @async.handle_cancellation(() => 42)
  assert_true(result is Some(42))
}
