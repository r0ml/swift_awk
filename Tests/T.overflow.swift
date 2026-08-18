
import ShellTesting

extension awkTest {

  @Suite("T.overflow") struct Toverflow : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let foo1 = try tmpfile("foo1","")
      defer { rm(foo1) }
      let prog = """
        BEGIN {
           for (i = 0; i < 1000; i++) printf("abcdefghijklmnopqsrtuvwxyz") >>"\(foo1)"
           printf("\\n") >>"\(foo1)"
           exit
        }
        
        """
      try await run(args: prog) {r in 
        let foo1 = try tmpfile("foo1", r.data)
        defer { rm(foo1) }
        try await run(output: foo1, args: "{print}", foo1)
      }
      
    }
    
    @Test("second") func second() async throws {
      let foo1 = try tmpfile("foo1", "abcdefghijklmnopqsrtuvwxyz\n")
      defer { rm(foo1) }
      let prog = """
         { for (i = 1; i < 500; i++) s = s "abcdefghijklmnopqsrtuvwxyz "
           $0 = s
           print $1
         }
        
        """
      try await run(withStdin: "hello\n",
                    output: foo1,
                    args: prog)
    }
    
    @Test("third") func third() async throws {
      let prog = """
        BEGIN {
          for (j = 0; j < 2; j++) {
            for (i = 0; i < 500; i++)
              printf(" 123456789")
            printf("\\n");
          }
        } 
        
        """
      try await run(args: prog) { r in
        let foo1 = try tmpfile("foo1", r.data)
        try await run(output: foo1,
                      args: #"{$1 = " 123456789"; print}"#, foo1)
      }
    }
    
    @Test("fourth") func fourth() async throws {
      let prog = """
        BEGIN {
          for (j = 0; j < 2; j++) {
            for (i = 0; i < 500; i++)
              printf(" 123456789")
            printf("\\n");
          }
        }
        
        """
      try await run(args: prog) { r in
        let foo1 = try tmpfile("foo1", r.data)
        try await run(output: "500\n500\n",
                      args: #"{ print NF}"#, foo1)
      }
    }
    
    @Test("fifth") func fifth() async throws {
      let prog = """
        BEGIN {
          for (i = 1; i < 1000; i++) s = s "a-z"
          if ("x" ~ "[" s "]")
            print "ugh"
        }
        
        """
      try await run(status: 0, error: "", args: prog)
    }
    
    
    @Test("sixth") func sixth() async throws {
      let prog = """
        BEGIN {
          x1 = sprintf("%1000000s\\n", "hello")
          x2 = sprintf("%-1000000s\\n", "world")
          x3 = sprintf("%1000000.1000000s\\n", "goodbye")
          x4 = sprintf("%-1000000.1000000s\\n", "goodbye")
          print length(x1 x2 x3 x4)
        }
        """
      try await run(output: "4000004\n",
                    args: prog)
    }
    
    // FIXME: was 100000, but that took forever
    @Test("seventh") func seventh() async throws {
      let prog = """
        BEGIN {
          for (i = 0; i < 100; i++)
            x[i] = i
          for (i in x)
            delete x[i]
          n = 0
          for (i in x)
            n++
          print n
        }
        
        """
      try await run(output: "0\n",
                    args: prog)
    }
    
    @Test("eighth") func eighth() async throws {
      let prog = "{print $40000000000000}"
      try await run(withStdin: "x\n", status: 2, error: /out of range/, args: prog)
    }
    
    @Test("ninth") func ninth() async throws {
      let t = try tmpdir("awktest")
      let tt = try tmpfile("awktest/foo")
      defer { rm(t) }
      let prog = """
        BEGIN { for (i=1; i <= 1000; i++) print i >("\(tt)" i) }
        
        """
      print("DEBUG prog=\(prog)")
      try await run(status: 0, output: "", args: prog) { r in
        let k = try t.listDirectory()
        print("DEBUG listing count=\(k.count) sample=\(k.prefix(5))")
        #expect(k.count == 1000)
      }
      
    }
    
    
    

  }
}
