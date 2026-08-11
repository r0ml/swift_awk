
import ShellTesting

extension awkTest {

  @Suite("T.func") struct Tfunc : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
