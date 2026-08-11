
import ShellTesting

extension awkTest {

  @Suite("T.multibyte") struct Tmultibyte : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
