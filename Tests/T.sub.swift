
import ShellTesting

extension awkTest {

  @Suite("T.sub") struct Tsub : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = try inFile("T.sub.prog")
      let input = try inFile("T.sub.input")
      try await run(output: "140 tests\n", error: "", args: "-f", prog, input)
    }
  }
}
