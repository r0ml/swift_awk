
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
      guard s != "clsflnam.awk" else {
        print("test for \(s) skipped: not sure what the right thing to do here is")
        return
      }


      let inp = try inFile("beebe/\(s)".replacing(".awk", with: ".in"))
      let prog = try inFile("beebe/\(s)")
      let outp = try? fileContents("beebe/\(s)".replacing(".awk", with: ".ok"))
      let err = try? fileContents("beebe/\(s)".replacing(".awk", with: ".err"))
      let indir = try geturl().appending("beebe")
      if inp.exists {
        if let err {
          try await run(status: 2, error: Regex<Substring>(verbatim: String(err.dropLast())), args: "-f", prog, inp.relativeTo(indir), cd: indir)
        }
        if let outp {
          try await run(output: outp, error: "", args: "-f", prog, inp.relativeTo(indir), cd: indir)
        }
      } else {
        if let err {
          try await run(status: 2, error: Regex<Substring>(verbatim: String(err.dropLast())), args: "-f", prog)
        }
        if let outp {
          try await run(output: outp, error: "", args: "-f", prog)
        }
      }
    }
  }
}
