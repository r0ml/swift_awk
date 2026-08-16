
import ShellTesting

extension awkTest {

  @Suite("T.func") struct Tfunc : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = """
        # tests whether function returns sensible type bits

        function assert(cond) { # assertion
            if (cond) print 1; else print 0
        }

        function i(x) { return x }

        { m=$1; n=i($2); assert(m>n) }

        """
      let input = """
        10 2
        2 10
        10 10
        10 1e1
        1e1 9
        
        """
      
      let output = """
        1
        0
        0
        0
        1
        
        """
      
      try await run(withStdin: input, output: output,
                    args: prog)
    }
    
    @Test("second") func second() async throws {
      let prog = """
        function test1(array) { array["test"] = "data" }
        function test2(array) { return(array["test"]) }
        BEGIN { test1(foo); print "data: " test2(foo) }

        """
      try await run(output: "data: data\n",
                    args: prog)
    }
    
    @Test("third") func third() async throws {
      let prog = """
        BEGIN  { code() }
        END  { codeout("x") }
        function code() { ; }
        function codeout(ex) { print ex }

        """
      try await run(output: "x\n",
                    args: prog, "/dev/null")
    }
    
    @Test("fourth") func fourth() async throws {
      let prog = """
        BEGIN { unireghf() }

        function unireghf(hfeed) {
          hfeed[1]=0
          rcell("foo",hfeed)
          hfeed[1]=0
          rcell("bar",hfeed)
        }

        function rcell(cellname,hfeed) {
          print cellname
        }

        """
      try await run(output: "foo\nbar\n",
                    args: prog)      
    }
    
    @Test("fifth") func fifth() async throws {
      let prog = """
        function f(n) {
          if (n <= 1)
            return 1
          else
            return n * f(n-1)
        }
        { print f($1) }

        """
      let input = """
        0
        1
        2
        3
        4
        5
        6
        7
        8
        9
        
        """

      let output = """
        1
        1
        2
        6
        24
        120
        720
        5040
        40320
        362880
        
        """
      
      try await run(withStdin: input, output: output,
                    args: prog)
    }
    
    @Test("sixth") func sixth() async throws {
      let prog = """
        function ack(m,n) {
          k = k+1
          if (m == 0) return n+1
          if (n == 0) return ack(m-1, 1)
          return ack(m-1, ack(m, n-1))
        }
        { k = 0; print ack($1,$2), "(" k " calls)" }
        
        """
      
      let input = """
        0 0
        1 1
        2 2
        3 3
        3 4
        3 5
        
        """
      
      let output = """
        1 (1 calls)
        3 (4 calls)
        7 (27 calls)
        61 (2432 calls)
        125 (10307 calls)
        253 (42438 calls)
        
        """
      
      try await run(withStdin: input, output: output,
                    args: prog)
    }
    
    @Test("seventh") func seventh() async throws {
      let prog = """
        END { print "end" }
        { print fib($1) }
        function fib(n) {
          if (n <= 1) return 1
          else return add(fib(n-1), fib(n-2))
        }
        function add(m,n) { return m+n }
        BEGIN { print "begin" }
        
        """
      
      let input = """
        1
        3
        5
        10
        
        """
      
      let output = """
        begin
        1
        3
        8
        89
        end
        
        """
      
      try await run(withStdin: input, output: output,
                    args: prog)
    }

    @Test("eighth") func eighth() async throws {
      let prog = """
        function foo() {
          for (i = 1; i <= 2; i++)
            return 3
          print "should not see this\u{7}"
        }
        BEGIN { foo(); exit }
        
        """
      try await run(output: "",
                    args: prog)
    }

    @Test("ninth") func ninth() async throws {
      let prog = """
        BEGIN   { eprocess("eqn", "x", contig) 
            process("tbl" )
            eprocess("eqn" "2", "x", contig) 
          }
        function eprocess(file, first, contig) {
          print file
        }
        function process(file) {
          close(file)
        }
        
        """
      try await run(output: "eqn\neqn2\n",
                    args: prog)
    }

    @Test("tenth") func tenth() async throws {
      let prog = """
        function f() { n = 1; exit }
          BEGIN { n = 0; f(); n = 2 }; END { print n}
        
        """
      try await run(output: "1\n",
                    args: prog)
    }

    @Test("eleventh") func eleventh() async throws {
      let prog = """
        BEGIN {  n = 10
          for (i = 1; i <= n; i++)
          for (j = 1; j <= n; j++)
            x[i,j] = n * i + j
          for (i = 1; i <= n; i++)
          for (j = 1; j <= n; j++)
            if ((i,j) in x)
              k++
          print (k == n^2)
              }
        
        """
      try await run(output: "1\n", args: prog)
    }

    @Test("twelfth") func twelfth() async throws {
      let prog = """
        
        function foo() { i = 0 }
                BEGIN { x = foo(); printf "<%s> %d\\n", x, x }
        
        """
      try await run(output: "<> 0\n", error: "", args: prog)
    }
    
  }
}
