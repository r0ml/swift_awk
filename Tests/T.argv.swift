// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026
import ShellTesting

extension awkTest {

  @Test("T.argv.1") func T_argv_1() async throws {
    let a = """
    
    BEGIN {
      for (i = 1; i < ARGC-1; i++)
        printf "%s ", ARGV[i]
      if (ARGC > 1)
        printf "%s", ARGV[i]
      printf "\\n"
      exit
    }
    """
    let ls = try FilePath("/usr/").listDirectory()
    let env = ["LC_CTYPE": "en_US.LATIN1"]//, "SHELLDEBUGGING" : "1"]

               try await run( output: ls.joined(separator: " ") + "\n", args: [a]+ls, env: env)
  }

  @Test("T.argv.2") func T_argv_2() async throws {
    let a = """
    BEGIN {
    for (i = 1; i < ARGC; i++) {
      printf "%s", ARGV[i]
      if (i < ARGC-1)
        printf " "
    }
    printf "\\n"
    exit
    }
    """
    let ls = try FilePath("/usr/").listDirectory()
    let env = ["LC_CTYPE": "en_US.LATIN1"]//, "SHELLDEBUGGING" : "1"]

    try await run( output: ls.joined(separator: " ") + "\n", args: [a]+ls, env: env)
  }

  @Test("T.argv.3") func T_argv_3() async throws {
    let a = """
    BEGIN {
      print ARGC
      ARGV[ARGC-1] = ""
      for (i=0; i < ARGC; i++)
        print ARGV[i]
      exit
    }
"""
    let op = """
5
\(cmd)
a
bc
def


"""

    try await run( output: op, args: a, "a", "bc", "def", "gh")
  }

  @Test("T.argv.4") func T_argv_4() async throws {
    let ip = """
    1
    2
    3
    """


    let env = ["LC_CTYPE": "en_US.LATIN1"] //, "SHELLDEBUGGING" : "1"]


    try await run( withStdin: ip, output: "foo1\nfoo2\nfoo3\n", args: "{print L $0}", "L=foo", env: env)
  }

  @Test("T.argv.5") func T_argv_5() async throws {
    let ip = try tmpfile("foo", """
    1
    2
    3
    """)
    defer { rm(ip) }

    try await run( output: "foo1\nfoo2\nfoo3\n", args: "{print L $0}", "L=foo", ip)
  }

  @Test("T.argv.6") func T_argv_6() async throws {
    let ip = """
    1
    2
    3
    """

    try await run( withStdin: ip, output: "foo1\nfoo2\nfoo3\n", args: "{print L $0}", "L=foo", "-")
  }

  @Test("T.argv.7") func T_argv_7() async throws {
    let ip = try tmpfile("foo0", """
    1
    2
    3
    """)
    defer { rm(ip) }

    try await run( withStdin: ip, output: "foo1\nfoo2\nfoo3\nglop1\nglop2\nglop3\n", args: "{print L $0}", "L=foo", ip, "L=glop", ip )
  }

  @Test("T.argv.8") func T_argv_8() async throws {
    let ip = try tmpfile("foo8", """
    1
    2
    3
    """)


//    let env = ["LC_CTYPE": "en_US.LATIN1", "SHELLDEBUGGING" : "1"]
    try await run( output: "111\n112\n113\n221\n222\n223\n", args: "{print L $0}", "L=11", ip, "L=22", ip) //, env: env)
  }

  @Test("T.argv.9") func T_argv_9() async throws {


    try await run( output: "3.345\n", args: "BEGIN { print ARGV[1] + ARGV[2] }", "1", "2.345")
  }

  @Test("T.argv.10") func T_argv_10() async throws {


    let env = ["x1":"1", "x2":"2.345"]
    try await run( output: "3.345\n", args: "BEGIN { print ENVIRON[\"x1\"] + ENVIRON[\"x2\"] }", "1", "2.345", env: env)
  }


  @Test("T.argv.11") func T_argv_11() async throws {
    let foo1 = try tmpfile("foo1", "foo1\n")
        let foo2 = try tmpfile("foo2", "foo2\n")
        let foo3 = try tmpfile("foo3", "foo3\n")

    defer { rm(foo1, foo2, foo3) }

    try await run( output: "foo1\nfoo3\n", args: """
    BEGIN { ARGV[2] = "" }
                   { print }
    """, foo1, foo2, foo3)
  }

  @Test("T.argv.12") func T_argv_12() async throws {
    let foo1 = try tmpfile("hi", "foo1\n")
    let foo2 = try tmpfile("foo2")
    rm(foo2)
    try foo1.rename(to: foo2)

    defer { rm(foo2) }

    try await run( output: "\nfoo2\n", args: """
    BEGIN { ARGV[1] = "foo2" ; print FILENAME }
         { print FILENAME }
    """, "foo1", cd: tmpdir() )
  }

  @Test("T.argv.13") func T_argv_13() async throws {
    let f1 = """
ARGV[3] is /dev/null
ARGV[0] is \(cmd)
ARGV[1] is /dev/null

"""

    let foo1 = try tmpfile("foo1", f1)
    let prog = """
    BEGIN {   # this is a variant of arnolds original example
            ARGV[1] = "/dev/null"
            ARGV[2] = "glotch"  # file open must skipped deleted argv
            ARGV[3] = "/dev/null"
            ARGC = 4
            delete ARGV[2]
    }
    # note that input is read here
    END {
            for (i in ARGV)
                    printf("ARGV[%d] is %s\\n", i, ARGV[i])
    }
    """

    defer { rm(foo1) }

    try await run( output: f1, args: prog)
  }



}
