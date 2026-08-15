// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import ShellTesting

extension awkTest {

  @Suite("P.tests") struct Ptests : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"

    static func getList() -> [String] {
      let j = try? awkTest().geturl().appending("ptests")
      let k = try? j!.listDirectory().sorted()

      let k2 = (k!.filter { $0.hasPrefix("expected.") })
      // t.randk and p.48b are based on random() -- which is replaced by drand48() -- so don't match
        .filter { $0 != "expected.p.48b" }
      return k2
    }

    @Test("Checks basic functionality",
          arguments: getList()
    ) func basic(_ f : String) async throws {
      let p = "ptests"
      let g = String(f.dropFirst("expected.".count))
      var expected = try fileContents("\(p)/\(f)")
      if expected == "EMPTY\n" { expected = "" }

      let b = try geturl().appending(p)
      let inp1 = try inFile("\(p)/\(g)")

      let env = ["LC_CTYPE": "en_US.LATIN1"] // "SHELLDEBUGGING" : "1"]

      let inp2 = try inFile("\(p)/test.countries")
      try await run(output: expected, args: "-f", inp1, inp2.relativeTo(b), inp2.relativeTo(b), env: env, cd: b)

    }
  }
}
