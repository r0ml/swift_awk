
import ShellTesting

extension awkTest {

  @Suite("T.re") struct Tre : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
