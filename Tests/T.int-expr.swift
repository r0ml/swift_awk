
import ShellTesting

extension awkTest {

  @Suite("T.intexpr") struct Tintexpr : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
