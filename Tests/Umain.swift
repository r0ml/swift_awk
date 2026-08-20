// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import ShellTesting

extension awkTest {

  @Suite("U.main") struct Umain : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      try await run(status: 1, error: /usage/, args: [])
    }

    @Test("second", arguments: [
      ("-F:", "no program given"),
    ]) func second(_ s : String, _ t : String) async throws {
      try await run(status: 2, error: Regex(t), args: s)
    }
    
    @Test("third", arguments: [
      ("-f", "option requires an argument"),
      ("-zzz", "illegal option"),
      ("-F", "option requires an argument"),
    ]) func third(_ s : String, _ t : String) async throws {
      try await run(status: 1, error: Regex(t), args: s)
    }


  }
}
