
import ShellTesting

extension awkTest {

  @Suite("T.redir") struct Tredir : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"

    @Test("first") func first() async throws {
      let t = try tmpfile("foo")
      let p = FilePath("/etc/passwd")
      defer { rm(t) }
      let po = try p.readAsString()
      try await run(args: "{print >\"\(t)\" }",
                    p) { _ in 
        let k = try t.readAsString()
        #expect(po == k)
      }
    }

    @Test("second") func second() async throws {
      let t = try tmpfile("foo")
      rm(t)
      defer { rm(t) }
      let p = FilePath("/etc/passwd")
      let po = try p.readAsString()
      try await run(args: "{print >>\"\(t)\" }",
                    p) { _ in 
        let k = try t.readAsString()
        #expect(po == k)
      }
    }

    @Test("third") func third() async throws {
      let t = try tmpfile("foo")
      rm(t)
      defer { rm(t) }
      let p = FilePath("/etc/passwd")
      let po = try p.readAsString()
      try await run(args: "{print | \"cat >\(t)\" }",
                    p) { _ in 
        let k = try t.readAsString()
        #expect(po == k)
      }      
    }

    @Test("fourth") func fourth() async throws {
      let prog = """
        BEGIN { print "   head"
          for (i = 1; i < 3; i++)
            print i | "sort" }
        
        """
      let output = """
           head
        1
        2
        
        """
      try await run(output: output,
                    args: prog)
    }

    @Test("fifth") func fifth() async throws {
      let p = FilePath("/etc/passwd")
      let po = try p.readAsString()
      try await run(output: "", error: po,
                    args: "{ print >\"/dev/stderr\" }", p)
    }

    @Test("sixth") func sixth() async throws {
      let p = FilePath("/etc/passwd")
      let po = try p.readAsString()
      try await run(output: po, error: "",
                    args: "{ print >\"/dev/stdout\" }", p)
    }

    // out of order from the original -- was third test
    @Test("seventh") func seventh() async throws {
      let t = try tmpfile("foo")
      rm(t)
      defer { rm(t) }
      let prog = """
        NR%2 == 1 { print >>"\(t)" }
        NR%2 == 0 { print >"\(t)" }
        
        """
      let p = FilePath("/etc/passwd")
      let po = try p.readAsString()
      
      try await run(args: prog, p) {_ in 
        let k = try t.readAsString()
        #expect(po == k)
      }
    }


  }
}
