
import ShellTesting

extension awkTest {

  @Suite("T.system") struct Tsystem : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("T.system") func T_system() async throws {
      let a = """
    BEGIN {
      n = system("exit 3")
      print n
      exit n+1
    }

    """
      let inp = try inFile("test.countries")
      try await run( status: 4, output: "3\n", args: a, inp )
    }

  }
}
