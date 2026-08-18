
import ShellTesting

extension awkTest {

  @Suite("T.getline") struct Tgetline : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = """
        BEGIN {
          while (getline)
            print
          exit
        }

        """
        let inp = "This is a sentence.\nAnd this is a second sentence.\n"
      try await run(withStdin: inp, output: inp,
                    args: prog)
    }
    
    @Test("second") func second() async throws {
      let prog = """
        BEGIN {
          while (getline xxx)
            print xxx
          exit
        }

        """
      let inp = "This is a sentence.\nAnd this is a second sentence.\n"
    try await run(withStdin: inp, output: inp,
                  args: prog)

    }
    
    @Test("third") func third() async throws {
      let prog = """
        BEGIN {
          while (getline <"/etc/passwd")
            print
          exit
        }
        
        """
      try await run(output: FilePath("/etc/passwd"),
                                     args: prog)
    }
    
    @Test("fourth") func fourth() async throws {
      let prog = """
        BEGIN {
          while (getline <"-")  # stdin
            print
          exit
        }

        """
      try await run(withStdin: FilePath("/etc/passwd"),
                    output: FilePath("/etc/passwd"),
                    args: prog)
    }
    
    @Test("fifth") func fifth() async throws {
      let prog = """
        BEGIN {
          while (getline <ARGV[1])
            print
          exit
        }
        
        """
      try await run(output: FilePath("/etc/passwd"),
                    args: prog, "/etc/passwd")
    }
    
    @Test("sixth") func sixth() async throws {
      let prog = """
        BEGIN {
          while (getline x <ARGV[1])
            print x
          exit
        }
        
        """
      try await run(output: FilePath("/etc/passwd"),
                    args: prog, "/etc/passwd")
    }
    
    @Test("seventh") func seventh() async throws {
      let prog = """
        BEGIN {
          while (("cat " ARGV[1]) | getline)
            print
          exit
        }
        
        """
      try await run(output: FilePath("/etc/passwd"),
                    args: prog, "/etc/passwd")
    }
    
    @Test("eighth") func eighth() async throws {
      let prog = """
        BEGIN {
          while (("cat " ARGV[1]) | getline x)
            print x
          exit
        }
        
        """
      try await run(output: FilePath("/etc/passwd"),
                    args: prog, "/etc/passwd")
    }
    
    @Test("ninth") func ninth() async throws {
      try await run(output: "-1\n",
                    args: " BEGIN { print getline <\"/glop/glop/glop\" } " )
    }
    
    @Test("tenth") func tenth() async throws {
      let foo1 = try tmpfile("foo1", "false false equal\n")
      let prog = """
        BEGIN {
          "echo 0" | getline
          if ($0) printf "true " 
          else printf "false "
          if ($1) printf "true " 
          else printf "false "
          if ($0==$1) printf "equal\\n"
          else printf "not equal\\n"
        }
        
        """
      defer { rm(foo1) }
      try await run(output: foo1, args: prog)
    }
    
    @Test("eleventh") func eleventh() async throws {
      try await run(withStdin: "L1\nL2\n",
                    output: "new stuff\n",
                    args: #"BEGIN { $0="old stuff"; $1="new"; getline x; print}"#)
    }
  }
}
