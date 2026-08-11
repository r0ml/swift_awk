
import ShellTesting

extension awkTest {

  @Suite("T.csconcat") struct Tcsconcat : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
