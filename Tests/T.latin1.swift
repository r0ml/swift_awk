
import ShellTesting

extension awkTest {

  @Suite("T.latin1") struct Tlatin1 : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"

    let le = IEncoding("latin1")!

    @Test("first") func first() async throws {
      let latin1 = try inFile("latin1")
      let latc = try latin1.readAsString(encoding: IEncoding.latin1)
      try await run(output: latc,
                    args: "{ print $0 }", latin1,
                    encoding: le )
    }
    
    @Test("second") func second() async throws {
      let latin1 = try inFile("latin1")
      try await run(args: "{ gsub(/\\351/,\"\\370\"); print }", latin1,
                    encoding: le) { r in 
//        print(r.string(encoded: le) )
        try await run(output: r.string(encoded: le), args: "{ gsub(/È/, \"¯\"); print }", latin1,
                      encoding: le)
        
      }
    }
    
    @Test("third") func third() async throws {
      let latin1 = try inFile("latin1")
      try await run(args: "{ gsub(/\\300-\\370/,\"\"); print }", latin1, encoding: le) { r in 
        try await run(output: r.string(encoded: le), args: "{ gsub(/[^¿-¯]/, \"\"); print }", latin1, encoding: le)
        
      }
    }
    
    @Test("fourth") func fourth() async throws {
      let s = "/·/\n"
      let foo1 = try tmpfile("foo1", s )
      try await run(output: s, args: "-f", foo1, foo1 )
    }

    @Test("fifth") func fifth() async throws {
      let foo0 = try tmpfile("foo0", """
        This is a line.
        Patterns like /[·È]/ do not work yet. Example, run awk /[·È]/
        over a file containing just ·.
        This is another line.
        
        """)
      let foo1 = """
        Patterns like /[·È]/ do not work yet. Example, run awk /[·È]/
        over a file containing just ·.
        
        """
      let s = "/[·È]/"
      try await run(output: foo1, args: s, foo0 )
    }

    
  }
}

