
import ShellTesting

extension awkTest {

  @Suite("T.errmsg") struct Terrmsg : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"
    
    
    @Test("first", 
          arguments: [
            ("/(/", "illegal primary"),
            ("BEGIN { nextfile }", "illegal .*next.* from BEGIN"),
            ("END { nextfile }", "illegal .*next.* from END"),
            ("function foo() { nextfile }","nextfile.*illegal"),
            ("function f(i,j,i) { return i }", "[Dd]uplicate (parameter|argument)"),
            ("/[[/", "[Ee]xpected"),
            ("/[]", "unterminated regex"),
            ("/[\\", "unexpected.*regex"),
            ("BEGIN { s = \"[x\"; if (1 ~ s) print \"foo\" }", "{Ee]xpected"),
            ("/[[:abcdef:]]/", "unknown character class"),
            ("BEGIN { if (\"x\" ~ /$^/) print \"ugh\" }", "syntax error"),
            ("/((.)/", "syntax error"),
            ("BEGIN { print 1/0}", "division by zero"),
            ("BEGIN { x = 1; print x /= 0 }", "division by zero"),
            // 57
            ("BEGIN { x = 1; print x %= 0 }", "division by zero"),
            ("BEGIN { print 1%0 }", "division by zero"),
            
            (#"BEGIN { x[1] = 0; split("a b c", y, x) }"#, "can.t read value.* array"),
            (#"function f(){}; {split($0, x, f)}"#, "can.t read value.* function"),
            // 69
            (#"function f(){}; {f = split($0, x)}"#, "can.t assign.*function"),
            (#"{x = split($0, x)}"#, "not an array"),
            ("""
              BEGIN { f(f) }
              function f() { print "x" }
              
              """, "called with"),
            ("""
              BEGIN { f(f) }
              function f() { print "x" }
              
              """, "can't use.*as argument"),
            ("{ split($0, x) }; function x() {}", "not a function"), 
            (#"function x() { function g() {} }"#, "nested function" ),
            (" { return } ", "not in function"),
            (" { break } ", "outside"),
            (" { continue } ", "outside"),
            (" { print \"abc\n }", "unterminated"),
            (" BEGIN { print $\"foo\" }", "illegal field"),
            (" BEGIN { f() }\nfunction f() { next }", "illegal.*from BEGIN"),
            ("BEGIN { printf(\"%s\") }", "not enough args"),
            ("BEGIN { printf(\"%z\", \"foo\") }", "weird.*conversion"),
            ("""
              function f(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,
                c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,
                e1,e2,e3,e4,e5,e6,e7,e8,e9,e10,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10) {}
              BEGIN { f(123) }              
              """, "too many args"),
            ("])}", "extra"),
            ("{ print }}", "extra"),
            ("{ print }}}", "extra"),
            ("]", "extra"),
            ("[", "[Uu]nexpected"),
            ("a & b", "not valid"),
            ("{ x = 1) }", "extra"),
            ("{ print ))}", "extra"),
            ("{{ print }", "[Ee]xpected"),
            ("{{{ print }", "[Ee]xpected"),
            ("BEGIN { next }", "illegal .*next.* from BEGIN"),
            // 157
            ("END {  next; print NR }", "illegal .*next.* from END"),
            (#"BEGIN { print "abc" >"/etc/passwd" }"#, "can.t open file"),
            ("""
              function f() { print 1 }
              function f() { print 2 }

              """, "define function"),
            (#"BEGIN { index("abc", /a/) }"#, "index.*doesn.t permit regular"),
            (#"BEGIN { print >foo }"#, "null file name in print or getline"),
            ("BEGIN { foo() }", "undefined function"),
            // 194
            
            
            
            
            
              ]) func first(_ s : String, _ b : String) async throws {
                try await run(status: 2,
                              error: Regex(b),
                              args: s)
    }
    
    @Test("second") func second() async throws {
      let foo0 = try tmpfile("foo0", "xxx\n")
      try await run(status: 2,
                    error: /newline in string/,
                    args: "{print x}", "x='a\nb'", foo0)
      
    }
    
    // log(-1) and exp(1000) are not fatal in real awk — they just print "nan"/"inf"
    // like ordinary floating-point results, so these don't belong in the "first"
    // suite (which asserts a fatal error on every case).
    @Test("logDomain") func logDomain() async throws {
      try await run(output: "nan\n", args: "BEGIN { print log(-1) }")
    }

    @Test("expRange") func expRange() async throws {
      try await run(output: "inf\n", args: "BEGIN { print exp(1000) }")
    }

    // length() with extra arguments is a non-fatal warning in real awk — it prints
    // to stderr and keeps running (using only the first argument), exiting 0.
    @Test("lengthTooManyArgs") func lengthTooManyArgs() async throws {
      try await run(error: /too many arguments/,
                    args: #"BEGIN { length("abc", "def") }"#)
    }

    // A bare `print` before any record has been read (e.g. in BEGIN) is not an
    // error — real awk just prints a blank line, matching an empty $0.
    @Test("barePrintInBegin") func barePrintInBegin() async throws {
      try await run(output: "\n", args: "BEGIN { print }")
    }

    // Calling a user-defined function with more arguments than it declares is also
    // a non-fatal warning — the call proceeds using only the declared parameters.
    @Test("functionCalledWithTooManyArgs") func functionCalledWithTooManyArgs() async throws {
      try await run(error: /called with/,
                    args: """
                      function mp(){ cnt++;}
                      BEGIN {  mp(xx) }
                      """)
    }

    @Test("third", arguments: [
      "BEGIN{\"date\" | getline}",
      "BEGIN{print >\"foo\"}",
      "BEGIN{print >>\"foo\"}",
      "BEGIN{print | \"foo\"}",
      "BEGIN{system(\"date\")}",
    ]) func third(_ s : String) async throws {
      try await run(status: 2,
                    error: /is unsafe/,
                    args: "-safe", s)
    }
  }
}
