
import ShellTesting

extension awkTest {

  @Suite("T.delete") struct Tdelete : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let foo0 = try tmpfile("foo0", """
        '1 2 3 4
        1 2 3
        1

        
        """)
      let prog = """
        {  n = split($0, x)
          delete x[1]
          n1 = 0;  for (i in x) n1++
          delete x; 
          n2 = 0; for (i in x) n2++
          print n, n1, n2
        }     
        """

      let outp = """
        4 3 0
        3 2 0
        1 0 0
        0 0 0
        
        """
      defer { rm(foo0) }
      try await run(output: outp, args: prog, foo0)
    }
  }
}
