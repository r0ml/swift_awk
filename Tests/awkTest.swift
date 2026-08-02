// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import ShellTesting

struct awkTest : ShellTest {
  var cmd = "awk"
  var suiteBundle = "awk_awkTest"

  @Test("Checks basic functionality") func basic() async throws {
    let expected = try fileContents("expected.p.1")
    let inp1 = try inFile("p.1")
    let inp2 = try inFile("test.countries")

    try await run(output: expected, args: "-f", inp1, inp2)
  }
}
