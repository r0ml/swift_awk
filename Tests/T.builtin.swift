
import ShellTesting

extension awkTest {

  @Suite("T.builtin") struct Tbuiltin : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
