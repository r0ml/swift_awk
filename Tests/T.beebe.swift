
import ShellTesting

extension awkTest {

  @Suite("T.beebe") struct Tbeebe : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
