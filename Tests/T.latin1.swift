
import ShellTesting

extension awkTest {

  @Suite("T.latin1") struct Tlatin1 : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
