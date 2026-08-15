
import ShellTesting

extension awkTest {

  @Suite("T.clv") struct Tclv : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      try await run(withStdin: "hello\ngoodbye\n",
                    output: "0\n0 hello\n",
                    args: "BEGIN { x=0; print x; getline; print x, $0 }")
    }

    @Test("second") func second() async throws {
      try await run(withStdin: "hello\ngoodbye\n",
                    output: "0\n1 hello\n",
                    args: "BEGIN { x=0; print x; getline; print x, $0 }",
      "x=1")
    }

    @Test("third") func third() async throws {
      try await run(withStdin: "hello\ngoodbye\n",
                    output: "0\n3 hello\n",
                    args: "BEGIN { x=0; print x; getline; print x, $0 }",
                    "x=1", "x=2", "x=3")
    }

    @Test("fourth") func fourth() async throws {
      let foo = try tmpfile("foo", "hello\ngoodbye\n")
      defer { rm(foo) }
      try await run(output: "0\n3 hello\n",
                    args: "BEGIN { x=0; print x; getline; print x, $0 }",
                    "x=1", "x=2", "x=3", foo)
    }

    @Test("fifth") func fifth() async throws {
      try await run(output: "4\n",
                    args: "BEGIN { getline; print x }",
      "x=4", "/dev/null")
    }

    @Test("sixth") func sixth() async throws {
      try await run(output: "0\n",
                    args: "BEGIN { x=0; getline <\"/dev/null\"; print x }",
      "x=5", "/dev/null")
    }

    @Test("seventh") func seventh() async throws {
      let foo = try tmpfile("foo", "xxx\nyyy\nzzz\n")
      defer { rm(foo) }
      try await run(output: "6\nend\n",
                    args: """
                      BEGIN { x=0; getline; print x }
                      END { print x }
                      """,
      "x=6", foo, "x=end")
    }

    @Test("eighth") func eighth() async throws {
      try await run(output: "0\nend\n",
                    args: """
BEGIN { x=0; getline <"/dev/null"; print x }
END { print x }
""",
                    "x=7", "/dev/null", "x=end")
    }

    @Test("ninth") func ninth() async throws {
      try await run(output: "0\nend\n",
                    args: """
BEGIN { _=0; getline <"/dev/null"; print _ }
END { print _ }
""",
                    "_=7A", "/dev/null", "_=end")
    }


    @Test("tenth") func tenth() async throws {
      try await run(status: 2,
                    error: /can't open/,
                    args: "{ print }",
                    "99_=foo",
                    "/dev/null")
    }

    // the following tests exercise -v

    @Test("eleventh") func eleventh() async throws {
      try await run(output: "123\n",
                    args: "-v", "x=123", "BEGIN { print x }")
    }

    @Test("twelfth") func twelfth() async throws {
      try await run(output: "123\n",
                    args: "-vx=123", "BEGIN { print x }")
    }

    @Test("thirteenth") func thirteenth() async throws {
      try await run(output: "123 abc 10.99\n",
                    args: "-v", "x=123",
                    "-v", "y=abc",
                    "-v", "z1=10.99",
                    "BEGIN { print x, y, z1 }")
    }

    @Test("fourteenth") func fourteenth() async throws {
  try await run(output: "123 abc 10.99\n",
                args: "-vx=123",
                "-vy=abc", "-vz1=10.99",
                "BEGIN { print x, y, z1 }")
}

    @Test("fifteenth") func fifteenth() async throws {
      try await run(output: "123 abc 10.99\n",
                    args: "-v", "x=123",
                    "-v", "y=abc", "-v", "z1=10.99",
                    "--", "BEGIN { print x, y, z1 }")
    }

    @Test("sixteenth") func sixteenth() async throws {
      let foo0 = try tmpfile("foo0", "BEGIN { print x, y, z1 }\n")
      let foo1 =  "123 abc 10.99\n"
      defer { rm(foo0) }
      try await run(output: foo1,
                    args: "-v", "x=123", "-v", "y=abc",
                    "-f", foo0,
      "-vz1=10.99" )
    }

    @Test("seventeenth") func seventeenth() async throws {
      let foo0 = try tmpfile("foo0", "BEGIN { print x, y, z1 }\n")
      let foo1 =  "123 abc 10.99\n"
      defer { rm(foo0) }
      try await run(output: foo1,
                    args: "-vx=123", "-vy=abc",
                    "-f", foo0,
      "-vz1=10.99" )
    }

    @Test("eighteenth") func eighteenth() async throws {
      let foo0 = try tmpfile("foo0", "BEGIN { print x, y, z1 }\n")
      let foo1 =  "123 abc 10.99\n"
      defer { rm(foo0) }
      try await run(output: foo1,
                    args: "-f", foo0,
                    "-v", "x=123", "-v", "y=abc",
      "-v", "z1=10.99" )
    }


    @Test("twenty") func twenty() async throws {
      let foo0 = try tmpfile("foo0", """
BEGIN { print x, y, z1 }
END { print x }
""")
      let foo1 =  "123 abc 10.99\n4567\n"
      defer { rm(foo0) }
      try await run(output: foo1,
                    args: "-f", foo0,
                    "-v", "x=123", "-v", "y=abc",
      "-v", "z1=10.99",
      "/dev/null", "x=4567", "/dev/null")
    }

    @Test("twentyone") func twentyone() async throws {
      let foo0 = try tmpfile("foo0", """
BEGIN { print x, y, z1 }
END { print x }
""")
      let foo1 =  "123 abc 10.99\n4567\n"
      defer { rm(foo0) }
      try await run(output: foo1,
                    args: "-f", foo0,
                    "-vx=123", "-vy=abc",
      "-vz1=10.99", "/dev/null", "x=4567", "/dev/null" )
    }

    @Test("twentytwo") func twentytwo() async throws {
      let foo0 = try tmpfile("foo0", """
BEGIN { print x, y, z1 }
NR==1 { print x }
""")
      let foo1 =  "123 abc 10.99\n4567\n"
      defer { rm(foo0) }
      try await run(output: foo1,
                    args:
                    "-v", "x=123", "-v", "y=abc",
      "-v", "z1=10.99", "-f", foo0, "x=4567", "/etc/passwd" )
    }

    @Test("twentythree") func twentythree() async throws {
      let foo0 = try tmpfile("foo0", """
BEGIN { print x, y, z1 }
NR==1 { print x }
""")
      let foo1 =  "123 abc 10.99\n4567\n"
      defer { rm(foo0) }
      try await run(output: foo1,
                    args:
                    "-vx=123", "-vy=abc",
      "-vz1=10.99", "-f", foo0, "x=4567", "/etc/passwd" )
    }


    @Test("twentyfour") func twentyfour() async throws {
      try await run(withStdin: "hello\n",
                    output: "a\\\\b\\z\n",
                    args: "{print x}",
  "x=\u{61}\\\\\u{62}\\z")
    }


    @Test("twentyfive") func twentyfive() async throws {
      try await run(withStdin: "hello\n",
                    output: "a\nz\n",
                    args: "{print x}",
                    "x=a\nz")
    }

    @Test("twentysix") func twentysix() async throws {
      let x = try await DarwinProcess().run(cmd, args: """
        BEGIN { printf("a%c%c%ca\n", "\u{07}", "\r", "\u{c}") )
        """)
      let y = try await DarwinProcess().run(cmd, withStdin: "hello\n", args:
                                              "{print x}", "x=a\\b\\r\\fz")
      #expect(x.data == y.data)
    }



    @Test("twentyseven") func twentyseven() async throws {
      try await run(status: 2,
                    error: /invalid -v option argument/,
                    args: "-vx",
                    "BEGIN { print x }")
    }

    @Test("twentyeight") func twentyeight() async throws {
      try await run(status: 2,
                    error: /invalid -v option argument/,
                    args: "-v", "x",
                    "BEGIN { print x }")
    }


  }
}
