
import ShellTesting

extension awkTest {

  @Suite("T.gawk") struct Tgawk : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = """
          BEGIN { # foo[10] = 0    # put this line in and it will work
            test(foo); print foo[1]
            test2(foo2); print foo2[1]
          }
          function test(foo) { test2(foo) }
          function test2(bar) { bar[1] = 1 }
        
        """
      try await run(output: "1\n1\n", args: prog)
    }
    
    // asgext
    @Test("second") func second() async throws {
      let foo = try tmpfile("foo", """
        1 2 3
        1
        1 2 3 4
                
        """)
      defer { rm(foo) }
      let outp = """
        3
        1 2 3 a

        1   a
        3
        1 2 3 a

           a

        """
      try await run(output: outp, args: #"{ print $3; $4 = "a"; print }"#, foo)
    }
    
    // backgsub
    @Test("third") func third() async throws {
      let prog = """
        {  x = y = $0
                gsub( /\\\\\\\\/, "A", x); print x
                gsub( "\\\\\\\\", "A", y); print y
        }
        
        """
      let outp = """
        x\\y
        xAy
        xAy
        xAAy
        
        """
      
      let foo = try tmpfile("foo", """
        x\\y
        x\\\\y
        
        """)
      defer { rm(foo) }
      try await run(output: outp, args: prog, foo)
    }
    
    // backgsub2
    @Test("fourth") func fourth() async throws {
      let prog = """
        {  w = x = y = z = $0
                gsub( /\\\\\\\\/, "\\\\", w); print "  " w
                gsub( /\\\\\\\\/, "\\\\\\\\", x); print "  " x
                gsub( /\\\\\\\\/, "\\\\\\\\\\\\", y); print "  " y
        }
        
        """
      let outp = """
  x\\y
  x\\y
  x\\y
  x\\y
  x\\\\y
  x\\\\\\y
  x\\\\y
  x\\\\\\y
  x\\\\\\\\y

"""
      let foo = try tmpfile("foo", """
        x\\y
        x\\\\y
        x\\\\\\y
        
        """)
      try await run(output: outp, args: prog, foo)
    }
    
    // backgsub3
    @Test("fifth") func fifth() async throws {
      let prog = """
        {  w = x = y = z = z1 = z2 = $0
                gsub( /a/, "\\&", w); print "  " w
                gsub( /a/, "\\\\&", x); print "  " x
                gsub( /a/, "\\\\\\&", y); print "  " y
                gsub( /a/, "\\\\\\\\&", z); print "  " z
                gsub( /a/, "\\\\\\\\\\&", z1); print "  " z1
                gsub( /a/, "\\\\\\\\\\\\&", z2); print "  " z2
        }
        
        """
      let outp = """
  xax
  x&x
  x&x
  x\\ax
  x\\ax
  x\\&x
  xaax
  x&&x
  x&&x
  x\\a\\ax
  x\\a\\ax
  x\\&\\&x

"""
      let foo = try tmpfile("foo", """
        xax
        xaax
        
        """)
      defer { rm(foo) }
      try await run(output: outp, args: prog, foo)
    }
    // 94
    
    // backsub3:
    @Test("sixth") func sixth() async throws {
      let prog = """
        {  w = x = y = z = z1 = z2 = $0
                sub( /a/, "\\&", w); print "  " w
                sub( /a/, "\\\\&", x); print "  " x
                sub( /a/, "\\\\\\&", y); print "  " y
                sub( /a/, "\\\\\\\\&", z); print "  " z
                sub( /a/, "\\\\\\\\\\&", z1); print "  " z1
                sub( /a/, "\\\\\\\\\\\\&", z2); print "  " z2
        }
        
        """
      let outp = """
  xax
  x&x
  x&x
  x\\ax
  x\\ax
  x\\&x
  xaax
  x&ax
  x&ax
  x\\aax
  x\\aax
  x\\&ax

"""
      let foo = try tmpfile("foo", """
xax
xaax

""")
      defer { rm(foo) }
      try await run(output: outp, args: prog, foo)
    }
    
    // backsub:
    @Test("seventh") func seventh() async throws {
      let prog = """
        {  x = y = $0
                sub( /\\\\\\\\/, "\\\\\\\\", x); print x
                sub( "\\\\\\\\", "\\\\\\\\", y); print y
        }
        
        """
      let outp = """
        x\\y
        x\\\\y
        x\\\\y
        x\\\\\\y
        
        """
      let foo = try tmpfile("foo", """
        x\\y
        x\\\\y
        
        """)
      defer { rm(foo) }
      try await run(output: outp, args: prog, foo)
    }
    
    // 137
    
    // dyn1j
    @Test("eighth") func eighth() async throws {
      try await run(output: "hello               world\n",
                    args: #"BEGIN { printf "%*sworld\n", -20, "hello" }"#)
    }
    
    // fsrs
    @Test("ninth") func ninth() async throws {
      let foo = try tmpfile("foo", """
        a b
        c d
        e f
        
        1 2
        3 4
        5 6
        
        """)
      defer { rm(foo) }
      let prog = """
        BEGIN {
               RS=""; FS="\\n";
               ORS=""; OFS="\\n";
              }
        {
                split ($2,f," ")
                print $0;
        }
        
        """
      let outp = """
        a b
        c d
        e f1 2
        3 4
        5 6
        """
      try await run(output: outp, args: prog, foo) 
    }
    
    // intest
    @Test("tenth") func tenth() async throws {
      let prog = """
        BEGIN {
          bool = ((b = 1) in c);
          print bool, b  # gawk-3.0.1 prints "0 "; should print "0 1"
        }
        
        """
      try await run(output: "0 1\n", args: prog)
    }
    
    // intprec
    @Test("eleventh") func eleventh() async throws {
      try await run(output: "0000000005:000000000e\n",
                    args: #"BEGIN { printf "%.10d:%.10x\n", 5, 14 }"#)
    }
    
    // litoct
    @Test("twelfth") func twelfth() async throws {
      let prog = """
        { if (/a\\52b/) print "match" ; else print "no match" }
        """
      let foo = try tmpfile("foo", """
        axb
        ab
        a*b
        
        """)
      defer { rm(foo) }
      try await run(output: "no match\nno match\nmatch\n",
                    args: prog, foo)
    }
    
    // math:
    @Test("thirteenth") func thirteenth() async throws {
      let outp = """
        cos(0.785398) = 0.707107
        sin(0.785398) = 0.707107
        e = 2.718282
        log(e) = 1.000000
        sqrt(pi ^ 2) = 3.141593
        atan2(1, 1) = 0.785398
        
        """
      let prog = """
        BEGIN {
          pi = 3.1415927
          printf "cos(%f) = %f\\n", pi/4, cos(pi/4)
          printf "sin(%f) = %f\\n", pi/4, sin(pi/4)
          e = exp(1)
          printf "e = %f\\n", e
          printf "log(e) = %f\\n", log(e)
          printf "sqrt(pi ^ 2) = %f\\n", sqrt(pi ^ 2)
          printf "atan2(1, 1) = %f\\n", atan2(1, 1)
        }
        
        """
      try await run(output: outp, args: prog)
    }
    
    // nlfldsep
    @Test("fourteenth") func fourteenth() async throws {
      let foo = try tmpfile("foo", """
        some stuff
        more stuffA
        junk
        stuffA
        final
        
        """)
      defer { rm(foo) }
      let prog = """
        BEGIN { RS = "A" }
        {print NF; for (i = 1; i <= NF; i++) print $i ; print ""}

        """
      let outp = """
        4
        some
        stuff
        more
        stuff

        2
        junk
        stuff

        1
        final

        
        """
      try await run(output: outp, args: prog, foo)
    }
    
    // numsubstr
    @Test("fifteenth") func fifteenth() async throws {
      let foo = try tmpfile("foo", """
        5000
        10000
        5000
        
        """)
      defer { rm(foo) }
      let prog = #"{ print substr(1000+$1, 2) }"#
      let outp = """
        000
        1000
        000
        
        """
      try await run(output: outp, args: prog, foo)
    }
    
    // pcntplus
    @Test("sixteenth") func sixteenth() async throws {
      try await run(output: "+3 4\n", 
                    args: #"BEGIN { printf "%+d %d\n", 3, 4 }"#)
    }
    
    // prtleval
    @Test("seventeenth") func seventeenth() async throws {
      let prog = """
        function tst () {
          sum += 1
          return sum
        }
        BEGIN { OFMT = "%.0f" ; print tst() }

        """
      try await run(output: "1\n", args: prog)
    }
    
    // reparse
    @Test("eighteenth") func eighteenth() async throws {
      let foo = try tmpfile("foo", "1 axbxc 2\n")
      defer { rm(foo) }
      let outp = """
        1
        1 a b c 2
        1 a b
        
        """
      let prog = """
        {  gsub(/x/, " ")
          $0 = $0
          print $1
          print $0
          print $1, $2, $3
        }
        """
      try await run(output: outp, args: prog, foo)
    }
    
    // rswhite
    @Test("nineteenth") func nineteenth() async throws {
      let foo = try tmpfile("foo", "    a b\nc d\n")
      defer { rm(foo) }
      let outp = "<    a b\nc d>\n"
      let prog = """
        BEGIN { RS = "" }
        { printf("<%s>\\n", $0) }
        """
      try await run(output: outp, args: prog, foo)
    }
    
    // splitvar
    @Test("twentieth") func twentieth() async throws {
      let foo = try tmpfile("foo", "Here===Is=Some=====Data\n")
      defer { rm(foo) }
let prog = """
  {  sep = "=+"
    n = split($0, a, sep)
    print n
  }
  """
      try await run(output: "4\n", args: prog, foo)
    }
    
    // splitwht
    @Test("twentyfirst") func twentyfirst() async throws {
        let prog = """
          BEGIN {
            str = "a   b\t\tc d"
            n = split(str, a, " ")
            print n
            m = split(str, b, / /)
            print m
          }      
          """
      try await run(output: "4\n5\n", args: prog)
    }
    
    // sprintfc
    @Test("twentysecond") func twentysecond() async throws {
      let foo = try tmpfile("foo", "65\n66\n")
      try await run(output: "A 65\nB 66\n",
                    args: #"{ print sprintf("%c", $1), $1 }"#, foo)
    }
    
    // substr
    @Test("twentythird") func twentythird() async throws {
      let outp = """
        xxA                                      
        xxab
        xxbc
        xxab
        xx
        xx
        xxab
        xx
        xxef
        xx
        
        """
     
      let prog = """
        BEGIN {
          x = "A"
          printf("xx%-39s\\n", substr(x,1,39))
          print "xx" substr("abcdef", 0, 2)
          print "xx" substr("abcdef", 2.3, 2)
          print "xx" substr("abcdef", -1, 2)
          print "xx" substr("abcdef", 1, 0)
          print "xx" substr("abcdef", 1, -3)
          print "xx" substr("abcdef", 1, 2.3)
          print "xx" substr("", 1, 2)
          print "xx" substr("abcdef", 5, 5)
          print "xx" substr("abcdef", 7, 2)
          exit (0)
        }
        """
      try await run(output: outp, args: prog)
    }
    
    // fldchg
    @Test("twentyfourth") func twentyfourth() async throws {
      let foo = try tmpfile("foo", "aa aab c d e f\n")
      defer { rm(foo) }
      let outp = """
        1: + +b c d e f
        2: + +b <c> d e f
        2a:%+%+b%<c>%d%e
        
        """
      let prog = """
        {  gsub("aa", "+")
          print "1:", $0
          $3 = "<" $3 ">"
          print "2:", $0
          print "2a:" "%" $1 "%" $2 "%" $3 "%" $4 "%" $5
        }
        
        """
      try await run(output: outp, args: prog, foo)
    }
    
    // fldchgnf
    @Test("twentyfifth") func twentyfifth() async throws {
      let foo = try tmpfile("foo", "a b c d\n")
      defer { rm(foo) }
      let outp = "a::c:d\n4\n"
      let prog = #"{ OFS = ":"; $2 = ""; print $0; print NF }"#
      try await run(output: outp, args: prog, foo)
    }
    
    // OFMT from arnold robbins 6/02
    @Test("twentysixth") func twentysixth() async throws {
      try await run(output: "6\n",
                    args: """
                      BEGIN {
                        OFMT = "%.0f"
                        print 5.7
                      }
                      """)
    }
   }
}
