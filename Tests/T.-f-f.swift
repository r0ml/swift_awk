
import ShellTesting

extension awkTest {

  @Suite("T.f-f") struct Tf_f : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let foo1 = try tmpfile("foo1", "BEGIN { print \"begin\" }")
      let foo2 = try tmpfile("foo2", "END { print \"end\" }")
      defer { rm(foo1, foo2) }
      try await run(withStdin: "xxx\n", output: "begin\nend\n", args: "-f", foo1, "-f", foo2)
    }

    @Test("second") func second() async throws {
      let foo1 = try tmpfile("foo1", "BEGIN { print \"begin\" }")
      let foo2 = try tmpfile("foo2", "END { print \"end\" }")
      defer { rm(foo1, foo2) }
      try await run(withStdin: "xxx\n", output: "begin\nend\n", args: "-f", foo1, "-f", foo2)
    }

    @Test("third") func third() async throws {
      let foo2 = try tmpfile("foo2", "/./ {\n")
      let foo3 = try tmpfile("foo3", "print\n")
      let foo4 = try tmpfile("foo4", "}\n")
      let foo1 = FilePath("/etc/passwd")
      let foo1c = try foo1.readAsString()
      defer { rm(foo2, foo3, foo4) }

      try await run(output: foo1c, args: "-f", foo2, "-f", foo3, "-f", foo4, foo1)
    }

    @Test("fourth") func fourth() async throws {
      let foo2 = try tmpfile("foo2", "/./ {\n")
      let foo3 = try tmpfile("foo3", "print\n")
      let foo4 = try tmpfile("foo4", "\n\n\n\n]\n")
      let foo1 = FilePath("/etc/passwd")
      defer { rm(foo2, foo3, foo4) }
      try await run(status: 2, error: /lexical error/, args: "-f", foo2, "-f", foo2, "-f", foo3, "-f", foo4, foo1)
    }
  }
}
