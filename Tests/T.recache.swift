
import ShellTesting

extension awkTest {

  @Suite("T.recache") struct Trecache : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
