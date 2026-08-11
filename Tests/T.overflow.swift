
import ShellTesting

extension awkTest {

  @Suite("T.overflow") struct Toverflow : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
