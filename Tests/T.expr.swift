
import ShellTesting

extension awkTest {

  @Suite("T.expr") struct Texpr : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let input = try inFile("T.expr.input")
      let prog = try inFile("T.expr.prog")

      try await run(withStdin: input,
                    output: "114 tests\n",
                    args: "-f", prog)
      // FIXME: the prog here creates files foo1 and foo2
      // which I need to delete
    }
  }
}
