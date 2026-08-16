
import ShellTesting

extension awkTest {

  @Suite("T.split") struct Tsplit : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = """
        BEGIN {
          # Assign string to $0, then change FS.
          FS = ":"
          $0="a:bc:def"
          FS = "-"
          print FS, $1, NF

          # Assign number to $0, then change FS.
          FS = "2"
          $0=1212121
          FS="3"
          print FS, $1, NF
        }
        
        """
      try await run(output: "- a 3\n3 1 4\n",
                    args: prog)
    }

    @Test("second") func second() async throws {
      let prog = """
        BEGIN {
          # FS changes after getline.
          FS = ":"
          "echo a:bc:def" | getline
          FS = "-"
          print FS, $1, NF
        }
        
        """
      try await run(output: "- a 3\n", args: prog)
    }

    @Test("third") func third() async throws {
      let temp0 = try tmpfile("temp0", """
      
      a
      a:b
      c:d:e
      e:f:g:h
      
      """)
      let prog = """
        BEGIN {
          FS = ":"
          while (getline <"\(temp0)" > 0) 
            print NF
        }
        
        """
      defer { rm(temp0) }
      try await run(output: "0\n1\n2\n3\n4\n",
                    args:prog, temp0)
     }

    @Test("fourth") func fourth() async throws {
      let prog = """
        {
          FS = ":"
          getline a < "/etc/passwd"
          print $1
        }
        
        """
      
      try await run(withStdin: "f b a\n",
                    output: "f\n",
                    args: prog)
    }

    @Test("fifth") func fifth() async throws {
      let prog = """
        {
          FS=":"
          getline v
          print $2, NF
          FS=" "
        }
        
        """
      let temp0 = try tmpfile("temp0", """
        a b c d
        foo
        e f g h i
        bar
        
        """)
      defer { rm(temp0) }
      try await run(output: "b 4\nf 5\n",
                    args: prog, temp0)      
     }

    @Test("sixth") func sixth() async throws {
      let prog = """
        BEGIN { FS="=" } { FS="."; $0=$1; print $2; FS="="; }
        
        """
      let temp0 = try tmpfile("temp0", """
        a.b.c=d.e.f
        g.h.i=j.k.l
        m.n.o=p.q.r
        
        """)
      defer { rm(temp0) }
      
      try await run(output: "b\nh\nn\n",
                    args: prog, temp0)
     
    }

    @Test("seventh") func seventh() async throws {
      let prog = """
        BEGIN { FS="=" } { print $2; FS="."; $0=$1; print $2; FS="="; }
        
        """
      let temp0 = try tmpfile("temp0", """
        a.b.c=d.e.f
        g.h.i=j.k.l
        m.n.o=p.q.r
        
        """)
      defer { rm(temp0) }
      try await run(output: """
        d.e.f
        b
        j.k.l
        h
        p.q.r
        n
        
        """, args: prog, temp0)
    }

    @Test("eighth", arguments: [
            """
              {  n = split($0, x, "")
                m = length($0)
                if (m != n) print "error 1", NR
                s = ""
                for (i = 1; i <= m; i++)
                  s = s x[i]
                if (s != $0) print "error 2", NR
                print s
              }
              
              """,
                  """
                    {  n = split($0, x, //)
                      m = length($0)
                      if (m != n) print "error 1", NR
                      s = ""
                      for (i = 1; i <= m; i++)
                        s = s x[i]
                      if (s != $0) print "error 2", NR
                      print s
                    }
                    
                    """,
                  """
                     BEGIN { FS = "" }
                     {  n = split($0, x)  # will be split with FS
                       m = length($0)
                       if (m != n) print "error 1", NR
                       s = ""
                       for (i = 1; i <= m; i++)
                         s = s x[i]
                       if (s != $0) print "error 2", NR
                       print s
                     }
                    
                    """,
                  """
                    BEGIN { FS = "" }
                    {  n = NF
                      m = length($0)
                      if (m != n) print "error 1", NR
                      s = ""
                      for (i = 1; i <= m; i++)
                        s = s $i
                      if (s != $0) print "error 2", NR
                      print s
                    }
                    
                    """
    ]
    ) func eighth(_ prog : String) async throws {
/*      let prog = """
        {  n = split($0, x, "")
          m = length($0)
          if (m != n) print "error 1", NR
          s = ""
          for (i = 1; i <= m; i++)
            s = s x[i]
          if (s != $0) print "error 2", NR
          print s
        }
        
        """
*/
      let temp0 = try tmpfile("temp0","")
      defer { rm(temp0) }
      let setup = """
      BEGIN {
      print "abc" >"\(temp0)"
      print "de" >>"\(temp0)"
      print "f" >>"\(temp0)"
      print "" >>"\(temp0)"
      print "     " >>"\(temp0)"
      system("who | head -n 10 | cat >>\(temp0)")
      system("head -n 20 | tail -20 >>\(temp0)")
      }
      """
      // sets up temp0
      try await run(args: setup)
      
      let inpoutp = try temp0.readAsString()
      
      try await run(output: inpoutp,
                    args: prog, temp0)

      
    }
/*
    @Test("ninth") func ninth() async throws {
      let prog = """
        {  n = split($0, x, //)
          m = length($0)
          if (m != n) print "error 1", NR
          s = ""
          for (i = 1; i <= m; i++)
            s = s x[i]
          if (s != $0) print "error 2", NR
          print s
        }
        
        """
      // same temp0 as eighth
    }

    @Test("tenth") func tenth() async throws {
      let prog = """
         BEGIN { FS = "" }
         {  n = split($0, x)  # will be split with FS
           m = length($0)
           if (m != n) print "error 1", NR
           s = ""
           for (i = 1; i <= m; i++)
             s = s x[i]
           if (s != $0) print "error 2", NR
           print s
         }
        
        """
      // still same temp0
    }

    @Test("eleventh") func eleventh() async throws {
      let prog = """
        BEGIN { FS = "" }
        {  n = NF
          m = length($0)
          if (m != n) print "error 1", NR
          s = ""
          for (i = 1; i <= m; i++)
            s = s $i
          if (s != $0) print "error 2", NR
          print s
        }
        
        """
      // still same temp0
    }
 */

    @Test("twelfth") func twelfth() async throws {
      let prog = """
        { n = split( $0, temp, /^@@@ +/ )
          print n
        }
        
        """
      let input = """
      @@@ xxx
      @@@ xxx
      @@@ xxx
      
      """
      try await run(withStdin: input, output: "2\n2\n2\n",
                    args: prog)
    }

    @Test("thirteenth") func thirteenth() async throws {
      let prog = """
        { print split($0, x, "")
        }
        
        """
      let temp0 = try tmpfile("temp0", """
        
        a
        bc
        def
        
        """)
      defer { rm(temp0) }
      try await run(output: "0\n1\n2\n3\n", args: prog, temp0)
    }

    @Test("fourteenth") func fourteenth() async throws {
      let prog = """
        BEGIN {
          a[1]="a b"
          print split(a[1],a),a[1],a[2]
        }
        
        """
      try await run(output: "2 a b\n",
                    args: prog)
    }

    @Test("fifteenth") func fifteenth() async throws {
      let prog = """
        BEGIN {
          a = "cat\\n\\n\\ndog"
          split(a, b, "[\\\\r\\\\n]+")
          print b[1], b[2]
        }
        
        """
      try await run(output: "cat dog\n",
                    args: prog)
    }
  }
}
