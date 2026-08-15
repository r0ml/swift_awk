
import ShellTesting

extension awkTest {

  @Suite("T.bugs-fixed") struct TbugsFixed : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    static func getList() -> [String] {
      let j = try? awkTest().geturl().appending("bugs-fixed")
      let k = try? j!.listDirectory().sorted()

      let k2 = (k!.filter { $0.hasSuffix(".awk") })
      return k2
    }


    @Test("first", .serialized, arguments: getList()) func first(_ s : String) async throws {
      let p = "bugs-fixed"
      let inp = try inFile("\(p)/\(s)".replacing(".awk", with: ".in"))
      let prog = try inFile("\(p)/\(s)")
      let outp = try? fileContents("\(p)/\(s)".replacing(".awk", with: ".ok"))
      let err = try? fileContents("\(p)/\(s)".replacing(".awk", with: ".err"))
      let indir = try geturl().appending(p)
      if inp.exists {
        if let err {
          try await run(status: 2, error: Regex<Substring>(verbatim: String(err.dropLast())), args: "-f", prog, inp.relativeTo(indir), cd: indir)
        }
        if let outp {
          try await run(output: outp, error: "", args: "-f", prog, inp.relativeTo(indir), cd: indir)
        }
      } else {
        if let err {
          try await run(status: 2, error: Regex<Substring>(verbatim: String(err.dropLast())), args: "-f", prog, cd: indir)
        }
        if let outp {
          try await run(output: outp, error: "", args: "-f", prog, cd: indir)
        }
      }
    }
  }
}
