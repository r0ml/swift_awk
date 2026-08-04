// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import ShellTesting

@Suite("awkTest", .serialized) struct awkTest : ShellTest {
  var cmd = "awk"
  var suiteBundle = "awk_awkTest"

  static func getList() -> [String] {
    let j = try? awkTest().geturl()
    let k = try? j!.listDirectory().sorted()

    let k2 = k!.filter { $0.hasPrefix("expected.") }
    return k2
  }

  @Test("Checks basic functionality",
        arguments: getList()[0..<34]
        //        arguments: ["expected.p.1"]
  ) func basic(_ f : String) async throws {
/*    let j = try geturl()
    let k = try j.listDirectory().sorted()

    let k2 = k.filter { $0.hasPrefix("expected.") }
*/
//    for f in k2 {
      print(f)
    let g = String(f.dropFirst("expected.".count))
      let expected = try fileContents(f)
      let inp1 = try inFile(g)

    if g.first == "t" {
      let inp2 = try inFile("test.data")
      try await run(output: expected, args: "-f", inp1, inp2)
    } else {
      let inp2 = try inFile("test.countries")
      try await run(output: expected, args: "-f", inp1, inp2, inp2)

    }

    
//    }
  }
}
