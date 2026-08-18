
import ShellTesting

extension awkTest {

  @Suite("T.overflow") struct Toverflow : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let foo1 = try tmpfile("foo1","")
      let prog = """
        BEGIN {
           for (i = 0; i < 1000; i++) printf("abcdefghijklmnopqsrtuvwxyz") >>"\(foo1)"
           printf("\n") >>"\(foo1)"
           exit
        }
        
        """
      try await run(output: foo1, args: "{print}", foo1)
      
    }
    
  }
}
