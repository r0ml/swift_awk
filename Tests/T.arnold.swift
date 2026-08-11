
import ShellTesting

extension awkTest {

  @Suite("T.arnold") struct Tarnold : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
