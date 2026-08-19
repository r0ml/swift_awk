
import ShellTesting

extension awkTest {
  
  @Suite("T.misc") struct Tmisc : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"
    
    
    @Test("first") func first() async throws {
      let foo = try tmpfile("foo", """
        The big brown over the lazy doe
        The big brown over the lazy dog
        x
        The big brown over the lazy dog
        
        """)
      defer { rm(foo) }
      let foo1 = """
        failed
        succeeded
        failed
        succeeded
        
        """
      let prog = """
        { if (match($0, /^The big brown over the lazy dog/) == 0) {
            printf("failed\\n")
          } else {
            printf("succeeded\\n")
          }
        } 
        
        """
      try await run(output: foo1, args: prog, foo)
    }
    
    @Test("second") func second() async throws {
      let foo = try tmpfile("foo", """
        123
        1234567890
        12345678901
        
        """)
      defer { rm(foo) }
      let foo1 = "12345678901\n"
      
      let prog = "length($0) > 10"
      try await run(output: foo1, args: prog, foo)
      
    }
    
    @Test("third") func third() async throws {
      let foo1 = "HIJKL\n"
      let prog = "{ print \"H\\x49\\x4a\\x4BL\" }"
      try await run(withStdin: "foo\n", output: foo1, args: prog)
    }
    
    @Test("fourth") func fourth() async throws {
      let foo = try tmpfile("foo", """
        123
        1234567890
        12345678901
        
        """)
      defer { rm(foo) }
      let foo1 = "012x45\n"
      
      let prog = "BEGIN { print \"0\\061\\62x\\0645\" }"
      try await run(output: foo1, args: prog, foo)
    }
    
    @Test("fifth") func fifth() async throws {
      try await run(withStdin: "3 5\n", 
                    output: "3\n4 1\n",
                    args: "{ i = 1; print $i++; print $1, i }")
    }
    
    // makes sure that fields are recomputed even if self-assignment
    // take into account that subtracting from NF now rebuilds the record
    @Test("sixth") func sixth() async throws {
      try await run(withStdin: """
        a b c
        s p q r
        x y z
        
        """, output: """
          a
          s p
          x
          
          """, args: "{ NF -= 2; $1 = $1; print }" )
    }
    
    @Test("seventh") func seventh() async throws {
      try await run(output: "1\n1\n",
                    args: "BEGIN {x = 1; print x; x = x; print x }")
    }
    
    @Test("eighth") func eighth() async throws {
      try await run(
        withStdin: "573109312\n",
        output: "2292437248\n",
        args: "{print $1*4}")
    }
    
    // note that there are 8-bit characters in the echo
    // some shells will probably screw this up.
    @Test("ninth") func ninth() async throws {
      try await run(withStdin: """
        #
        code  1
        code  2
        
        """, output: "#\n",
                    args: "/^#/" )
    }
    
    @Test("tenth") func tenth() async throws {
      try await run(withStdin: "hello\n",
                    status: 0,
                    args: "BEGIN { FILENAME = \"/etc/passwd\" }\n  { print $0 }")
    }
    
    @Test("eleventh", .disabled("goes into an infinite loop")) func eleventh() async throws {
      let prog = """
          function foo(foo) {
                        foo = 1
                        foo()
                }
          { foo(bar) }
        
        """
      try await run(withStdin: "hello\n",
                    status: 2,
                    error: /both function name and argument name/,
                    args: prog)
    }
    
    @Test("twelfth") func twelfth() async throws {
      let prog = """
        { x[NR] = $0 }  # test whether $0 is NUM as well as STR
        END { if (x[1] > x[2]) {
            print "\u{7}BAD: T.misc: $0 is not NUM";
          exit 2 }
        }
        
        """
      try await run(withStdin: "2\n10\n",
                    status: 0, error: "",
                    args: prog)
    }
    
    // This should give an error about function arguments
    @Test("fourteenth") func fourteenth() async throws {
      let prog = """
        function foo(x) { print "x is" x }
        BEGIN { foo(foo) }
        
        """
      try await run(status: 2, error: /can.t (read value|use function)/,
                    args: prog)
    }
    
    // gawk defref test; should give error about undefined function
    @Test("fifteenth") func fifteenth() async throws {
      try await run(status: 2,
                    error: /calling undefined function/,
                    args: "BEGIN { foo() }")
    }
    
    // gawk arrayparm test; should give error about function 
    @Test("sixteenth") func sixteenth() async throws {
      let prog = """
        BEGIN {
            foo[1]=1;
            foo[2]=2;
            bug1(foo);
        }
        function bug1(i) {
            for (i in foo) {
          bug2(i);
          delete foo[i];
          print i,1,bot[1];
            }
        }
        function bug2(arg) {
            bot[arg]=arg;
        }
        
        """
      try await run(status: 2,
                    error: /can.t assign to/,
                    args: prog)
    }
    
    // This should be a syntax error
    @Test("seventeenth") func seventeenth() async throws {
      try await run(status: 2,
                    error: /syntax error|must be assignable/,
                    args: "!x = y")
    }
    
    // This should print bbb
    @Test("eighteenth") func eighteenth() async throws {
      let prog = """
        BEGIN { up[1] = "a"
          for (i in up) gsub("a", "A", x)
          print x x "bbb"
          exit
              }
        
        """
      try await run(output: /bbb/,
                    args: prog)
    }
    
    @Test("nineteenth") func nineteenth() async throws {
      let prog = """
        BEGIN {
          printf "push return\u{7}" >"/dev/null"
          getline ans <"/dev/null"
        } 
        
        """
      try await run(withStdin: "yes\n",
                    status: 0, error: "",
                    args: prog)
    }
    
    @Test("twentieth") func twentieth() async throws {
      let prog = """
        BEGIN { unireghf() }
        function unireghf(hfeed) { hfeed[1] = 0 }
        
        """
      try await run(status: 0, error: "", args: prog)
    }
    
    @Test("twentyfirst") func twentyfirst() async throws {
      try await run(withStdin: "x\n", 
                    status: 2,
                    error: /extra ']'/,
                    args: "/{/]/")
    }
    
    @Test("twentysecond") func twentysecond() async throws {
      let prog = """
      function f() { return 12345 }
      BEGIN { printf "<%s>\\n", f() }

      """
      try await run(output: "<12345>\n", args: prog)
    }
    
    @Test("twentythird") func twentythird() async throws {
      let foo = try tmpfile("foo", """
      abc
      def
      
      ghi
      jkl
      
      """)
      defer { rm(foo) }
      let prog = """
      BEGIN {  RS = ""
        while (getline <"\(foo)")
          print
      }
      
      """
      try await run(args: prog) { r in 
        try await run(withStdin: r.data,
                      output: "4\n",
                      args: "END { print NR }")
      }
    }
    
    @Test("twentyfourth") func twentyfourth() async throws {
      try await run(withStdin: "aaa1a2a\n",
                    output: """
      
      aa1a2a
      
      
      
      """, args: "1", "RS=^a")
    }
    
    
    // The following should not produce a warning about changing a constant
    // nor about a curdled tempcell list
    @Test("twentyfifth") func twentyfifth() async throws {
      try await run(status: 0, error: "",
                    args: """
function f(x) { x = 2 }
BEGIN { f(1) }
""")
    }
    
    // The following should not produce a warning about a curdled tempcell list
    @Test("twentysixth") func twentysixth() async throws {
      try await run(status: 0, error: "",
                    args: """
function f(x) { x }
BEGIN { f(1) }
""")
      
    }
    
    @Test("twentyseventh") func twentyseventh() async throws {
      try await run(output: "9 10 11\n10\n",
                    args: "BEGIN { print 9, a=10, 11; print a; exit }")
    }
    
    @Test("twentyeighth") func twentyeighth() async throws {
      try await run(withStdin: "abc defgh ijkl\n",
                    output: """
                     defgh ijkl
                     defgh ijkl
                     defgh ijkl
                    
                    """,
                    args: """
                    { $1 = ""; line = $0; print line; print $0; $0 = line; print $0 }
                    
                    """)
    }
    
    @Test("twentyninth") func twentyninth() async throws {
      try await run(status: 0, error: "",
                    args: """
function min(a, b)
{
  if (a < b)
    return a
  else
    return b
}
BEGIN { exit }

""")
    }
    
    // The following should not give a syntax error message:
    @Test("thirtieth") func thirtieth() async throws {
      try await run(status: 0, error: "",
                    args: """
                    function expand(chart) {
                      getline chart < "CHAR.ticks"
                    }
                    
                    """)
    }
    
    @Test("thirtyfirst") func thirtyfirst() async throws {
      try await run(status: 0, error: "",
                    args: "BEGIN { print 1e40 }")
    }
    
    /// The following syntax error should not dump core:
    @Test("thirtysecond") func thirtysecond() async throws {
      try await run(status: 2, error: /[Ee]xpected/,
                    args: """
                    $NF==3  {first=1}
                    $NF==2 && first==0 && (abs($1-o1)>120||abs($2-o2)>120)  {print $0}
                    $NF==2  {o1=%1; o2=$2; first=0}
                    
                    """)
    }
    
    // The following syntax error should not dump core:
    @Test("thirtythird") func thirtythird() async throws {
      try await run(status: 2, error: /[Ee]xpected|illegal statement/,
                    args: """
                    { n = split($1, address, !); print address[1] }
                    """)
    }
    
    // The following syntax error should not dump core:
    @Test("thirtyfourth") func thirtyfourth() async throws {
      try await run(status: 2, error: /illegal statement/,
                    args: "BEGIN {\"hello\"}")
    }
    
    // The following should give a syntax error message:
      @Test("thirtyfifth") func thirtyfifth() async throws {
      try await run(status: 2, error: /context is/,
                    args: """
                      function pile(c,     r) {
                        r = ++pile[c]
                      }

                      { pile($1) }
                      
                      """)
    }
    
    // This should complain about missing atan2 argument:
    @Test("thirtysixth") func thirtysixth() async throws {
      try await run(status: 2, error: /requires two arg/,
                    args: "BEGIN { atan2(1) }")
    }
    
    // This should not dump core
    @Test("thirtyseventh") func thirtyseventh() async throws {
      try await run(status: 0, error: "",
                    args: """
                      BEGIN { f() }
                      function f(A) { delete A[1] }
                      
                      """)
    }
    
    // nasty one:  should not be able to overwrite constants
    @Test("thirtyeighth") func thirtyeighth() async throws {
      try await run(status: 2, error: /syntax error/,
                    args: """
                      BEGIN { gsub(/ana/,"anda","banana")
                          printf "the monkey ate a %s\\n", "banana" }
                      
                      """)
    }
  
    // line numbers used to double-count comments
    @Test("thirtyninth") func thirtyninth() async throws {
      try await run(status: 2, error: /line [45]/,
                    args: """
                      #
                      #
                      #
                      /x
                      
                      """)
    }
    
    @Test("fortieth") func fortieth() async throws {
      // \f \r \b \v \a in order: form feed, carriage return, backspace, vertical tab, bell.
      try await run(output: "x\u{c}\u{d}\u{8}\u{b}\u{7}\\y\n",
                    args: "BEGIN { print \"x\\f\\r\\b\\v\\a\\\\y\" }")
    }
    
    @Test("fortyfirst") func fortyfirst() async throws {
      try await run(output: "0\n",
                    args: """
  BEGIN { exit }
  { print }
  END { print NR }

""")
    }
      
      @Test("fortysecond") func fortysecond() async throws {
        try await run(output: "1\n",
      args: """
        { exit }
        END { print NR }
        
        """, "/etc/passwd")
      }
    
    
    @Test("fortythird") func fortythird() async throws {
      try await run(output: "1\n",
    args: """
       {i = 1; while (i <= NF) {if (i == NF) exit; i++ } }
        END { print NR }
      
      """, "/etc/passwd")
    }

    @Test("fortyfourth") func fortyfourth() async throws {
      try await run(output: "1\n",
    args: """
  function f() {
    i = 1; while (i <= NF) {if (i == NF) return NR; i++ }
  }
  { if (f() == 1) exit }
  END { print NR }
  """, "/etc/passwd")
    }

    @Test("fortyfifth") func fortyfifth() async throws {
      try await run(output: "1\n",
    args: """
  function f() {
    split("a b c", arr)
    for (i in arr) {if (i == 3) return NR; i++ }
  }
  { if (f() == 1) exit }
  END { print NR }
  """, "/etc/passwd")
    }


    @Test("fortysixth") func fortysixth() async throws {
      try await run(output: "1\n",
    args: """
  {i = 1; do { if (i == NF) exit; i++ } while (i <= NF) }
  END { print NR }
  """, "/etc/passwd")
    }

    @Test("fortyseventh") func fortyseventh() async throws {
      try await run(output: "1\n",
    args: """
  function f() {
    i = 1; do { if (i == NF) return NR; i++ } while (i <= NF)
  }
  { if (f() == 1) exit }
  END { print NR }
  """, "/etc/passwd")
    }

    @Test("fortyeighth") func fortyeighth() async throws {
      try await run(output: "1\n",
    args: """
  {i = 1; do { if (i == NF) break; i++ } while (i <= NF); exit }
  END { print NR }
  """, "/etc/passwd")
    }

  
    @Test("fortyninth") func fortyninth() async throws {
      try await run(output: "1\n",
    args: """
  { n = split($0, x)
    for (i in x) {
     if (i == 1)
      exit } }
  END { print NR }
  """, "/etc/passwd")
    }

    @Test("fiftieth") func fiftieth() async throws {
      try await run(output: "XXXXXXXX\n",
                    args: """
                      BEGIN { s = "ab\\fc\\rd\\be"
                        t = s;   gsub("[" s "]", "X", t); print t }
                      
                      """)
    }
    
    @Test("fiftyfirst") func fiftyfirst() async throws {
      try await run(status: 2, error: /can.t open/,
                    args: "{}", "etc/passwd", "glop/glop")
    }
  
    @Test("fiftysecond") func fiftysecond() async throws {
      let foo = try tmpfile("foo", """
        
        
        
        a
        aa

        b


        c

        
        
        """)
      defer { rm(foo) }
      try await run(output: "3\n",
                    args: "BEGIN { RS = \"\" }; END { print NR }", foo)
    }
      
    @Test("fiftysecond2") func fiftysecond2() async throws {
      try await run(status: 2, error: /line 4/,
                    args: """
                      BEGIN \\
                        {
                          print "hello, world"
                        }
                      }}}
                      
                      """)
    }
    
    @Test("fiftythird") func fiftythird() async throws {
      let foo = try tmpfile("foo", "111 222 333\n")
      defer { rm(foo) }
      try await run(output: "111 111 222 2 2\n",
                    args: """
                      { f[1]=1; f[2]=2; print $f[1], $f[1]++, $f[2], f[1], f[2] }
                      
                      """, foo)
    }
    
    // These should be syntax errors
    @Test("fiftyfourth", arguments:
            [".", "..", ".E.", ".++."]) func fiftyfourth(_ s : String) async throws {
      try await run(status: 2, error: /unexpected character/,
                    args: s)
      
    }
    
    // These should be synta errors
    @Test("fiftyfifth", arguments:
            ["$", "{print $", "\""] ) func fiftyfifth(_ s : String) async throws {
      try await run(status: 2, error: /[Ee]xpected|unterminated|non-terminated/,
                    args: s)
    }
    
    // %c of 0 is explicit null byte
    @Test("fiftysixth") func fiftysixth() async throws {
      try await run(args: "BEGIN {printf(\"%c%c\\n\", 0, 0) }") { r in
        #expect(r.data.count == 3)
      }
    }
    
    // non-terminated RE
    @Test("fiftyseventh") func fiftyseventh() async throws {
      try await run(status: 2, error: /unterminated regex|non-terminated/,
                    args: "/xyz")
    }
    
    // next several were infinite loops, found by brian tsang.
    // this is his example:
    @Test("fiftyeighth", arguments:
    ["""
                      BEGIN {
                          switch (substr("x",1,1)) {
                          case /ask.com/:
                        break
                          case "google":
                        break
                          }
                      }
                      
                      """,
    "BEGIN { s { c /./ } }",
     "BEGIN { s { c /../ } }"]) func fiftyeighth(_ s : String) async throws {
      try await run(status: 2, error: /unexpected character|illegal statement/,
                    args: s)
    }

    @Test("fiftyninth") func fiftyninth() async throws {
      try await run(status: 2, error: /not permitted/,
                    args: #"BEGIN {printf "%2$s %1$s\n", "a", "b"}"#)
    }
    
    @Test("sixtieth", arguments:[
           """
             a
             b c
             de fg hi
             
             """, """
        fg hi
        
        """, "\n"
    ]) func sixtieth(_ s : String) async throws {
      let foo0 = try tmpfile("foo0", s)
      defer { rm(foo0) }
      try await run(args: "END { print NF, $0}", foo0) { foo1 in
        try await run(args: "{ print NF, $0 }", foo0) { res in
          let r2 = try res.string(encoded: .utf8).split(separator: "\n").last?.appending("\n")
          let r1 = try foo1.string(encoded: .utf8)
          #expect(r2 == r1)
        }
      }
    }
 
  }
}
