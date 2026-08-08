// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import ShellTesting

@Suite("awkTest", .serialized) struct awkTest : ShellTest {
  var cmd = "awk"
  var suiteBundle = "awk_awkTest"

  static func getList() -> [String] {
    let j = try? awkTest().geturl()
    let k = try? j!.listDirectory().sorted()

    // t.randk is based on random() -- which is replaced by arc4random() -- so doesn't match
    let k2 = (k!.filter { $0.hasPrefix("expected.") }).filter { !($0 == "expected.t.randk") }
    return k2
  }

  @Test("Checks basic functionality",
        arguments: getList()
        //        arguments: ["expected.p.1"]
  ) func basic(_ f : String) async throws {
    /*    let j = try geturl()
     let k = try j.listDirectory().sorted()

     let k2 = k.filter { $0.hasPrefix("expected.") }
     */
    //    for f in k2 {
    print(f)
    let g = String(f.dropFirst("expected.".count))
    var expected = try fileContents(f)
    if expected == "EMPTY\n" { expected = "" }

    let b = try geturl()
    let inp1 = try inFile(g)

    let env = ["LC_CTYPE": "en_US.LATIN1"]
    if g.first == "t" {
      let inp2 = try inFile("test.data")
      try await run(output: expected, args: "-f", inp1.relativeTo(b), inp2.relativeTo(b), env: env, cd: b)
    } else {
      let inp2 = try inFile("test.countries")
      try await run(output: expected, args: "-f", inp1, inp2.relativeTo(b), inp2.relativeTo(b), env: env, cd: b)

    }


    //    }
  }
}
