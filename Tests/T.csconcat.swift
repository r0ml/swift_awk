
import ShellTesting

extension awkTest {

  @Suite("T.csconcat") struct Tcsconcat : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let prog = """
        BEGIN {
          $0 = "aaa"
          print "abcdef" " " $0
        }
        BEGIN { print "hello" "world"; print helloworld }
        BEGIN {
           print " " "hello"
           print "hello" " "
           print "hello" " " "world"
           print "hello" (" " "world")
        }

        """
      let foo2 = """
        abcdef aaa
        helloworld

         hello
        hello 
        hello world
        hello world
        
        """

      try await run(output: foo2, args: prog)
    }
  }
}
