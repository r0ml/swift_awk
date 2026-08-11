
import ShellTesting

extension awkTest {

  @Suite("T.exprconv") struct Texprconv : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
