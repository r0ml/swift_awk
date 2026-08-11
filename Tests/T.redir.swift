
import ShellTesting

extension awkTest {

  @Suite("T.redir") struct Tredir : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
