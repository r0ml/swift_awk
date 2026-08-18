// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import ShellTesting

extension awkTest {

  @Suite("T.tests") struct Ttests : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"

    static func getList() -> [String] {
      let j = try? awkTest().geturl().appending("ttests")
      let k = try? j!.listDirectory().sorted()

      let k2 = (k!.filter { $0.hasPrefix("expected.") })
      // t.randk and p.48b are based on random() -- which is replaced by drand48() -- so don't match
        .filter { $0 != "expected.t.randk" }
      return k2
    }

    @Test("Checks basic functionality",
          arguments: getList()
    ) func basic(_ f : String) async throws {
      let p = "ttests"
      let g = String(f.dropFirst("expected.".count))
      var expected = try fileContents("\(p)/\(f)", encoding: .latin1)
      if expected == "EMPTY\n" { expected = "" }

      let b = try geturl().appending(p)
      let inp1 = try inFile("\(p)/\(g)")

      let inp2 = try inFile("\(p)/test.data")

      // t.exit / t.exit1 deliberately call `exit <n>` to test that awk's own exit
      // status follows the exit expression, so (unlike every other fixture here) they
      // can't be checked against the default expected status of 0.
      let status = ["t.exit": 1, "t.exit1": 2][g] ?? 0
      try await run(status: status, output: expected, args: "-f", inp1, inp2.relativeTo(b), cd: b, encoding: .latin1)

    }
  }
}
