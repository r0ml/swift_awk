
import ShellTesting

extension awkTest {

  @Suite("T.exprconv") struct Texprconv : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = """
        BEGIN {  x = (1 > 0); print x
          x = (1 < 0); print x
          x = (1 == 1); print x
          print ("a" >= "b")
          print ("b" >= "a")
          print (0 == 0.0)
          # x = ((1 == 1e0) && (1 == 10e-1) && (1 == .1e2)); print x
          exit
        }
        
        """
      let output = """
        1
        0
        1
        0
        1
        1
        
        """
      
      try await run(output: output,
                    args: prog)
    }
  }
}
