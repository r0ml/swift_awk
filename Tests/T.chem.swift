
import ShellTesting

extension awkTest {

  @Suite("T.chem") struct Tchem : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
