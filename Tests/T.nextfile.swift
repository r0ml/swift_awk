
import ShellTesting

extension awkTest {

  @Suite("T.nextfile") struct Tnextfile : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
