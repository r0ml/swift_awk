
import ShellTesting

extension awkTest {

  @Suite("T.expr") struct Texpr : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
