
import ShellTesting

extension awkTest {

  @Suite("T.main") struct Tmain : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"

    @Test("T.main.1") func T_main_1() async throws {
      try await run(withStdin: "a::b::c\n", output: "3\n", args: "-F::", "{print NF}")
    }

    @Test("T.main.2") func T_main_2() async throws {
      try await run(withStdin: "a::b::c\n", output: "3\n", args: "-F", "::", "{print NF}")
    }

    @Test("T.main.3") func T_main_3() async throws {
      try await run(withStdin: "a b c\n", output: "3\n", args: "-F", "t", "{print NF}")
    }

    @Test("T.main.4") func T_main_4() async throws {
      try await run(withStdin: "atabbtabc\n", output: "3\n", args: "-F", "tab", "{print NF}")
    }
  }
}
