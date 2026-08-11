
import ShellTesting

extension awkTest {

  @Suite("T.split") struct Tsplit : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
