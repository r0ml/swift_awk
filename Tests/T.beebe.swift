
import ShellTesting

extension awkTest {

  @Suite("T.beebe") struct Tbeebe : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    static func getList() -> [String] {
      let j = try? awkTest().geturl().appending("beebe")
      let k = try? j!.listDirectory().sorted()

      let k2 = (k!.filter { $0.hasSuffix(".awk") })
      return k2
    }


    @Test("first", .serialized, arguments: getList()) func first(_ s : String) async throws {
      guard s != "strftlng.awk" else {
        print("test for \(s) skipped: tests extension for gawk")
        return
      }
      let inp = try inFile("beebe/\(s)".replacing(".awk", with: ".in"))
      let prog = try inFile("beebe/\(s)")
      let outp = try fileContents("beebe/\(s)".replacing(".awk", with: ".ok"))
      if inp.exists {
        try await run(withStdin: inp, output: outp, error: "", args: "-f", prog)
      } else {
        try await run(output: outp, error: "", args: "-f", prog)
      }
    }
  }
}
