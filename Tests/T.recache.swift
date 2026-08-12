
import ShellTesting

extension awkTest {

  @Suite("T.recache") struct Trecache : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    // since the Swift version does not use an RE cache,
    // it is not clear what (if anything) this is testing
    @Test("first") func first() async throws {
      let prog = """
        BEGIN {
                #
                # Fill up DFA cache with run-time REs that have all been
                # used twice.
                #
                CACHE_SIZE=64
                for(i = 0; i < CACHE_SIZE; i++) {
                        for(j = 0; j < 2; j++) {
                                "" ~ i "";
                        }
                }
                #
                # Now evalutate an expression that uses two run-time REs
                # that have never been used before.  The second RE will
                # push the first out of the cache while the first RE is 
                # still needed.
                #
                x = "a"
                reg1 = "[Aa]"
                reg2 = "A"
                sub(reg1, x ~ reg2 ? "B" : "b", x)

                print x
        }
        
        """
      try await run(output: "b\n", args: prog)
    }
  }
}
