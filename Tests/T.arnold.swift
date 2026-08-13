
import ShellTesting

extension awkTest {

  @Suite("T.arnold") struct Tarnold : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"

    static func getList() -> [String] {
      let j = try? awkTest().geturl().appending("arnold-fixes")
      let k = try? j!.listDirectory().sorted()

      let k2 = (k!.filter { $0.hasSuffix(".awk") })
      return k2
    }


    @Test("first", arguments: getList()) func first(_ s : String) async throws {
      guard s != "system-status.awk" else {
        print("system-status.awk relies on killing a process and generating a core -- which might be blocked by theOS")
        print("ergo: skipping this test")
        return
      }
      let inp = try inFile("arnold-fixes/\(s)")
      let outp = try fileContents("arnold-fixes/\(s)".replacing(".awk", with: ".ok"))
      try await run(output: outp, args: "-f", inp)
    }
  }
}

