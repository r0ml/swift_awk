
import ShellTesting

extension awkTest {

  @Suite("T.errmsg") struct Terrmsg : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
