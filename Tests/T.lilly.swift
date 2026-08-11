
import ShellTesting

extension awkTest {

  @Suite("T.lilly") struct Tlilly : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
//      let env = [ "SHELLDEBUGGING":"1" ]
      let prog = """
        /./ {
          print $0 >"foo"
          close("foo")
          print "###", NR, $0
          system("\(cmd) -f foo <\\"lilly.ifile\\" ")
        }        
        """
      let lilly = try inFile("lilly.progs")
      let lo = try fileContents("lilly.out")
      try await run(withStdin: lilly, output: lo, args: prog,
                    // env: env,
                    cd: geturl())

    }
  }
}
