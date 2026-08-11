
import ShellTesting

extension awkTest {

  @Suite("T.misc") struct Tmisc : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
