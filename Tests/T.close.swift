
import ShellTesting

extension awkTest {

  @Suite("T.close") struct Tclose : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let cd = try tmpfile("foo", "")
      defer { rm(cd) }
      let cc = "{print >>\"\(cd.string)\"; close(\"\(cd.string)\") }"
      print(cc)
      try await run(args: cc,
                    "/etc/passwd") { op in
        let a = try cd.readAsString()
        let b = try FilePath("/etc/passwd").readAsString()
        #expect(a == b)
      }
    }

    @Test("second") func second() async throws {
      let foo = try tmpfile("foo", "one\ntwo\nthree\nfour\n")
      let foo2 = try tmpfile("foo2")
      defer { rm(foo, foo2) }
      try await run(args: "{ print >\"\(foo2)\"; close(\"\(foo2)\") }", foo
//                    , env: ["SHELLDEBUGGING": "1"]
      ) {_ in
        let a = try foo2.readAsString()
        #expect(a == "four\n")
      }
    }

    @Test("third") func third() async throws {
      try await run(output: "0\n",
                    args: "BEGIN { getline <\"/etc/passwd\"; print close(\"/etc/passwd\"); } " )

    }

    @Test("fourth") func fourth() async throws {
      try await run(output: "-1\n",
                    args: "BEGIN { print close(\"glotch\"); } " )
    }

    @Test("fifth") func fifth() async throws {
      let foo = try tmpfile("foo")
      defer { rm(foo) }
      try await run(output: "0\n",
                    args: "BEGIN { print \"hello\" >\"\(foo)\"; print close(\"\(foo)\"); }")
    }

    @Test("sixth") func sixth() async throws {
      let foo = try tmpfile("foo")
      defer { rm(foo) }
      try await run(output: "0\n",
                    args: "BEGIN { print \"hello\" | \"cat >\(foo)\"; print close(\"cat >\(foo)\") }")
    }
  }

}
