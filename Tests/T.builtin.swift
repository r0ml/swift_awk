
import ShellTesting

extension awkTest {

  @Suite("T.builtin") struct Tbuiltin : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = "BEGIN { print index(123, substr(123, 2)) }"
      try await run(output: "2\n", args: prog)
    }

    @Test("second") func second() async throws {
      let prog = """
BEGIN {
  pi = 2 * atan2(1, 0)
  printf("%.5f %.3f %.3f %.5f %.3f\\n",
    pi, sin(pi), cos(pi/2), exp(log(pi)), log(exp(10)))
}
"""
      let output = "3.14159 0.000 0.000 3.14159 10.000\n"
      try await run(output: output, args: prog)
    }

// the third test was skipped because it uses rand()

    @Test("third") func third() async throws {

      let foo1 = try tmpfile("foo1")
      let foo2 = try tmpfile("foo2")
      let prog = """
  BEGIN {
    s = srand(1)  # set a real random start
    for (i = 1; i <= 10; i++)
      print rand() >"\(foo1)"
    srand(s)  # reset it
    for (i = 1; i <= 10; i++)
      print rand() >"\(foo2)"
  }
  """
      try await run(args: prog, cd: tmpdir()) { k in
        #expect(k.code == 0)
        let o1 = try foo1.readAsString()
        let o2 = try foo2.readAsString()
        #expect(o1 == o2)
        rm(foo1, foo2)
      }
    }


    @Test("fourth") func fourth() async throws {
      let prog = #"{ printf("%s|%s|%s\n", tolower($0), toupper($0), $0)}"#
      let output = "hello, world!|HELLO, WORLD!|hello, WORLD!\n"
      try await run(withStdin: "hello, WORLD!\n", output: output, args: prog)
    }


    // five is the Dürst
    @Test("five", .disabled("""
                            POSIX says the answer should be "0,01", but Awk says "0.01" because Awk's printf %g ignores LC_NUMERIC
                            """)) func five() async throws {
      let env = ["LANG":"de_DE.UTF-8" ]
      try await run(withStdin: "Dürst\n", output: "dürst|DÜRST|Dürst\n", args: "{ printf(\"%s|%s|%s\\n\", tolower($0), toupper($0), $0)}", env: env)
      let env2=["LC_NUMERIC":"de_DE.UTF-8"]
      try await run(output: "0.01\n", args: "BEGIN { print 0.01 }", env: env2)
    }


    @Test("six", .disabled("""
          // The original test was %d, but the second argument
          //     SHOULD NOT be used in that case.
          // -- but the alternative is
          // that the arguments should be evaluated even
          // if they are not used
      """

    )) func six() async throws {
      let prog = """
        BEGIN {
          j = 1; sprintf("%d", 99, ++j)  # does j get incremented?
          if (j != 2) {
        print j
            print "BAD: T.builtin (printf arg list not evaluated)"
        exit(2)
        }
        }
        """
      try await run(output: "", args: prog)
    }

          @Test("seven", .disabled("""
            If the second arg of substr is not needed
            (the start is past the end, then it is not
            evaluated.  Should this be an error?
            """)) func seven() async throws {
      let prog = """
        BEGIN {
          j = 1; substr("", 1, ++j)  # does j get incremented?
          if (j != 2) {
            print "BAD: T.builtin (substr arg list not evaluated)"
        exit(2)
        }
        }
        """
      try await run(output: "", args: prog)
    }

    @Test("eight", .disabled("""
      sub arguments not evaluated
      """)) func eight() async throws {
let prog = """
  BEGIN {
    j = 1; sub(/1/, ++j, z)  # does j get incremented?
    if (j != 2) {
      print "BAD: T.builtin (sub() arg list not evaluated)"
  exit(2)
  }
  }
  """
try await run(output: "", args: prog)
}


    @Test("nine", .disabled("""
      Excess arguments are not evaluated
      """)) func nine() async throws {
      let prog = """
        BEGIN {
          j = 1; length("zzzz", ++j, ++j)  # does j get incremented?
          if (j != 3) {
            print "BAD: T.builtin (excess length args not evaluated)"
        exit 2
        }
        }
        """

      try await run(output: "", args: prog)
    }

    @Test("ten") func ten() async throws {
      let prog = "{ n = split($0, x); print length(x) }"
      try await run(withStdin: "a\na b\na b c\n", output: "1\n2\n3\n", args: prog)
    }

    @Test("eleven") func eleven() async throws {
      let prog = """
        BEGIN {
            print "A\
        B";
            print "CD"
        }        
        """
      let foo0 = try tmpfile("foo1", prog)
      let foo2 = """
        AB
        CD
        
        """
      defer { rm(foo0) }
      try await run(output: foo2, args: "-f", foo0, "/devv/null")
    }
  }
}
