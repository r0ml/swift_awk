
import ShellTesting

extension awkTest {

  @Suite("T.expr") struct Texpr : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let foo1 = try tmpfile("foo1")
      let foo2 = try tmpfile("foo2")
      let input = try inFile("T.expr.input")
      let prog = try inFile("T.expr.prog")

      try await run(withStdin: input,
                    output: "114 tests\n",
                    args: "-f", prog)
    }
  }
}
